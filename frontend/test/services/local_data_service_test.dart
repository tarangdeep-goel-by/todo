import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/database/app_database.dart';
import 'package:frontend/models/task.dart';
import 'package:frontend/models/category.dart';
import 'package:frontend/services/local_data_service.dart';

Task _makeTask({
  String id = 'task-1',
  String userId = 'user-1',
  String title = 'Test task',
  String category = 'career',
  String status = 'active',
  Map<String, dynamic>? aiPlacementJson,
}) =>
    Task(
      id: id,
      userId: userId,
      title: title,
      category: category,
      status: status,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      transcription: '',
      aiPlacementJson: aiPlacementJson,
    );

Category _makeCat({
  String id = 'cat-1',
  String name = 'career',
  int position = 0,
}) =>
    Category(
      id: id,
      name: name,
      position: position,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  late AppDatabase db;
  late LocalDataService svc;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    svc = LocalDataService(db);
  });

  tearDown(() => db.close());

  group('LocalDataService - Tasks', () {
    test('upsert and getAll roundtrip', () async {
      await svc.upsertTask(_makeTask());
      final tasks = await svc.getAllTasks();
      expect(tasks, hasLength(1));
      expect(tasks.first.id, 'task-1');
      expect(tasks.first.title, 'Test task');
    });

    test('upsertTasks batch works', () async {
      await svc.upsertTasks([
        _makeTask(id: '1'),
        _makeTask(id: '2', title: 'Second'),
      ]);
      final tasks = await svc.getAllTasks();
      expect(tasks, hasLength(2));
    });

    test('aiPlacementJson roundtrips correctly', () async {
      await svc.upsertTask(_makeTask(
        aiPlacementJson: {'parent': 'career', 'confidence': 0.9},
      ));
      final tasks = await svc.getAllTasks();
      expect(tasks.first.aiPlacementJson, isNotNull);
      expect(tasks.first.aiPlacementJson!['parent'], 'career');
      expect(tasks.first.aiPlacementJson!['confidence'], 0.9);
    });

    test('deleteTask removes task', () async {
      await svc.upsertTask(_makeTask());
      await svc.deleteTask('task-1');
      expect(await svc.getAllTasks(), isEmpty);
    });

    test('clearAll empties everything', () async {
      await svc.upsertTask(_makeTask());
      await svc.replaceCategories([_makeCat()]);
      await svc.enqueueMutation(
          entityType: 'task', entityId: 'x', action: 'create', payload: {});
      await svc.setMeta('key', 'val');

      await svc.clearAll();

      expect(await svc.getAllTasks(), isEmpty);
      expect(await svc.getAllCategories(), isEmpty);
      expect(await svc.pendingMutationCount(), 0);
      expect(await svc.getMeta('key'), isNull);
    });
  });

  group('LocalDataService - Categories', () {
    test('replaceCategories roundtrip', () async {
      await svc.replaceCategories([
        _makeCat(id: '1', name: 'career'),
        _makeCat(id: '2', name: 'health', position: 1),
      ]);
      final cats = await svc.getAllCategories();
      expect(cats, hasLength(2));
      expect(cats.map((c) => c.name).toSet(), {'career', 'health'});
    });
  });

  group('LocalDataService - Sync Queue', () {
    test('enqueue and getPending', () async {
      await svc.enqueueMutation(
        entityType: 'task',
        entityId: 'a',
        action: 'create',
        payload: {'title': 'New'},
      );
      final pending = await svc.getPendingMutations();
      expect(pending, hasLength(1));
      expect(pending.first.entityId, 'a');
    });

    test('pendingMutationCount', () async {
      await svc.enqueueMutation(
          entityType: 'task', entityId: 'a', action: 'create', payload: {});
      await svc.enqueueMutation(
          entityType: 'task', entityId: 'b', action: 'update', payload: {});
      expect(await svc.pendingMutationCount(), 2);
    });
  });

  group('LocalDataService - Sync Meta', () {
    test('get/set meta roundtrip', () async {
      await svc.setMeta('last_pull_at', '2026-01-01T00:00:00Z');
      expect(await svc.getMeta('last_pull_at'), '2026-01-01T00:00:00Z');
    });
  });
}
