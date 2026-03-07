import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';
import '../services/local_data_service.dart';

/// Holds the encryption key fetched during app initialization.
String? _encryptionKey;

/// Initializes database encryption: fetches (or creates) the key and
/// migrates from the old unencrypted database by deleting it (cache-only data
/// is re-synced from the backend).
Future<void> initDatabaseEncryption() async {
  _encryptionKey = await getOrCreateEncryptionKey();

  // Migrate: delete old unencrypted DB if it still exists.
  const storage = FlutterSecureStorage();
  final migrated = await storage.read(key: 'amble_db_encrypted');
  if (migrated != 'true') {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final oldDb = File('${dir.path}/amble_cache.sqlite');
      if (await oldDb.exists()) {
        await oldDb.delete();
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
