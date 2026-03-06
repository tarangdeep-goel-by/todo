import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'sync_queue_dao.g.dart';

@DriftAccessor(tables: [SyncQueue])
class SyncQueueDao extends DatabaseAccessor<AppDatabase>
    with _$SyncQueueDaoMixin {
  SyncQueueDao(super.db);

  Future<int> enqueue({
    required String entityType,
    required String entityId,
    required String action,
    required String payload,
  }) =>
      into(syncQueue).insert(SyncQueueCompanion.insert(
        entityType: entityType,
        entityId: entityId,
        action: action,
        payload: payload,
        createdAt: DateTime.now(),
      ));

  Future<List<SyncQueueData>> getPending() =>
      (select(syncQueue)
            ..where((e) => e.failed.equals(false))
            ..orderBy([(e) => OrderingTerm.asc(e.id)]))
          .get();

  Future<int> pendingCount() async {
    final count = countAll();
    final query = selectOnly(syncQueue)
      ..where(syncQueue.failed.equals(false))
      ..addColumns([count]);
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  Future<void> ack(int id) =>
      (delete(syncQueue)..where((e) => e.id.equals(id))).go();

  Future<void> markFailed(int id, String error) =>
      (update(syncQueue)..where((e) => e.id.equals(id))).write(
        SyncQueueCompanion(
          failed: const Value(true),
          lastError: Value(error),
        ),
      );

  Future<void> incrementRetry(int id, String error) =>
      customStatement(
        'UPDATE sync_queue SET retry_count = retry_count + 1, last_error = ? WHERE id = ?',
        [error, id],
      );

  Future<void> markFailedForEntity(String entityId) =>
      (update(syncQueue)..where((e) => e.entityId.equals(entityId))).write(
        const SyncQueueCompanion(failed: Value(true)),
      );

  Future<List<SyncQueueData>> getAllForEntity(String entityId) =>
      (select(syncQueue)
            ..where((e) => e.entityId.equals(entityId))
            ..orderBy([(e) => OrderingTerm.asc(e.id)]))
          .get();

  Future<int> deleteAllForEntity(String entityId) =>
      (delete(syncQueue)..where((e) => e.entityId.equals(entityId))).go();

  Future<int> deleteAll() => delete(syncQueue).go();
}
