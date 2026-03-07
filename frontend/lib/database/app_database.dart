import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';

import 'tables.dart';
import 'daos/task_dao.dart';
import 'daos/category_dao.dart';
import 'daos/sync_queue_dao.dart';
import 'daos/sync_meta_dao.dart';

part 'app_database.g.dart';

/// Retrieves or creates a 256-bit encryption key for the local database.
///
/// The key is stored in platform secure storage (Keychain on iOS,
/// EncryptedSharedPreferences on Android) and persists across app launches.
Future<String> getOrCreateEncryptionKey() async {
  const storage = FlutterSecureStorage();
  const storageKey = 'amble_db_encryption_key';
  var encryptionKey = await storage.read(key: storageKey);
  if (encryptionKey == null) {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    encryptionKey =
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await storage.write(key: storageKey, value: encryptionKey);
  }
  return encryptionKey;
}

@DriftDatabase(
  tables: [LocalTasks, LocalCategories, SyncQueue, SyncMeta],
  daos: [TaskDao, CategoryDao, SyncQueueDao, SyncMetaDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? _openConnection());

  AppDatabase.encrypted(String encryptionKey)
      : super(_openEncryptedConnection(encryptionKey));

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'amble_cache.sqlite'));
      return NativeDatabase.createInBackground(
        file,
        isolateSetup: () {
          open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
        },
      );
    });
  }

  static QueryExecutor _openEncryptedConnection(String key) {
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'amble_cache_enc.sqlite'));
      return NativeDatabase.createInBackground(
        file,
        isolateSetup: () {
          open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
        },
        setup: (db) {
          db.execute("PRAGMA key = '$key'");
        },
      );
    });
  }
}
