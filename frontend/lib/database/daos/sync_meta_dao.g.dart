// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_meta_dao.dart';

// ignore_for_file: type=lint
mixin _$SyncMetaDaoMixin on DatabaseAccessor<AppDatabase> {
  $SyncMetaTable get syncMeta => attachedDatabase.syncMeta;
  SyncMetaDaoManager get managers => SyncMetaDaoManager(this);
}

class SyncMetaDaoManager {
  final _$SyncMetaDaoMixin _db;
  SyncMetaDaoManager(this._db);
  $$SyncMetaTableTableManager get syncMeta =>
      $$SyncMetaTableTableManager(_db.attachedDatabase, _db.syncMeta);
}
