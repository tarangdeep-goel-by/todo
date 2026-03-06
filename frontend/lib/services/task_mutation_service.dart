import '../models/task.dart';
import '../providers/task_store_provider.dart';
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
