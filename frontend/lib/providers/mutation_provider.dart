import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/task_mutation_service.dart';
import 'local_data_provider.dart';
import 'task_store_provider.dart';

final taskMutationServiceProvider = Provider<TaskMutationService>((ref) {
  final store = ref.read(taskStoreProvider.notifier);
  final localDb = ref.read(localDataServiceProvider);
  return TaskMutationService(
    store: store,
    localDb: localDb,
  );
});
