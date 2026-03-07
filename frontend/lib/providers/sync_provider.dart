import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/app_logger.dart';
import '../services/sync_service.dart';
import 'api_provider.dart';
import 'connectivity_provider.dart';
import 'local_data_provider.dart';
import 'task_store_provider.dart';

final syncServiceProvider = Provider<SyncService>((ref) {
  final api = ref.read(apiServiceProvider);
  final localDb = ref.read(localDataServiceProvider);
  final connectivity = ref.read(connectivityServiceProvider);
  final store = ref.read(taskStoreProvider.notifier);

  final service = SyncService(
    api: api,
    localDb: localDb,
    connectivity: connectivity,
    refreshStore: () => store.refreshFromLocalDb(),
    onMutationFailed: (entityId, action, error) {
      AppLogger.instance.warning('sync.mutation_failed', logger: 'SyncProvider', data: {
        'entityId': entityId, 'action': action, 'error': error,
      });
    },
  );

  ref.onDispose(() => service.dispose());
  return service;
});
