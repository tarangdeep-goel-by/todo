import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/app_database.dart';
import '../services/local_data_service.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

final localDataServiceProvider = Provider<LocalDataService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return LocalDataService(db);
});
