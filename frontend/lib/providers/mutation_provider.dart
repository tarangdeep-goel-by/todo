import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/environment.dart';
import '../services/task_mutation_service.dart';
import 'api_provider.dart';
import 'local_data_provider.dart';
import 'sync_provider.dart';
import 'task_store_provider.dart';

final taskMutationServiceProvider = Provider<TaskMutationService>((ref) {
  final store = ref.read(taskStoreProvider.notifier);
  if (Environment.isTestMode) {
    // Test mode: skip offline DB, use direct API calls
    final api = ref.read(apiServiceProvider);
    return TestMutationService(
      store: store,
      api: api,
      onCategoriesChanged: () async {
        final cats = await api.getCategories();
        ref.read(categoriesProvider.notifier).state = cats;
      },
    );
  }
  final localDb = ref.read(localDataServiceProvider);
  final syncService = ref.read(syncServiceProvider);
  return TaskMutationService(
    store: store,
    localDb: localDb,
    onPush: () => syncService.triggerPush(),
  );
});
