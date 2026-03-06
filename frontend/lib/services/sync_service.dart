import 'dart:async';
import 'dart:convert';
import '../database/app_database.dart';
import '../models/api_error.dart';
import '../models/api_response.dart';
import '../models/task.dart';
import 'api_service.dart';
import 'app_logger.dart';
import 'local_data_service.dart';

/// Background sync engine: push local mutations to server, pull server changes.
class SyncService {
  final ApiService _api;
  final LocalDataService _localDb;
  final Future<void> Function() _refreshStore;
  final _logger = AppLogger.instance;

  bool _syncing = false;
  bool _pushPending = false;
  Timer? _periodicTimer;

  SyncService({
    required ApiService api,
    required LocalDataService localDb,
    required Future<void> Function() refreshStore,
  })  : _api = api,
        _localDb = localDb,
        _refreshStore = refreshStore;

  bool get isSyncing => _syncing;

  /// Full sync cycle: push then pull then refresh store.
  Future<void> sync() async {
    if (_syncing) return;
    _syncing = true;
    try {
      await push();
      await pull();
      await _refreshStore();
    } finally {
      _syncing = false;
    }
  }

  /// Trigger a push if online. Called after every local mutation.
  void triggerPush() {
    if (_syncing) {
      _pushPending = true;
      return;
    }
    _pushOnly();
  }

  Future<void> _pushOnly() async {
    if (_syncing) return;
    _syncing = true;
    try {
      await push();
      await _refreshStore();
      if (_pushPending) {
        _pushPending = false;
        await push();
        await _refreshStore();
      }
    } finally {
      _syncing = false;
    }
  }

