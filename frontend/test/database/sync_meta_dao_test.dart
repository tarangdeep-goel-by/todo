import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  group('SyncMetaDao', () {
    test('getValue returns null for missing key', () async {
      final value = await db.syncMetaDao.getValue('nonexistent');
      expect(value, isNull);
    });

    test('setValue and getValue roundtrip', () async {
      await db.syncMetaDao.setValue('last_pull_at', '2026-01-01T00:00:00Z');
      final value = await db.syncMetaDao.getValue('last_pull_at');
      expect(value, '2026-01-01T00:00:00Z');
    });

    test('setValue overwrites existing', () async {
      await db.syncMetaDao.setValue('key', 'old');
      await db.syncMetaDao.setValue('key', 'new');
      final value = await db.syncMetaDao.getValue('key');
      expect(value, 'new');
    });

    test('removeKey deletes entry', () async {
      await db.syncMetaDao.setValue('key', 'value');
      await db.syncMetaDao.removeKey('key');
      final value = await db.syncMetaDao.getValue('key');
      expect(value, isNull);
    });

    test('deleteAll clears all entries', () async {
      await db.syncMetaDao.setValue('a', '1');
      await db.syncMetaDao.setValue('b', '2');
      await db.syncMetaDao.deleteAll();
      expect(await db.syncMetaDao.getValue('a'), isNull);
      expect(await db.syncMetaDao.getValue('b'), isNull);
    });
  });
}
