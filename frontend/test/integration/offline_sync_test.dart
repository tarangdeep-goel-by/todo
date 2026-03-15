import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:frontend/database/app_database.dart';
import 'package:frontend/models/api_response.dart';
import 'package:frontend/models/task.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/local_data_service.dart';
import 'package:frontend/services/connectivity_service.dart';
import 'package:frontend/services/sync_service.dart';

class MockApiService extends Mock implements ApiService {}

class FakeConnectivityService extends Fake implements ConnectivityService {
  @override
  bool get isOnline => true;
  @override
  void reportSuccess() {}
  @override
  void reportFailure() {}
}

class FakeCreateTaskRequest extends Fake implements CreateTaskRequest {}

class FakeUpdateTaskRequest extends Fake implements UpdateTaskRequest {}

void main() {
  late AppDatabase db;
  late LocalDataService localDb;
  late MockApiService mockApi;
  late SyncService syncService;
  late Map<String, Task> storeSnapshot;

  setUpAll(() {
    registerFallbackValue(FakeCreateTaskRequest());
    registerFallbackValue(FakeUpdateTaskRequest());
  });

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    localDb = LocalDataService(db);
    mockApi = MockApiService();
    storeSnapshot = {};

    syncService = SyncService(
      api: mockApi,
      localDb: localDb,
      connectivity: FakeConnectivityService(),
      refreshStore: () async {
        final tasks = await localDb.getAllTasks();
        storeSnapshot = {for (final t in tasks) t.id: t};
      },
    );
  });

  tearDown(() {
    syncService.dispose();
    db.close();
  });

  Task makeTask({
    String id = 'task-1',
    String title = 'Test',
    String category = 'career',
    String status = 'active',
  }) =>
      Task(
        id: id,
        userId: 'u1',
        title: title,
        category: category,
        status: status,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        transcription: title,
      );

  group('offline → online sync', () {
    test('create 3 tasks offline, all sync when push runs', () async {
      for (var i = 1; i <= 3; i++) {
        await localDb.upsertTask(makeTask(id: 'task-$i', title: 'Task $i'), pendingSync: true);
        await localDb.enqueueMutation(
          entityType: 'task',
          entityId: 'task-$i',
          action: 'create',
          payload: {'title': 'Task $i', 'category': 'career', 'transcription': 'Task $i'},
        );
      }

      when(() => mockApi.createTask(any()))
          .thenAnswer((_) async => makeTask(id: 'task-1', title: 'Task 1'));

      expect(await localDb.pendingMutationCount(), 3);
      await syncService.push();
      expect(await localDb.pendingMutationCount(), 0);
      verify(() => mockApi.createTask(any())).called(3);
    });

    test('edit + complete + delete offline all sync correctly', () async {
      for (var i = 1; i <= 3; i++) {
        await localDb.upsertTask(makeTask(id: 'task-$i', title: 'Task $i'));
      }

      await localDb.upsertTask(makeTask(id: 'task-1', title: 'Edited'), pendingSync: true);
      await localDb.enqueueMutation(
        entityType: 'task', entityId: 'task-1',
        action: 'update', payload: {'title': 'Edited'},
      );

      await localDb.upsertTask(makeTask(id: 'task-2', status: 'completed'), pendingSync: true);
      await localDb.enqueueMutation(
        entityType: 'task', entityId: 'task-2',
        action: 'complete', payload: {},
      );

      await localDb.enqueueMutation(
        entityType: 'task', entityId: 'task-3',
        action: 'delete', payload: {},
      );

      when(() => mockApi.updateTask('task-1', any()))
          .thenAnswer((_) async => makeTask(id: 'task-1', title: 'Edited'));
      when(() => mockApi.completeTask('task-2'))
          .thenAnswer((_) async => makeTask(id: 'task-2', status: 'completed'));
      when(() => mockApi.deleteTask('task-3')).thenAnswer((_) async {});

      await syncService.push();

      expect(await localDb.pendingMutationCount(), 0);
      verify(() => mockApi.updateTask('task-1', any())).called(1);
      verify(() => mockApi.completeTask('task-2')).called(1);
      verify(() => mockApi.deleteTask('task-3')).called(1);
    });

    test('create then delete offline → compacted to no-op', () async {
      await localDb.upsertTask(makeTask(id: 'task-x'), pendingSync: true);
      await localDb.enqueueMutation(
        entityType: 'task', entityId: 'task-x',
        action: 'create',
        payload: {'title': 'Temp', 'category': 'career', 'transcription': 'Temp'},
      );
      await localDb.enqueueMutation(
        entityType: 'task', entityId: 'task-x',
        action: 'delete', payload: {},
      );

      expect(await localDb.pendingMutationCount(), 2);

      await syncService.push();

      verifyNever(() => mockApi.createTask(any()));
      verifyNever(() => mockApi.deleteTask(any()));
      expect(await localDb.getTaskById('task-x'), isNull);
    });

    test('server creates tasks while offline → appear after full sync', () async {
      final serverTasks = [
        makeTask(id: 'server-1', title: 'From server'),
        makeTask(id: 'server-2', title: 'Also from server'),
      ];

      when(() => mockApi.getTasksAdvancedWithRetry(
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
            updatedAtGte: any(named: 'updatedAtGte'),
          )).thenAnswer((_) async => TaskListResponse(
            tasks: serverTasks, totalCount: 2, limit: 100, offset: 0, hasMore: false,
          ));
      when(() => mockApi.getCategories()).thenAnswer((_) async => []);
      when(() => mockApi.getArchivedTasks(limit: any(named: 'limit'), offset: any(named: 'offset')))
          .thenAnswer((_) async => []);

      await syncService.sync();

      expect(storeSnapshot.keys, containsAll(['server-1', 'server-2']));
    });

    test('full sync preserves local pending tasks', () async {
      await localDb.upsertTask(
        makeTask(id: 'local-1', title: 'My edit'),
        pendingSync: true,
      );

      when(() => mockApi.getTasksAdvancedWithRetry(
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
            updatedAtGte: any(named: 'updatedAtGte'),
          )).thenAnswer((_) async => TaskListResponse(
            tasks: [makeTask(id: 'local-1', title: 'Server version')],
            totalCount: 1, limit: 100, offset: 0, hasMore: false,
          ));
      when(() => mockApi.getCategories()).thenAnswer((_) async => []);
      when(() => mockApi.getArchivedTasks(limit: any(named: 'limit'), offset: any(named: 'offset')))
          .thenAnswer((_) async => []);

      await syncService.pull();

      final local = await localDb.getTaskById('local-1');
      expect(local!.title, 'My edit');
    });

    test('sign out clears all local data', () async {
      await localDb.upsertTask(makeTask(id: 't1'));
      await localDb.enqueueMutation(
        entityType: 'task', entityId: 't1',
        action: 'update', payload: {'title': 'x'},
      );
      await localDb.setMeta('last_pull_at', 'now');

      await localDb.clearAll();

      expect(await localDb.getAllTasks(), isEmpty);
      expect(await localDb.pendingMutationCount(), 0);
      expect(await localDb.getMeta('last_pull_at'), isNull);
    });

    test('500 cached tasks load under 500ms', () async {
      final tasks = List.generate(500, (i) => makeTask(id: 'task-$i', title: 'Task $i'));
      await localDb.upsertTasks(tasks);

      final sw = Stopwatch()..start();
      final loaded = await localDb.getAllTasks();
      sw.stop();

      expect(loaded, hasLength(500));
      expect(sw.elapsedMilliseconds, lessThan(500));
    });

    test('multiple updates to same task compacted into one', () async {
      await localDb.upsertTask(makeTask(id: 'task-1'), pendingSync: true);

      // Three separate updates
      await localDb.enqueueMutation(
        entityType: 'task', entityId: 'task-1',
        action: 'update', payload: {'title': 'v1'},
      );
      await localDb.enqueueMutation(
        entityType: 'task', entityId: 'task-1',
        action: 'update', payload: {'title': 'v2', 'priority': 'high'},
      );
      await localDb.enqueueMutation(
        entityType: 'task', entityId: 'task-1',
        action: 'update', payload: {'title': 'v3'},
      );

      expect(await localDb.pendingMutationCount(), 3);

      // Compact should merge into 1
      await syncService.compact();

      final pending = await localDb.getPendingMutations();
      expect(pending, hasLength(1));
      expect(pending.first.action, 'update');
    });
  });
}
