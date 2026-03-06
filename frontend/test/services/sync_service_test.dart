import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:frontend/database/app_database.dart';
import 'package:frontend/models/api_error.dart';
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
}

class FakeCreateTaskRequest extends Fake implements CreateTaskRequest {}
class FakeUpdateTaskRequest extends Fake implements UpdateTaskRequest {}

void main() {
  late AppDatabase db;
  late LocalDataService localDb;
  late MockApiService mockApi;
  late SyncService syncService;
  late int refreshCount;

  setUpAll(() {
    registerFallbackValue(FakeCreateTaskRequest());
    registerFallbackValue(FakeUpdateTaskRequest());
  });

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    localDb = LocalDataService(db);
    mockApi = MockApiService();
    refreshCount = 0;
    syncService = SyncService(
      api: mockApi,
      localDb: localDb,
      connectivity: FakeConnectivityService(),
      refreshStore: () async { refreshCount++; },
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
    DateTime? archivedAt,
  }) => Task(
    id: id, userId: 'u1', title: title, category: category,
    status: status, createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1), transcription: title,
    archivedAt: archivedAt,
  );

  group('push', () {
    test('creates task on server and acks mutation', () async {
      final task = makeTask();
      await localDb.upsertTask(task, pendingSync: true);
      await localDb.enqueueMutation(
        entityType: 'task', entityId: 'task-1',
        action: 'create',
        payload: {'title': 'Test', 'category': 'career', 'transcription': 'Test'},
      );

      final serverTask = makeTask(id: 'task-1', title: 'Test');
      when(() => mockApi.createTask(any())).thenAnswer((_) async => serverTask);

      await syncService.push();

      verify(() => mockApi.createTask(any())).called(1);
      final pending = await localDb.getPendingMutations();
      expect(pending, isEmpty);
    });

    test('updates task on server and acks mutation', () async {
      final task = makeTask();
      await localDb.upsertTask(task, pendingSync: true);
      await localDb.enqueueMutation(
        entityType: 'task', entityId: 'task-1',
        action: 'update',
        payload: {'status': 'completed', 'completed_at': '2026-01-01T00:00:00.000'},
      );

      final serverTask = makeTask(status: 'completed');
      when(() => mockApi.updateTask('task-1', any())).thenAnswer((_) async => serverTask);

      await syncService.push();

      verify(() => mockApi.updateTask('task-1', any())).called(1);
      final pending = await localDb.getPendingMutations();
      expect(pending, isEmpty);
    });

    test('completes task on server and acks mutation', () async {
      final task = makeTask();
      await localDb.upsertTask(task, pendingSync: true);
      await localDb.enqueueMutation(
        entityType: 'task', entityId: 'task-1',
        action: 'complete', payload: {},
      );

      final serverTask = makeTask(status: 'completed');
      when(() => mockApi.completeTask('task-1')).thenAnswer((_) async => serverTask);

      await syncService.push();

      verify(() => mockApi.completeTask('task-1')).called(1);
      final pending = await localDb.getPendingMutations();
      expect(pending, isEmpty);
    });

    test('deletes task on server and acks mutation', () async {
      final task = makeTask();
      await localDb.upsertTask(task, pendingSync: true);
      await localDb.enqueueMutation(
        entityType: 'task', entityId: 'task-1',
        action: 'delete', payload: {},
      );

      when(() => mockApi.deleteTask('task-1')).thenAnswer((_) async {});

      await syncService.push();

      verify(() => mockApi.deleteTask('task-1')).called(1);
      final pending = await localDb.getPendingMutations();
      expect(pending, isEmpty);
    });

    test('marks validation errors as permanently failed', () async {
      await localDb.upsertTask(makeTask(), pendingSync: true);
      await localDb.enqueueMutation(
        entityType: 'task', entityId: 'task-1',
        action: 'create',
        payload: {'title': 'Bad', 'category': 'career', 'transcription': 'Bad'},
      );

      when(() => mockApi.createTask(any())).thenThrow(
        const ApiError(message: 'Invalid', type: ApiErrorType.validation, statusCode: 422),
      );

      await syncService.push();

      final pending = await localDb.getPendingMutations();
      expect(pending, isEmpty); // Failed entries are excluded from getPending
    });

    test('404 on update removes task from local DB', () async {
      await localDb.upsertTask(makeTask(), pendingSync: true);
      await localDb.enqueueMutation(
        entityType: 'task', entityId: 'task-1',
        action: 'update',
        payload: {'title': 'Updated'},
      );

      when(() => mockApi.updateTask('task-1', any())).thenThrow(
        const ApiError(message: 'Not found', type: ApiErrorType.server, statusCode: 404),
      );

      await syncService.push();

      final localTask = await localDb.getTaskById('task-1');
      expect(localTask, isNull);
    });

    test('transient error stops queue and increments retry', () async {
      await localDb.upsertTask(makeTask(), pendingSync: true);
      await localDb.upsertTask(makeTask(id: 'task-2', title: 'Second'), pendingSync: true);
      await localDb.enqueueMutation(
        entityType: 'task', entityId: 'task-1',
        action: 'create',
        payload: {'title': 'Test', 'category': 'career', 'transcription': 'Test'},
      );
      await localDb.enqueueMutation(
        entityType: 'task', entityId: 'task-2',
        action: 'create',
        payload: {'title': 'Second', 'category': 'career', 'transcription': 'Second'},
      );

      when(() => mockApi.createTask(any())).thenThrow(
        const ApiError(message: 'Timeout', type: ApiErrorType.timeout),
      );

      await syncService.push();

      // Both should still be pending (first failed transiently, second never tried)
      final pending = await localDb.getPendingMutations();
      expect(pending, hasLength(2));
    });
  });

  group('pull', () {
    test('full sync fetches all tasks from server', () async {
      final serverTasks = [makeTask(id: 't1'), makeTask(id: 't2', title: 'Two')];
      when(() => mockApi.getTasksAdvancedWithRetry(
        limit: any(named: 'limit'), offset: any(named: 'offset'),
        updatedAtGte: any(named: 'updatedAtGte'),
      )).thenAnswer((_) async => TaskListResponse(
        tasks: serverTasks, totalCount: 2, limit: 100, offset: 0, hasMore: false,
      ));
      when(() => mockApi.getCategories()).thenAnswer((_) async => []);

      await syncService.pull();

      final local = await localDb.getAllTasks();
      expect(local, hasLength(2));
    });

    test('delta sync skips pending-sync tasks', () async {
      // Set last_pull_at to enable delta sync
      await localDb.setMeta('last_pull_at', DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String());
      await localDb.setMeta('last_full_sync_at', DateTime.now().toIso8601String());

      // Local task with pending changes
      await localDb.upsertTask(makeTask(id: 't1', title: 'Local edit'), pendingSync: true);

      // Server returns different data for same task
      final serverTask = makeTask(id: 't1', title: 'Server version');
      when(() => mockApi.getTasksAdvancedWithRetry(
        limit: any(named: 'limit'), offset: any(named: 'offset'),
        updatedAtGte: any(named: 'updatedAtGte'),
      )).thenAnswer((_) async => TaskListResponse(
        tasks: [serverTask], totalCount: 1, limit: 100, offset: 0, hasMore: false,
      ));
      when(() => mockApi.getCategories()).thenAnswer((_) async => []);

      await syncService.pull();

      // Local task should retain its local edit (not overwritten)
      final local = await localDb.getTaskById('t1');
      expect(local!.title, 'Local edit');
    });

    test('delta sync removes archived tasks from local DB', () async {
      await localDb.setMeta('last_pull_at', DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String());
      await localDb.setMeta('last_full_sync_at', DateTime.now().toIso8601String());

      await localDb.upsertTask(makeTask(id: 't1'), pendingSync: false);

      final archivedTask = makeTask(id: 't1', archivedAt: DateTime.now());
      when(() => mockApi.getTasksAdvancedWithRetry(
        limit: any(named: 'limit'), offset: any(named: 'offset'),
        updatedAtGte: any(named: 'updatedAtGte'),
      )).thenAnswer((_) async => TaskListResponse(
        tasks: [archivedTask], totalCount: 1, limit: 100, offset: 0, hasMore: false,
      ));
      when(() => mockApi.getCategories()).thenAnswer((_) async => []);

      await syncService.pull();

      final local = await localDb.getTaskById('t1');
      expect(local, isNull);
    });
  });

  group('sync', () {
    test('calls push then pull then refreshStore', () async {
      // No pending mutations, set up for full sync
      when(() => mockApi.getTasksAdvancedWithRetry(
        limit: any(named: 'limit'), offset: any(named: 'offset'),
        updatedAtGte: any(named: 'updatedAtGte'),
      )).thenAnswer((_) async => TaskListResponse(
        tasks: [], totalCount: 0, limit: 100, offset: 0, hasMore: false,
      ));
      when(() => mockApi.getCategories()).thenAnswer((_) async => []);

      await syncService.sync();

      expect(refreshCount, 1);
    });

    test('concurrent sync calls are prevented', () async {
      when(() => mockApi.getTasksAdvancedWithRetry(
        limit: any(named: 'limit'), offset: any(named: 'offset'),
        updatedAtGte: any(named: 'updatedAtGte'),
      )).thenAnswer((_) async {
        await Future.delayed(const Duration(milliseconds: 50));
        return TaskListResponse(
          tasks: [], totalCount: 0, limit: 100, offset: 0, hasMore: false,
        );
      });
      when(() => mockApi.getCategories()).thenAnswer((_) async => []);

      // Fire two syncs concurrently
      final f1 = syncService.sync();
      final f2 = syncService.sync(); // Should return immediately (mutex)
      await Future.wait([f1, f2]);

      // Only one actual fetch should have happened
      expect(refreshCount, 1);
    });
  });
}
