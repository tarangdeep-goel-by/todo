import 'dart:convert';
import 'package:drift/drift.dart';
import '../database/app_database.dart';
import '../models/task.dart';
import '../models/category.dart';

class LocalDataService {
  final AppDatabase _db;

  LocalDataService(this._db);

  // --- Tasks ---

  Future<List<Task>> getAllTasks() async {
    final rows = await _db.taskDao.getAllTasks();
    return rows.map(_rowToTask).toList();
  }

  Future<void> upsertTask(Task task, {bool pendingSync = false}) =>
      _db.taskDao.upsertTask(_taskToCompanion(task, pendingSync: pendingSync));

  Future<void> upsertTasks(List<Task> tasks, {bool pendingSync = false}) =>
      _db.taskDao.upsertTasks(
        tasks.map((t) => _taskToCompanion(t, pendingSync: pendingSync)).toList(),
      );

  Future<Task?> getTaskById(String id) async {
    final row = await _db.taskDao.getTaskById(id);
    return row != null ? _rowToTask(row) : null;
  }

  Future<bool> isTaskPendingSync(String id) async {
    final row = await _db.taskDao.getTaskById(id);
    return row?.pendingSync ?? false;
  }

  Future<void> deleteTask(String id) => _db.taskDao.deleteTask(id);

  Future<void> markPendingSync(String id, bool pending) =>
      _db.taskDao.markPendingSync(id, pending);

  Future<void> deleteNonPendingTasks() => _db.taskDao.deleteNonPendingTasks();

  Future<void> deleteAllTasks() => _db.taskDao.deleteAllTasks();

  // --- Categories ---

  Future<List<Category>> getAllCategories() async {
    final rows = await _db.categoryDao.getAllCategories();
    return rows.map(_rowToCategory).toList();
  }

  Future<void> replaceCategories(List<Category> categories) =>
      _db.categoryDao.replaceAll(
        categories.map(_categoryToCompanion).toList(),
      );

  Future<void> deleteAllCategories() => _db.categoryDao.deleteAllCategories();

  // --- Sync Queue ---

  Future<int> enqueueMutation({
    required String entityType,
    required String entityId,
    required String action,
    required Map<String, dynamic> payload,
  }) =>
      _db.syncQueueDao.enqueue(
        entityType: entityType,
        entityId: entityId,
        action: action,
        payload: jsonEncode(payload),
      );

  Future<List<SyncQueueData>> getPendingMutations() =>
      _db.syncQueueDao.getPending();

  Future<int> pendingMutationCount() => _db.syncQueueDao.pendingCount();

  Future<void> ackMutation(int id) => _db.syncQueueDao.ack(id);

  Future<void> failMutation(int id, String error) =>
      _db.syncQueueDao.markFailed(id, error);

  Future<void> incrementRetry(int id, String error) =>
      _db.syncQueueDao.incrementRetry(id, error);

  Future<void> failAllForEntity(String entityId) =>
      _db.syncQueueDao.markFailedForEntity(entityId);

  Future<List<SyncQueueData>> getMutationsForEntity(String entityId) =>
      _db.syncQueueDao.getAllForEntity(entityId);

  Future<void> deleteMutationsForEntity(String entityId) =>
      _db.syncQueueDao.deleteAllForEntity(entityId);

  Future<void> deleteAllMutations() => _db.syncQueueDao.deleteAll();

  // --- Sync Meta ---

  Future<String?> getMeta(String key) => _db.syncMetaDao.getValue(key);

  Future<void> setMeta(String key, String value) =>
      _db.syncMetaDao.setValue(key, value);

  Future<void> removeMeta(String key) => _db.syncMetaDao.removeKey(key);

  Future<void> deleteAllMeta() => _db.syncMetaDao.deleteAll();

  // --- Bulk clear (sign-out) ---

  Future<void> clearAll() async {
    await _db.taskDao.deleteAllTasks();
    await _db.categoryDao.deleteAllCategories();
    await _db.syncQueueDao.deleteAll();
    await _db.syncMetaDao.deleteAll();
  }

  // --- Conversions ---

  static Task _rowToTask(LocalTask row) {
    Map<String, dynamic>? aiJson;
    if (row.aiPlacementJson != null) {
      try {
        aiJson = jsonDecode(row.aiPlacementJson!) as Map<String, dynamic>;
      } catch (_) {}
    }
    return Task(
      id: row.id,
      userId: row.userId,
      title: row.title,
      description: row.description,
      parentId: row.parentId,
      category: row.category,
      categoryId: row.categoryId,
      status: row.status,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      dueDate: row.dueDate,
      completedAt: row.completedAt,
      archivedAt: row.archivedAt,
      transcription: row.transcription,
      aiPlacementJson: aiJson,
      priority: row.priority,
      estimatedHours: row.estimatedHours,
      audioFileUri: row.audioFileUri,
    );
  }

  static LocalTasksCompanion _taskToCompanion(Task task,
      {bool pendingSync = false}) {
    String? aiJson;
    if (task.aiPlacementJson != null) {
      aiJson = jsonEncode(task.aiPlacementJson);
    }
    return LocalTasksCompanion(
      id: Value(task.id),
      userId: Value(task.userId),
      title: Value(task.title),
      description: Value(task.description),
      parentId: Value(task.parentId),
      category: Value(task.category),
      categoryId: Value(task.categoryId),
      status: Value(task.status),
      createdAt: Value(task.createdAt),
      updatedAt: Value(task.updatedAt),
      dueDate: Value(task.dueDate),
      completedAt: Value(task.completedAt),
      archivedAt: Value(task.archivedAt),
      transcription: Value(task.transcription),
      aiPlacementJson: Value(aiJson),
      priority: Value(task.priority),
      estimatedHours: Value(task.estimatedHours),
      audioFileUri: Value(task.audioFileUri),
      pendingSync: Value(pendingSync),
    );
  }

  static Category _rowToCategory(LocalCategory row) => Category(
        id: row.id,
        name: row.name,
        position: row.position,
        createdAt: row.createdAt,
      );

  static LocalCategoriesCompanion _categoryToCompanion(Category cat) =>
      LocalCategoriesCompanion.insert(
        id: cat.id,
        name: cat.name,
        position: cat.position,
        createdAt: cat.createdAt,
      );
}
