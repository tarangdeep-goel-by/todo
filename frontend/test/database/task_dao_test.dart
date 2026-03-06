import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  LocalTasksCompanion _makeTask({
    String id = 'task-1',
    String userId = 'user-1',
    String title = 'Test task',
    String category = 'career',
    String status = 'active',
    bool pendingSync = false,
  }) =>
      LocalTasksCompanion.insert(
        id: id,
        userId: userId,
        title: title,
        category: category,
        status: Value(status),
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        transcription: const Value(''),
        pendingSync: Value(pendingSync),
      );

  group('TaskDao', () {
    test('insert and retrieve task', () async {
      await db.taskDao.upsertTask(_makeTask());
      final tasks = await db.taskDao.getAllTasks();
      expect(tasks, hasLength(1));
      expect(tasks.first.id, 'task-1');
      expect(tasks.first.title, 'Test task');
      expect(tasks.first.category, 'career');
    });

    test('upsert updates existing task', () async {
      await db.taskDao.upsertTask(_makeTask());
      await db.taskDao.upsertTask(_makeTask(title: 'Updated title'));
      final tasks = await db.taskDao.getAllTasks();
      expect(tasks, hasLength(1));
      expect(tasks.first.title, 'Updated title');
    });

    test('getTaskById returns correct task', () async {
      await db.taskDao.upsertTask(_makeTask(id: 'a'));
      await db.taskDao.upsertTask(_makeTask(id: 'b', title: 'Second'));
      final task = await db.taskDao.getTaskById('b');
      expect(task, isNotNull);
      expect(task!.title, 'Second');
    });

    test('getTaskById returns null for missing', () async {
      final task = await db.taskDao.getTaskById('nonexistent');
      expect(task, isNull);
    });

    test('deleteTask removes task', () async {
      await db.taskDao.upsertTask(_makeTask());
      await db.taskDao.deleteTask('task-1');
      final tasks = await db.taskDao.getAllTasks();
      expect(tasks, isEmpty);
    });

    test('deleteNonPendingTasks preserves pending', () async {
      await db.taskDao.upsertTask(_makeTask(id: 'synced'));
      await db.taskDao.upsertTask(
          _makeTask(id: 'pending', pendingSync: true));
      await db.taskDao.deleteNonPendingTasks();
      final tasks = await db.taskDao.getAllTasks();
      expect(tasks, hasLength(1));
      expect(tasks.first.id, 'pending');
    });

    test('markPendingSync updates flag', () async {
      await db.taskDao.upsertTask(_makeTask());
      await db.taskDao.markPendingSync('task-1', true);
      final task = await db.taskDao.getTaskById('task-1');
      expect(task!.pendingSync, isTrue);
    });

    test('upsertTasks batch inserts', () async {
      await db.taskDao.upsertTasks([
        _makeTask(id: '1', title: 'First'),
        _makeTask(id: '2', title: 'Second'),
        _makeTask(id: '3', title: 'Third'),
      ]);
      final tasks = await db.taskDao.getAllTasks();
      expect(tasks, hasLength(3));
    });

    test('all nullable fields roundtrip correctly', () async {
      await db.taskDao.upsertTask(LocalTasksCompanion.insert(
        id: 'full',
        userId: 'user-1',
        title: 'Full task',
        description: const Value('desc'),
        parentId: const Value('parent-1'),
        category: 'health',
        categoryId: const Value('cat-1'),
        status: const Value('completed'),
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 2),
        dueDate: Value(DateTime(2026, 2, 1)),
        completedAt: Value(DateTime(2026, 1, 15)),
        archivedAt: Value(DateTime(2026, 1, 20)),
        transcription: const Value('some text'),
        aiPlacementJson: const Value('{"key":"val"}'),
        priority: const Value('high'),
        estimatedHours: const Value(2.5),
        audioFileUri: const Value('file://audio.m4a'),
        pendingSync: const Value(true),
      ));
      final task = await db.taskDao.getTaskById('full');
      expect(task!.description, 'desc');
      expect(task.parentId, 'parent-1');
      expect(task.categoryId, 'cat-1');
      expect(task.status, 'completed');
      expect(task.dueDate, DateTime(2026, 2, 1));
      expect(task.completedAt, DateTime(2026, 1, 15));
      expect(task.archivedAt, DateTime(2026, 1, 20));
      expect(task.transcription, 'some text');
      expect(task.aiPlacementJson, '{"key":"val"}');
      expect(task.priority, 'high');
      expect(task.estimatedHours, 2.5);
      expect(task.audioFileUri, 'file://audio.m4a');
      expect(task.pendingSync, isTrue);
    });

    test('deleteAllTasks removes everything', () async {
      await db.taskDao.upsertTasks([
        _makeTask(id: '1'),
        _makeTask(id: '2', pendingSync: true),
      ]);
      await db.taskDao.deleteAllTasks();
      final tasks = await db.taskDao.getAllTasks();
      expect(tasks, isEmpty);
    });
  });
}