  /// Start periodic sync (every 15 minutes).
  void startPeriodicSync() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => sync(),
    );
  }

  /// Stop periodic sync.
  void stopPeriodicSync() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  void dispose() {
    stopPeriodicSync();
  }

  // === Queue Compaction ===

  /// Compact redundant mutations before push.
  Future<void> compact() async {
    final entries = await _localDb.getPendingMutations();
    if (entries.length < 2) return;

    // Group by entityId
    final byEntity = <String, List<SyncQueueData>>{};
    for (final e in entries) {
      byEntity.putIfAbsent(e.entityId, () => []).add(e);
    }

    for (final group in byEntity.values) {
      if (group.length < 2) continue;
      final actions = group.map((e) => e.action).toList();

      // create + delete → remove both + delete local row
      if (actions.first == 'create' && actions.last == 'delete') {
        for (final e in group) {
          await _localDb.ackMutation(e.id);
        }
        await _localDb.deleteTask(group.first.entityId);
        continue;
      }

      // Any sequence ending with delete → keep only the delete
      if (actions.last == 'delete') {
        for (var i = 0; i < group.length - 1; i++) {
          await _localDb.ackMutation(group[i].id);
        }
        continue;
      }

      // create + update(s) → merge updates into create payload
      if (actions.first == 'create') {
        if (group.length > 1) {
          var merged = jsonDecode(group.first.payload) as Map<String, dynamic>;
          for (var i = 1; i < group.length; i++) {
            if (group[i].action == 'update') {
              final update = jsonDecode(group[i].payload) as Map<String, dynamic>;
              merged = {...merged, ...update};
              await _localDb.ackMutation(group[i].id);
            }
          }
          // Re-enqueue the merged create (ack old, enqueue new)
          await _localDb.ackMutation(group.first.id);
          await _localDb.enqueueMutation(
            entityType: 'task',
            entityId: group.first.entityId,
            action: 'create',
            payload: merged,
          );
        }
        continue;
      }

      // update + update → merge into single update (latest wins)
      final updates = group.where((e) => e.action == 'update').toList();
      if (updates.length > 1) {
        var merged = <String, dynamic>{};
        for (final u in updates) {
          final payload = jsonDecode(u.payload) as Map<String, dynamic>;
          merged = {...merged, ...payload};
          await _localDb.ackMutation(u.id);
        }
        await _localDb.enqueueMutation(
          entityType: 'task',
          entityId: updates.first.entityId,
          action: 'update',
          payload: merged,
        );
      }
    }
  }

  // === Push: Local mutations → Server ===

  Future<void> push() async {
    await compact();
    final entries = await _localDb.getPendingMutations();
    if (entries.isEmpty) return;

    _logger.info('sync.push.start', logger: 'SyncService', data: {'count': entries.length});

    for (final entry in entries) {
      try {
        final payload = jsonDecode(entry.payload) as Map<String, dynamic>;
        switch (entry.action) {
          case 'create':
            final serverTask = await _api.createTask(
              CreateTaskRequest(
                title: payload['title'] as String,
                category: payload['category'] as String,
                description: payload['description'] as String?,
                parentId: payload['parent_id'] as String?,
                dueDate: payload['due_date'] != null
                    ? DateTime.parse(payload['due_date'] as String)
                    : null,
                priority: payload['priority'] as String?,
                transcription: payload['transcription'] as String? ?? payload['title'] as String,
                aiPlacementJson: payload['ai_placement_json'] as Map<String, dynamic>?,
              ),
            );
            // Update local row with server response
            await _localDb.upsertTask(serverTask, pendingSync: false);
            break;

          case 'update':
            final serverTask = await _api.updateTask(
              entry.entityId,
              UpdateTaskRequest(
                title: payload['title'] as String?,
                description: payload['description'] as String?,
                status: payload['status'] as String?,
                category: payload['category'] as String?,
                priority: payload['priority'] as String?,
                parentId: payload['parent_id'] as String?,
                completedAt: payload['completed_at'] != null
                    ? DateTime.parse(payload['completed_at'] as String)
                    : null,
                dueDate: payload['due_date'] != null
                    ? DateTime.parse(payload['due_date'] as String)
                    : null,
                estimatedHours: payload['estimated_hours'] != null
                    ? (payload['estimated_hours'] as num).toDouble()
                    : null,
              ),
            );
            await _localDb.upsertTask(serverTask, pendingSync: false);
            break;

          case 'complete':
            final serverTask = await _api.completeTask(entry.entityId);
            await _localDb.upsertTask(serverTask, pendingSync: false);
            break;

          case 'delete':
            await _api.deleteTask(entry.entityId);
            await _localDb.markPendingSync(entry.entityId, false);
            break;
        }

        // Success — remove from queue
        await _localDb.ackMutation(entry.id);
        _logger.debug('sync.push.ack', logger: 'SyncService', data: {
          'id': entry.id, 'action': entry.action, 'entity': entry.entityId,
        });

      } on ApiError catch (e) {
        _logger.error('sync.push.error', logger: 'SyncService', data: {
          'id': entry.id, 'action': entry.action, 'entity': entry.entityId,
          'error': e.toString(), 'statusCode': e.statusCode,
        });

        if (e.type == ApiErrorType.validation) {
          // Permanent failure — mark failed
          await _localDb.failMutation(entry.id, e.message);
          if (entry.action == 'create') {
            // Fail all dependent mutations for this entity
            await _localDb.failAllForEntity(entry.entityId);
          }
        } else if (e.type == ApiErrorType.auth) {
          // Auth failure — abort push entirely
          _logger.error('sync.push.auth_abort', logger: 'SyncService');
          break;
        } else if (e.statusCode == 404 &&
            (entry.action == 'update' || entry.action == 'complete' || entry.action == 'delete')) {
          // Task gone on server — harmless, clean up
          await _localDb.ackMutation(entry.id);
          await _localDb.deleteTask(entry.entityId);
        } else {
          // Transient error — increment retry, stop queue
          await _localDb.incrementRetry(entry.id, e.message);
          if (entry.retryCount + 1 >= 5) {
            await _localDb.failMutation(entry.id, 'Max retries exceeded: ${e.message}');
          } else {
            break; // Stop processing — preserve FIFO ordering
          }
        }
      } catch (e) {
        // Unexpected error — treat as transient
        _logger.error('sync.push.unexpected', logger: 'SyncService', data: {
          'id': entry.id, 'error': e.toString(),
        });
        await _localDb.incrementRetry(entry.id, e.toString());
        if (entry.retryCount + 1 >= 5) {
          await _localDb.failMutation(entry.id, 'Max retries: ${e.toString()}');
        } else {
          break;
        }
      }
    }
  }

  // === Pull: Server → Local ===

  Future<void> pull() async {
    final lastPullAt = await _localDb.getMeta('last_pull_at');
    final lastFullSyncAt = await _localDb.getMeta('last_full_sync_at');

    final needsFullSync = lastPullAt == null ||
        lastFullSyncAt == null ||
        DateTime.now().difference(DateTime.parse(lastFullSyncAt)).inHours > 24;

    if (needsFullSync) {
      await _fullSync();
    } else {
      await _deltaSync(DateTime.parse(lastPullAt));
    }
  }

  Future<void> _fullSync() async {
    _logger.info('sync.pull.full', logger: 'SyncService');

    // Paginate all tasks from server
    final allServerTasks = <Task>[];
    int offset = 0;
    const limit = 100;
    while (true) {
      final response = await _api.getTasksAdvancedWithRetry(
        limit: limit,
        offset: offset,
      );
      allServerTasks.addAll(response.tasks);
      if (!response.hasMore) break;
      offset += limit;
    }

    // Fetch categories
    final categories = await _api.getCategories();

    // Delete non-pending tasks, then insert server tasks (skip pending ones)
    await _localDb.deleteNonPendingTasks();
    for (final task in allServerTasks) {
      final isPending = await _localDb.isTaskPendingSync(task.id);
      if (!isPending) {
        await _localDb.upsertTask(task, pendingSync: false);
      }
    }
    await _localDb.replaceCategories(categories);

    final now = DateTime.now().toIso8601String();
    await _localDb.setMeta('last_pull_at', now);
    await _localDb.setMeta('last_full_sync_at', now);

    _logger.info('sync.pull.full.done', logger: 'SyncService', data: {
      'server_tasks': allServerTasks.length,
    });
  }

  Future<void> _deltaSync(DateTime checkpoint) async {
    _logger.info('sync.pull.delta', logger: 'SyncService', data: {
      'since': checkpoint.toIso8601String(),
    });

    // Fetch changed tasks since checkpoint
    final changedTasks = <Task>[];
    int offset = 0;
    const limit = 100;
    while (true) {
      final response = await _api.getTasksAdvancedWithRetry(
        updatedAtGte: checkpoint,
        limit: limit,
        offset: offset,
      );
      changedTasks.addAll(response.tasks);
      if (!response.hasMore) break;
      offset += limit;
    }

    // Fetch categories
    final categories = await _api.getCategories();

    // Apply changes
    for (final serverTask in changedTasks) {
      final isPending = await _localDb.isTaskPendingSync(serverTask.id);
      if (isPending) continue; // Local has unpushed changes — skip

      if (serverTask.archivedAt != null) {
        // Archived on server — remove from local
        await _localDb.deleteTask(serverTask.id);
      } else {
        await _localDb.upsertTask(serverTask, pendingSync: false);
      }
    }

    await _localDb.replaceCategories(categories);
    await _localDb.setMeta('last_pull_at', DateTime.now().toIso8601String());

    _logger.info('sync.pull.delta.done', logger: 'SyncService', data: {
      'changed': changedTasks.length,
    });
  }
}
