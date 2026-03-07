import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

  /// Creates an encrypted database connection.
  AppDatabase.encrypted(String encryptionKey)
      : super(_openEncryptedConnection(encryptionKey));

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'amble_cache');
  }

  static QueryExecutor _openEncryptedConnection(String key) {
    return driftDatabase(
      name: 'amble_cache_enc',
      native: DriftNativeOptions(
        setup: (db) {
          // PRAGMA key must be the first statement on the connection.
          db.execute("PRAGMA key = '$key'");
        },
      ),
    );
  }
}
