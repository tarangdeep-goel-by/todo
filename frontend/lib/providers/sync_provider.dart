import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/sync_service.dart';
import 'api_provider.dart';
import 'local_data_provider.dart';
import 'task_store_provider.dart';

final syncServiceProvider = Provider<SyncService>((ref) {
  final api = ref.read(apiServiceProvider);
  final localDb = ref.read(localDataServiceProvider);
  final store = ref.read(taskStoreProvider.notifier);

  final service = SyncService(
    api: api,
    localDb: localDb,
    refreshStore: () => store.refreshFromLocalDb(),
  );

  ref.onDispose(() => service.dispose());
  return service;
});
