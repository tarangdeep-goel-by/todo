import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<int> _enqueue({
    String entityType = 'task',
    String entityId = 'task-1',
    String action = 'create',
    String payload = '{}',
  }) =>
      db.syncQueueDao.enqueue(
        entityType: entityType,
        entityId: entityId,
        action: action,
        payload: payload,
      );

  group('SyncQueueDao', () {
    test('enqueue and getPending returns FIFO order', () async {
      await _enqueue(entityId: 'a', action: 'create');
      await _enqueue(entityId: 'b', action: 'update');
      await _enqueue(entityId: 'c', action: 'delete');

      final entries = await db.syncQueueDao.getPending();
      expect(entries, hasLength(3));
      expect(entries[0].entityId, 'a');
      expect(entries[1].entityId, 'b');
      expect(entries[2].entityId, 'c');
    });

    test('ack removes entry', () async {
      final id = await _enqueue();
      await db.syncQueueDao.ack(id);
      final entries = await db.syncQueueDao.getPending();
      expect(entries, isEmpty);
    });

    test('markFailed excludes from getPending', () async {
      final id = await _enqueue();
      await db.syncQueueDao.markFailed(id, 'validation error');
      final entries = await db.syncQueueDao.getPending();
      expect(entries, isEmpty);
    });

    test('incrementRetry updates count', () async {
      final id = await _enqueue();
      await db.syncQueueDao.incrementRetry(id, 'timeout');
      await db.syncQueueDao.incrementRetry(id, 'timeout 2');
      final entries = await db.syncQueueDao.getPending();
      expect(entries.first.retryCount, 2);
      expect(entries.first.lastError, 'timeout 2');
    });

    test('pendingCount returns correct number', () async {
      await _enqueue(entityId: 'a');
      await _enqueue(entityId: 'b');
      final failedId = await _enqueue(entityId: 'c');
      await db.syncQueueDao.markFailed(failedId, 'err');

      final count = await db.syncQueueDao.pendingCount();
      expect(count, 2);
    });

    test('markFailedForEntity marks all entries for entity', () async {
      await _enqueue(entityId: 'x', action: 'create');
      await _enqueue(entityId: 'x', action: 'update');
      await _enqueue(entityId: 'y', action: 'create');

      await db.syncQueueDao.markFailedForEntity('x');
      final pending = await db.syncQueueDao.getPending();
      expect(pending, hasLength(1));
      expect(pending.first.entityId, 'y');
    });

    test('getAllForEntity returns ordered', () async {
      await _enqueue(entityId: 'x', action: 'create');
      await _enqueue(entityId: 'y', action: 'create');
      await _enqueue(entityId: 'x', action: 'update');

      final entries = await db.syncQueueDao.getAllForEntity('x');
      expect(entries, hasLength(2));
      expect(entries[0].action, 'create');
      expect(entries[1].action, 'update');
    });

    test('deleteAllForEntity removes entries', () async {
      await _enqueue(entityId: 'x', action: 'create');
      await _enqueue(entityId: 'x', action: 'update');
      await _enqueue(entityId: 'y', action: 'create');

      await db.syncQueueDao.deleteAllForEntity('x');
      final entries = await db.syncQueueDao.getPending();
      expect(entries, hasLength(1));
      expect(entries.first.entityId, 'y');
    });

    test('deleteAll clears everything', () async {
      await _enqueue(entityId: 'a');
      await _enqueue(entityId: 'b');
      await db.syncQueueDao.deleteAll();
      expect(await db.syncQueueDao.pendingCount(), 0);
    });
  });
}
