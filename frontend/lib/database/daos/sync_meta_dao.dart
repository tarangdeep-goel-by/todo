import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'sync_meta_dao.g.dart';

@DriftAccessor(tables: [SyncMeta])
class SyncMetaDao extends DatabaseAccessor<AppDatabase>
    with _$SyncMetaDaoMixin {
  SyncMetaDao(super.db);

  Future<String?> getValue(String key) async {
    final row = await (select(syncMeta)
          ..where((m) => m.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> setValue(String key, String value) =>
      into(syncMeta).insertOnConflictUpdate(
        SyncMetaCompanion.insert(key: key, value: value),
      );

  Future<void> removeKey(String key) =>
      (delete(syncMeta)..where((m) => m.key.equals(key))).go();

  Future<int> deleteAll() => delete(syncMeta).go();
}
