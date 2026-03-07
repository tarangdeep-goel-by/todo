import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'task_dao.g.dart';

@DriftAccessor(tables: [LocalTasks])
class TaskDao extends DatabaseAccessor<AppDatabase> with _$TaskDaoMixin {
  TaskDao(super.db);

  Future<List<LocalTask>> getAllTasks() => select(localTasks).get();

  Future<LocalTask?> getTaskById(String id) =>
      (select(localTasks)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<void> upsertTask(LocalTasksCompanion entry) =>
      into(localTasks).insertOnConflictUpdate(entry);

  Future<void> upsertTasks(List<LocalTasksCompanion> entries) async {
    await batch((b) {
      for (final entry in entries) {
        b.insert(localTasks, entry, onConflict: DoUpdate((_) => entry));
      }
    });
  }

  Future<int> deleteTask(String id) =>
      (delete(localTasks)..where((t) => t.id.equals(id))).go();

  Future<int> deleteNonPendingTasks() =>
      (delete(localTasks)..where((t) => t.pendingSync.equals(false))).go();

  Future<void> markPendingSync(String id, bool pending) =>
      (update(localTasks)..where((t) => t.id.equals(id)))
          .write(LocalTasksCompanion(pendingSync: Value(pending)));

  Future<int> getTaskCount() async {
    final count = countAll();
    final query = selectOnly(localTasks)..addColumns([count]);
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  Future<int> deleteAllTasks() => delete(localTasks).go();
}
