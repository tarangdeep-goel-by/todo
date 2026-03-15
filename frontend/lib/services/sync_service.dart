import 'dart:async';
import 'dart:convert';
import '../database/app_database.dart';
import '../models/api_error.dart';
import '../models/api_response.dart';
import '../models/task.dart';
import '../services/connectivity_service.dart';
import 'api_service.dart';
import 'app_logger.dart';
import 'local_data_service.dart';

/// Background sync engine: push local mutations to server, pull server changes.
class SyncService {
  final ApiService _api;
  final LocalDataService _localDb;
  final ConnectivityService _connectivity;
  final Future<void> Function() _refreshStore;
  final void Function(String entityId, String action, String error)? _onMutationFailed;
  final _logger = AppLogger.instance;

  bool _syncing = false;
  bool _pushPending = false;
  Timer? _periodicTimer;

  SyncService({
    required ApiService api,
    required LocalDataService localDb,
    required ConnectivityService connectivity,
    required Future<void> Function() refreshStore,
    void Function(String entityId, String action, String error)? onMutationFailed,
  })  : _api = api,
        _localDb = localDb,
        _connectivity = connectivity,
        _refreshStore = refreshStore,
        _onMutationFailed = onMutationFailed;

  bool get isSyncing => _syncing;

  /// Full sync cycle: push then pull then refresh store.
  Future<void> sync() async {
    if (_syncing) {
      _logger.info('sync.skipped', logger: 'SyncService', data: {'reason': 'already syncing'});
      return;
    }
    _syncing = true;
    _logger.info('sync.start', logger: 'SyncService');
    try {
      await push();
      await pull();
      await _refreshStore();
      _connectivity.reportSuccess();
      _logger.info('sync.done', logger: 'SyncService');
    } catch (e) {
      if (e is ApiError &&
          (e.type == ApiErrorType.network || e.type == ApiErrorType.timeout)) {
        _connectivity.reportFailure();
      }
      _logger.error('sync.error', logger: 'SyncService', data: {
        'error': e.toString(),
      });
    } finally {
      _syncing = false;
    }
  }

