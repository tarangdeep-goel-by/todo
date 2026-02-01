import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:todo/data/database/tables.dart';

part 'database.g.dart';

/// Main database class
@DriftDatabase(tables: [Tasks])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  /// Get tasks by category
  Future<List<TaskData>> getTasksByCategory(String category) {
    return (select(tasks)
          ..where((t) => t.category.equals(category))
          ..orderBy([
            (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)
          ]))
        .get();
  }

  /// Get tasks by parent ID
  Future<List<TaskData>> getTasksByParent(String? parentId) {
    if (parentId == null) {
      return (select(tasks)
            ..where((t) => t.parentId.isNull())
            ..orderBy([
              (t) =>
                  OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)
            ]))
          .get();
    } else {
      return (select(tasks)
            ..where((t) => t.parentId.equals(parentId))
            ..orderBy([
              (t) =>
                  OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)
            ]))
          .get();
    }
  }

  /// Get single task by ID
  Future<TaskData?> getTaskById(String id) {
    return (select(tasks)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Insert task
  Future<int> insertTask(TasksCompanion task) {
    return into(tasks).insert(task);
  }

  /// Update task
  Future<bool> updateTask(TasksCompanion task) {
    return update(tasks).replace(task);
  }

  /// Delete task
  Future<int> deleteTask(String id) {
    return (delete(tasks)..where((t) => t.id.equals(id))).go();
  }

  /// Get all descendants of a task (recursive)
  Future<List<TaskData>> getAllDescendants(String taskId) async {
    final descendants = <TaskData>[];
    final queue = [taskId];

    while (queue.isNotEmpty) {
      final currentId = queue.removeAt(0);
      final children = await getTasksByParent(currentId);

      descendants.addAll(children);
      queue.addAll(children.map((t) => t.id));
    }

    return descendants;
  }

  /// Batch update task status
  Future<void> batchUpdateStatus(
      List<String> taskIds, String status, DateTime completedAt) async {
    await batch((batch) {
      for (final id in taskIds) {
        batch.update(
          tasks,
          TasksCompanion(
            status: Value(status),
            completedAt: Value(completedAt),
            updatedAt: Value(DateTime.now()),
          ),
          where: (t) => t.id.equals(id),
        );
      }
    });
  }
}

/// Open database connection
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'todo.db'));
    return NativeDatabase(file);
  });
}
