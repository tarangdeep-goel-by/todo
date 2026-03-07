import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';
import '../services/local_data_service.dart';

/// Holds the encryption key fetched during app initialization.
///
/// Must be set via [initDatabaseEncryption] before the database is accessed.
String? _encryptionKey;

/// Initializes database encryption: fetches (or creates) the key and
/// migrates from the old unencrypted database.
///
/// Pending sync mutations are transferred to the new encrypted DB before
/// deleting the old one. Cached task data is re-synced from the backend.
Future<void> initDatabaseEncryption() async {
  _encryptionKey = await getOrCreateEncryptionKey();

  // Migrate: transfer pending mutations then delete old unencrypted DB.
  const storage = FlutterSecureStorage();
  final migrated = await storage.read(key: 'amble_db_encrypted');
  if (migrated != 'true') {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final oldDbFile = File('${dir.path}/amble_cache.sqlite');
      if (await oldDbFile.exists()) {
        // Open old DB, copy pending sync queue entries to new encrypted DB
        final oldDb = AppDatabase();
        final newDb = AppDatabase.encrypted(_encryptionKey!);
        try {
          final pending = await oldDb.syncQueueDao.getPending();
          for (final entry in pending) {
            await newDb.syncQueueDao.enqueue(
              entityId: entry.entityId,
              entityType: entry.entityType,
              action: entry.action,
              payload: entry.payload,
            );
          }
        } catch (_) {
          // Best-effort migration of pending mutations.
        } finally {
          await oldDb.close();
          await newDb.close();
        }
        await oldDbFile.delete();
      }
    } catch (_) {
      // Best-effort cleanup; failure is non-fatal.
    }
    await storage.write(key: 'amble_db_encrypted', value: 'true');
  }
}

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final key = _encryptionKey;
  final db =
      key != null ? AppDatabase.encrypted(key) : AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

final localDataServiceProvider = Provider<LocalDataService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return LocalDataService(db);
});
