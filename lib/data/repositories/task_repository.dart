import 'package:drift/drift.dart';
import 'package:todo/data/database/database.dart';
import 'package:todo/data/models/task.dart' as model;
import 'package:todo/data/models/ai_placement.dart';
import 'package:uuid/uuid.dart';
import 'package:todo/config/env.dart';
import 'package:todo/utils/constants.dart';

/// Repository for task operations
class TaskRepository {
  final AppDatabase _db;
  final Uuid _uuid = const Uuid();

  TaskRepository(this._db);

  /// Create a new task
  Future<String> createTask({
    required String title,
    String? description,
    String? parentId,
    required model.TaskCategory category,
    required String transcription,
    required AIPlacement aiPlacement,
    String? audioFileUri,
    DateTime? dueDate,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();

    final task = TasksCompanion(
      id: Value(id),
      userId: Value(Env.defaultUserId),
      title: Value(title),
      description: Value(description),
      parentId: Value(parentId),
      category: Value(category.name),
      status: Value(model.TaskStatus.active.name),
      createdAt: Value(now),
      updatedAt: Value(now),
      dueDate: Value(dueDate),
      completedAt: const Value(null),
      audioFileUri: Value(audioFileUri),
      transcription: Value(transcription),
      aiPlacementJson: Value(aiPlacement.toJsonString()),
    );

    await _db.insertTask(task);
    return id;
  }

  /// Get task by ID
  Future<model.Task?> getTask(String id) async {
    final taskData = await _db.getTaskById(id);
    if (taskData == null) return null;
    return _mapTaskDataToModel(taskData);
  }

  /// Get tasks by category
  Future<List<model.Task>> getTasksByCategory(model.TaskCategory category) async {
    final tasks = await _db.getTasksByCategory(category.name);
    return tasks.map(_mapTaskDataToModel).toList();
  }

  /// Get child tasks of a parent
  Future<List<model.Task>> getChildTasks(String? parentId) async {
    final tasks = await _db.getTasksByParent(parentId);
    return tasks.map(_mapTaskDataToModel).toList();
  }

  /// Get all descendants of a task
  Future<List<model.Task>> getAllDescendants(String taskId) async {
    final tasks = await _db.getAllDescendants(taskId);
    return tasks.map(_mapTaskDataToModel).toList();
  }

  /// Update task
  Future<void> updateTask(
    String id, {
    String? title,
    String? description,
    String? parentId,
    model.TaskCategory? category,
    model.TaskStatus? status,
    DateTime? completedAt,
    DateTime? dueDate,
  }) async {
    await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        title: title != null ? Value(title) : const Value.absent(),
        description: description != null ? Value(description) : const Value.absent(),
        parentId: parentId != null ? Value(parentId) : const Value.absent(),
        category: category != null ? Value(category.name) : const Value.absent(),
        status: status != null ? Value(status.name) : const Value.absent(),
        completedAt: completedAt != null ? Value(completedAt) : const Value.absent(),
        dueDate: dueDate != null ? Value(dueDate) : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Mark task as completed
  Future<void> markTaskDone(String taskId) async {
    await updateTask(
      taskId,
      status: model.TaskStatus.completed,
      completedAt: DateTime.now(),
    );
  }

  /// Archive task and all descendants
  Future<void> archiveTask(String taskId) async {
    final descendants = await getAllDescendants(taskId);
    final idsToArchive = [taskId, ...descendants.map((t) => t.id)];

    await _db.batchUpdateStatus(
      idsToArchive,
      model.TaskStatus.archived.name,
      DateTime.now(),
    );
  }

  /// Delete task
  Future<void> deleteTask(String id) async {
    await _db.deleteTask(id);
  }

  /// Seed root categories
  Future<void> seedRootCategories() async {
    // Check if root tasks already exist
    final workRoot = await _db.getTaskById(Constants.workRootId);
    final personalRoot = await _db.getTaskById(Constants.personalRootId);

    if (workRoot == null) {
      final now = DateTime.now();
      await _db.insertTask(
        TasksCompanion(
          id: const Value(Constants.workRootId),
          userId: Value(Env.defaultUserId),
          title: const Value('Work'),
          description: const Value('Work-related tasks'),
          parentId: const Value(null),
          category: const Value('work'),
          status: const Value('active'),
          createdAt: Value(now),
          updatedAt: Value(now),
          transcription: const Value('Work category'),
          aiPlacementJson: Value(
            const AIPlacement(
              confidence: 1.0,
              reasoning: 'Root category',
            ).toJsonString(),
          ),
        ),
      );
    }

    if (personalRoot == null) {
      final now = DateTime.now();
      await _db.insertTask(
        TasksCompanion(
          id: const Value(Constants.personalRootId),
          userId: Value(Env.defaultUserId),
          title: const Value('Personal'),
          description: const Value('Personal tasks'),
          parentId: const Value(null),
          category: const Value('personal'),
          status: const Value('active'),
          createdAt: Value(now),
          updatedAt: Value(now),
          transcription: const Value('Personal category'),
          aiPlacementJson: Value(
            const AIPlacement(
              confidence: 1.0,
              reasoning: 'Root category',
            ).toJsonString(),
          ),
        ),
      );
    }
  }

  /// Map TaskData to Task model
  model.Task _mapTaskDataToModel(TaskData data) {
    return model.Task(
      id: data.id,
      userId: data.userId,
      title: data.title,
      description: data.description,
      parentId: data.parentId,
      category: model.TaskCategory.fromString(data.category),
      status: model.TaskStatus.fromString(data.status),
      createdAt: data.createdAt,
      updatedAt: data.updatedAt,
      dueDate: data.dueDate,
      completedAt: data.completedAt,
      audioFileUri: data.audioFileUri,
      transcription: data.transcription,
      aiPlacement: AIPlacement.fromJsonString(data.aiPlacementJson),
    );
  }
}
