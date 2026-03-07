import '../models/task.dart';
import '../models/api_response.dart';
import '../providers/task_store_provider.dart';
import 'api_service.dart';
import 'local_data_service.dart';

class TaskMutationService {
  final TaskStoreNotifier _store;
  final LocalDataService _localDb;
  final void Function()? _onPush;

  TaskMutationService({
    required TaskStoreNotifier store,
    required LocalDataService localDb,
    void Function()? onPush,
  })  : _store = store,
        _localDb = localDb,
        _onPush = onPush;

  Future<void> createTask(Task optimistic, Map<String, dynamic> createPayload) async {
    _store.upsertTask(optimistic);
    await _localDb.upsertTask(optimistic, pendingSync: true);
    await _localDb.enqueueMutation(
      entityType: 'task',
      entityId: optimistic.id,
      action: 'create',
      payload: createPayload,
    );
    _onPush?.call();
  }

  Future<void> updateTask(Task optimistic, Map<String, dynamic> updatePayload) async {
    _store.upsertTask(optimistic);
    await _localDb.upsertTask(optimistic, pendingSync: true);
    await _localDb.enqueueMutation(
      entityType: 'task',
      entityId: optimistic.id,
      action: 'update',
      payload: updatePayload,
    );
    _onPush?.call();
  }

  Future<void> completeTask(Task task) async {
    _store.completeWithDescendants(task.id);
    // Persist the completed state for the task itself
    final completed = task.copyWith(
      status: 'completed',
      completedAt: DateTime.now(),
    );
    await _localDb.upsertTask(completed, pendingSync: true);
    await _localDb.enqueueMutation(
      entityType: 'task',
      entityId: task.id,
      action: 'complete',
      payload: {},
    );
    _onPush?.call();
  }

  Future<void> deleteTask(Task task) async {
    _store.removeTask(task.id);
    await _localDb.deleteTask(task.id);
    await _localDb.enqueueMutation(
      entityType: 'task',
      entityId: task.id,
      action: 'delete',
      payload: {},
    );
    _onPush?.call();
  }
}

/// Test-mode mutation service: optimistic update + direct API call (no local DB).
class TestMutationService extends TaskMutationService {
  final ApiService _api;
  final Future<void> Function()? _onCategoriesChanged;

  TestMutationService({
    required super.store,
    required ApiService api,
    Future<void> Function()? onCategoriesChanged,
  })  : _api = api,
        _onCategoriesChanged = onCategoriesChanged,
        super(localDb: _NoOpLocalDb());

  @override
  Future<void> createTask(Task optimistic, Map<String, dynamic> createPayload) async {
    // Skip optimistic insert — use API response directly to avoid duplicate
    // (test backend may not honour client-provided task_id)
    final created = await _api.createTask(CreateTaskRequest(
      taskId: optimistic.id,
      title: createPayload['title'] as String,
      category: createPayload['category'] as String? ?? 'home',
      parentId: createPayload['parent_id'] as String?,
      dueDate: createPayload['due_date'] != null ? DateTime.parse(createPayload['due_date'] as String) : null,
      priority: createPayload['priority'] as String?,
      transcription: createPayload['transcription'] as String? ?? createPayload['title'] as String,
    ));
    _store.upsertTask(created);
    // Backend auto-creates categories — refresh so node view picks them up
    await _onCategoriesChanged?.call();
  }

  @override
  Future<void> updateTask(Task optimistic, Map<String, dynamic> updatePayload) async {
    _store.upsertTask(optimistic);
    await _api.updateTask(optimistic.id, UpdateTaskRequest(
      title: updatePayload['title'] as String?,
      category: updatePayload['category'] as String?,
      parentId: updatePayload['parent_id'] as String?,
      status: updatePayload['status'] as String?,
      priority: updatePayload['priority'] as String?,
    ));
  }

  @override
  Future<void> completeTask(Task task) async {
    _store.completeWithDescendants(task.id);
    await _api.completeTask(task.id);
  }

  @override
  Future<void> deleteTask(Task task) async {
    _store.removeTask(task.id);
    await _api.deleteTask(task.id);
  }
}

/// No-op local DB for test mode (satisfies the super constructor).
class _NoOpLocalDb implements LocalDataService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
