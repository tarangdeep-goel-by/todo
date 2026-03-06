import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:frontend/database/app_database.dart';
import 'package:frontend/models/api_response.dart';
import 'package:frontend/providers/api_provider.dart';
import 'package:frontend/providers/local_data_provider.dart';
import 'package:frontend/providers/task_store_provider.dart';
import 'package:frontend/services/local_data_service.dart';
import 'package:frontend/services/task_mutation_service.dart';
import '../helpers/test_helpers.dart';

void main() {
  late AppDatabase db;
  late LocalDataService localDb;
  late ProviderContainer container;
  late TaskMutationService mutationService;
  late MockApiService mockApi;
  bool pushCalled = false;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    localDb = LocalDataService(db);
    mockApi = MockApiService();
    pushCalled = false;

    when(() => mockApi.getTasksAdvancedWithRetry(
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        )).thenAnswer((_) async => TaskListResponse(tasks: [], totalCount: 0, limit: 100, offset: 0, hasMore: false));

    container = ProviderContainer(overrides: [
      apiServiceProvider.overrideWithValue(mockApi),
      localDataServiceProvider.overrideWithValue(localDb),
    ]);

    mutationService = TaskMutationService(
      store: container.read(taskStoreProvider.notifier),
      localDb: localDb,
      onPush: () => pushCalled = true,
    );
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  group('TaskMutationService', () {
    test('createTask adds to store, local DB, and sync queue', () async {
      final task = createTestTask(id: 'new-1', title: 'New task');
      await mutationService.createTask(task, {'title': 'New task', 'category': 'career'});

      // Store has task
      final storeTask = container.read(taskByIdProvider('new-1'));
      expect(storeTask, isNotNull);
      expect(storeTask!.title, 'New task');

      // Local DB has task with pendingSync
      final dbTasks = await localDb.getAllTasks();
      expect(dbTasks, hasLength(1));

      // Sync queue has entry
      final pending = await localDb.getPendingMutations();
      expect(pending, hasLength(1));
      expect(pending.first.action, 'create');
      expect(pending.first.entityId, 'new-1');

      // Push triggered
      expect(pushCalled, isTrue);
    });

    test('updateTask updates store, local DB, and enqueues', () async {
      final original = createTestTask(id: 'u-1', title: 'Original');
      await localDb.upsertTask(original);
      container.read(taskStoreProvider.notifier).upsertTask(original);

      final updated = original.copyWith(title: 'Updated');
      await mutationService.updateTask(updated, {'title': 'Updated'});

      // Store updated
      expect(container.read(taskByIdProvider('u-1'))!.title, 'Updated');

      // Queue entry
      final pending = await localDb.getPendingMutations();
      expect(pending, hasLength(1));
      expect(pending.first.action, 'update');
    });

    test('completeTask marks store and enqueues', () async {
      final task = createTestTask(id: 'c-1', status: 'active');
      container.read(taskStoreProvider.notifier).upsertTask(task);

      await mutationService.completeTask(task);

      // Store shows completed
      expect(container.read(taskByIdProvider('c-1'))!.status, 'completed');

      // Queue entry
      final pending = await localDb.getPendingMutations();
      expect(pending, hasLength(1));
      expect(pending.first.action, 'complete');
    });

    test('deleteTask removes from store and enqueues', () async {
      final task = createTestTask(id: 'd-1');
      container.read(taskStoreProvider.notifier).upsertTask(task);
      await localDb.upsertTask(task);

      await mutationService.deleteTask(task);

      // Store doesn't have it
      expect(container.read(taskByIdProvider('d-1')), isNull);

      // Local DB doesn't have it
      expect(await localDb.getAllTasks(), isEmpty);

      // Queue has delete
      final pending = await localDb.getPendingMutations();
      expect(pending, hasLength(1));
      expect(pending.first.action, 'delete');
    });

    test('multiple mutations enqueue in FIFO order', () async {
      final t1 = createTestTask(id: 'fifo-1', title: 'First');
      final t2 = createTestTask(id: 'fifo-2', title: 'Second');
      await mutationService.createTask(t1, {'title': 'First'});
      await mutationService.createTask(t2, {'title': 'Second'});

      final pending = await localDb.getPendingMutations();
      expect(pending, hasLength(2));
      expect(pending[0].entityId, 'fifo-1');
      expect(pending[1].entityId, 'fifo-2');
    });
  });
}