  /// Trigger a push if online. Called after every local mutation.
  void triggerPush() {
    if (!_connectivity.isOnline) return; // Skip when offline
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
      // Only refresh store if no new mutations arrived during push.
      // Otherwise the push's server response (written to local DB) would
      // overwrite the newer optimistic state from the pending mutation.
      if (!_pushPending) {
        await _refreshStore();
      }
      if (_pushPending) {
        _pushPending = false;
        await push();
        await _refreshStore();
      }
    } catch (e) {
      _logger.error('sync._pushOnly.error', logger: 'SyncService', data: {
        'error': e.toString(),
      });
    } finally {
      _syncing = false;
    }
  }

  /// Sync with retry and exponential backoff.
  /// Surfaces errors to the task store after all retries exhausted.
  Future<void> syncWithRetry({int maxRetries = 3}) async {
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        await sync();
        return; // Success
      } catch (e) {
        final isLastAttempt = attempt >= maxRetries - 1;
        _logger.warning(
          'sync.retry',
          logger: 'SyncService',
          data: {
            'attempt': attempt + 1,
            'maxRetries': maxRetries,
            'error': e.toString(),
            'willRetry': !isLastAttempt,
          },
        );
        if (!isLastAttempt) {
          await Future.delayed(Duration(seconds: 1 << attempt)); // 1s, 2s, 4s
        }
      }
    }
    // All retries exhausted — surface error
    _logger.error(
      'sync.exhausted',
      logger: 'SyncService',
      data: {'maxRetries': maxRetries},
    );
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

    final beforeCount = entries.length;

    // Group by entityId
    final byEntity = <String, List<SyncQueueData>>{};
    for (final e in entries) {
      byEntity.putIfAbsent(e.entityId, () => []).add(e);
    }

    int removedCount = 0;
    for (final group in byEntity.values) {
      if (group.length < 2) continue;
      final actions = group.map((e) => e.action).toList();

      // create + delete → remove both + delete local row
      if (actions.first == 'create' && actions.last == 'delete') {
        _logger.debug('compact.create_delete', logger: 'SyncService', data: {
          'entity': group.first.entityId, 'removed': group.length,
        });
        removedCount += group.length;
        for (final e in group) {
          await _localDb.ackMutation(e.id);
        }
        await _localDb.deleteTask(group.first.entityId);
        continue;
      }

      // create + archive → remove both + delete local row (never synced)
      if (actions.first == 'create' && actions.last == 'archive') {
        _logger.debug('compact.create_archive', logger: 'SyncService', data: {
          'entity': group.first.entityId, 'removed': group.length,
        });
        removedCount += group.length;
        for (final e in group) {
          await _localDb.ackMutation(e.id);
        }
        await _localDb.deleteTask(group.first.entityId);
        continue;
      }

      // Any sequence ending with delete or archive → keep only the last action
      if (actions.last == 'delete' || actions.last == 'archive') {
        final removed = group.length - 1;
        _logger.debug('compact.keep_last', logger: 'SyncService', data: {
          'entity': group.first.entityId, 'removed': removed,
        });
        removedCount += removed;
        for (var i = 0; i < group.length - 1; i++) {
          await _localDb.ackMutation(group[i].id);
        }
        continue;
      }

      // create + update(s) → merge updates into create payload
      if (actions.first == 'create') {
        if (group.length > 1) {
          final removed = group.length - 1;
          _logger.debug('compact.merge_into_create', logger: 'SyncService', data: {
            'entity': group.first.entityId, 'merged': removed,
          });
          removedCount += removed;
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
        final removed = updates.length - 1;
        _logger.debug('compact.merge_updates', logger: 'SyncService', data: {
          'entity': updates.first.entityId, 'merged': removed,
        });
        removedCount += removed;
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

    if (removedCount > 0) {
      _logger.info('compact.done', logger: 'SyncService', data: {
        'before': beforeCount, 'after': beforeCount - removedCount, 'removed': removedCount,
      });
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
                taskId: entry.entityId,
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
            // If server assigned a different ID, remove the old local row
            if (serverTask.id != entry.entityId) {
              await _localDb.deleteTask(entry.entityId);
            }
            // Ack before checking for pending — so the current mutation
            // is removed before we ask "are there newer ones?"
            await _localDb.ackMutation(entry.id);
            // Only write server response if no newer mutations are queued
            // (prevents overwriting a concurrent undo's optimistic state)
            final createEntityId = serverTask.id != entry.entityId ? serverTask.id : entry.entityId;
            if (!await _localDb.hasPendingMutationsForEntity(createEntityId)) {
              await _localDb.upsertTask(serverTask, pendingSync: false);
            }
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
            await _localDb.ackMutation(entry.id);
            if (!await _localDb.hasPendingMutationsForEntity(entry.entityId)) {
              await _localDb.upsertTask(serverTask, pendingSync: false);
            }
            break;

          case 'complete':
            final serverTask = await _api.completeTask(entry.entityId);
            await _localDb.ackMutation(entry.id);
            if (!await _localDb.hasPendingMutationsForEntity(entry.entityId)) {
              await _localDb.upsertTask(serverTask, pendingSync: false);
            }
            break;

          case 'archive':
            final archivedTasks = await _api.archiveTask(entry.entityId);
            await _localDb.ackMutation(entry.id);
            for (final t in archivedTasks) {
              if (!await _localDb.hasPendingMutationsForEntity(t.id)) {
                await _localDb.upsertTask(t, pendingSync: false);
              }
            }
            break;

          case 'restore':
            final serverTask = await _api.restoreTask(entry.entityId);
            await _localDb.ackMutation(entry.id);
            if (!await _localDb.hasPendingMutationsForEntity(entry.entityId)) {
              await _localDb.upsertTask(serverTask, pendingSync: false);
            }
            break;

          case 'delete':
            await _api.deleteTask(entry.entityId);
            await _localDb.markPendingSync(entry.entityId, false);
            await _localDb.ackMutation(entry.id);
            break;
        }
        _connectivity.reportSuccess();
        _logger.debug('sync.push.ack', logger: 'SyncService', data: {
          'id': entry.id, 'action': entry.action, 'entity': entry.entityId,
        });

      } on ApiError catch (e) {
        _logger.error('sync.push.error', logger: 'SyncService', data: {
          'id': entry.id, 'action': entry.action, 'entity': entry.entityId,
          'error': e.toString(), 'statusCode': e.statusCode,
        });

        if (e.type == ApiErrorType.network || e.type == ApiErrorType.timeout) {
          // Offline / unreachable — stop queue, don't burn retries
          _connectivity.reportFailure();
          break;
        } else if (e.type == ApiErrorType.validation) {
          // Permanent failure — mark failed and clean up phantom data
          await _localDb.failMutation(entry.id, e.message);
          if (entry.action == 'create') {
            // Remove phantom task from local DB
            await _localDb.deleteTask(entry.entityId);
            // Fail all dependent mutations for this entity
            await _localDb.failAllForEntity(entry.entityId);
          } else if (entry.action == 'update') {
            // Revert to server version
            try {
              final serverTask = await _api.getTask(entry.entityId);
              await _localDb.upsertTask(serverTask, pendingSync: false);
            } catch (_) {
              // If we can't fetch server version, leave as-is
            }
          }
          _onMutationFailed?.call(entry.entityId, entry.action, e.message);
        } else if (e.type == ApiErrorType.auth) {
          // Auth failure — abort push entirely
          _logger.error('sync.push.auth_abort', logger: 'SyncService');
          break;
        } else if (e.statusCode == 404 &&
            (entry.action == 'update' || entry.action == 'complete' || entry.action == 'delete')) {
          // Task not found on server — check if a pending create exists
          final pendingForEntity = await _localDb.getMutationsForEntity(entry.entityId);
          final hasPendingCreate = pendingForEntity.any(
            (m) => m.action == 'create' && !m.failed && m.id != entry.id,
          );
          await _localDb.ackMutation(entry.id);
          if (hasPendingCreate) {
            // Create hasn't been pushed yet — keep local task, skip delete
            _logger.info('sync.push.404_kept', logger: 'SyncService', data: {
              'entity': entry.entityId, 'reason': 'pending_create_exists',
            });
          } else if (await _localDb.isTaskPendingSync(entry.entityId)) {
            // Task has local changes not yet on server — keep it
            _logger.info('sync.push.404_kept', logger: 'SyncService', data: {
              'entity': entry.entityId, 'reason': 'pending_sync',
            });
          } else {
            // Genuinely gone from server and no local pending — safe to delete
            _logger.info('sync.push.404_deleted', logger: 'SyncService', data: {
              'entity': entry.entityId,
            });
            await _localDb.deleteTask(entry.entityId);
          }
        } else {
          // Server error — increment retry, stop queue
          await _localDb.incrementRetry(entry.id, e.message);
          if (entry.retryCount + 1 >= 5) {
            await _localDb.failMutation(entry.id, 'Max retries exceeded: ${e.message}');
            if (entry.action == 'create') {
              await _localDb.deleteTask(entry.entityId);
            }
            _onMutationFailed?.call(entry.entityId, entry.action, 'Max retries exceeded');
          } else {
            break; // Stop processing — preserve FIFO ordering
          }
        }
      } catch (e) {
        // Unexpected error — stop queue, don't burn retries
        _logger.error('sync.push.unexpected', logger: 'SyncService', data: {
          'id': entry.id, 'error': e.toString(),
        });
        break;
      }
    }
  }

  // === Pull: Server → Local ===

  Future<void> pull() async {
    final lastPullAt = await _localDb.getMeta('last_pull_at');
    final lastFullSyncAt = await _localDb.getMeta('last_full_sync_at');

    // Force full sync if local DB is empty (e.g. after sign-out/sign-in,
    // app reinstall, or backend DB restore)
    final localTaskCount = await _localDb.getTaskCount();

    final needsFullSync = lastPullAt == null ||
        lastFullSyncAt == null ||
        localTaskCount == 0 ||
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

    // Also fetch archived tasks
    int archivedOffset = 0;
    while (true) {
      final archivedTasks = await _api.getArchivedTasks(
        limit: limit,
        offset: archivedOffset,
      );
      allServerTasks.addAll(archivedTasks);
      if (archivedTasks.length < limit) break;
      archivedOffset += limit;
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

    final now = DateTime.now().toUtc().toIso8601String();
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

      // Upsert all tasks (including archived) — store filters them by status
      await _localDb.upsertTask(serverTask, pendingSync: false);
    }

    await _localDb.replaceCategories(categories);
    await _localDb.setMeta('last_pull_at', DateTime.now().toUtc().toIso8601String());

    _logger.info('sync.pull.delta.done', logger: 'SyncService', data: {
      'changed': changedTasks.length,
    });
  }
}
