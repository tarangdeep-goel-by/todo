import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';
import 'daos/task_dao.dart';
import 'daos/category_dao.dart';
import 'daos/sync_queue_dao.dart';
import 'daos/sync_meta_dao.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [LocalTasks, LocalCategories, SyncQueue, SyncMeta],
  daos: [TaskDao, CategoryDao, SyncQueueDao, SyncMetaDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'amble_cache');
  }
}
