import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:dio/dio.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/models/api_response.dart';
import '../helpers/test_helpers.dart';

void main() {
  late MockDio mockDio;
  late ApiService apiService;

  final taskJson = {
    'id': 't1',
    'user_id': 'u1',
    'title': 'Task',
    'description': null,
    'parent_id': null,
    'category': 'career',
    'status': 'active',
    'created_at': '2025-01-15T00:00:00.000',
    'updated_at': '2025-01-15T00:00:00.000',
    'due_date': null,
    'completed_at': null,
    'audio_file_uri': null,
    'transcription': 'task',
    'ai_placement_json': null,
    'priority': null,
  };

  setUp(() {
    mockDio = MockDio();
    apiService = ApiService(dio: mockDio);
  });

  final categoryJson = {
    'id': 'cat-1',
    'name': 'career',
    'position': 0,
    'created_at': '2025-01-15T00:00:00.000',
  };

  Response<dynamic> ok(dynamic data, {int statusCode = 200}) {
    return Response(
      data: data,
      statusCode: statusCode,
      requestOptions: RequestOptions(path: ''),
    );
  }

  group('getTasks', () {
    test('returns task list', () async {
      when(() => mockDio.get('/tasks', queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async => ok({
                'tasks': [taskJson],
                'total_count': 1,
                'limit': 50,
                'offset': 0,
                'has_more': false,
              }));
      final tasks = await apiService.getTasks('u1');
      expect(tasks.length, 1);
      expect(tasks.first.title, 'Task');
    });
  });

  group('getTasksByCategory', () {
    test('returns filtered response', () async {
      when(() => mockDio.get('/tasks', queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async => ok({
                'tasks': [taskJson],
                'total_count': 1,
                'limit': 50,
                'offset': 0,
                'has_more': false,
              }));
      final resp = await apiService.getTasksByCategory('u1', 'career');
      expect(resp.tasks.length, 1);
    });
  });

  group('createTask', () {
    test('returns created task', () async {
      when(() => mockDio.post('/tasks', data: any(named: 'data')))
          .thenAnswer((_) async => ok(taskJson));
      final req = CreateTaskRequest(
        userId: 'u1',
        title: 'Task',
        category: 'career',
        transcription: 'task',
      );
      final task = await apiService.createTask(req);
      expect(task.id, 't1');
    });
  });

  group('updateTask', () {
    test('returns updated task', () async {
      when(() => mockDio.patch('/tasks/t1', data: any(named: 'data')))
          .thenAnswer((_) async =>
              ok(Map<String, dynamic>.from(taskJson)..['title'] = 'Updated'));
      final req = UpdateTaskRequest(title: 'Updated');
      final task = await apiService.updateTask('t1', req);
      expect(task.title, 'Updated');
    });
  });

  group('deleteTask', () {
    test('completes without error', () async {
      when(() => mockDio.delete('/tasks/t1',
              queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async => ok({'success': true}));
      await expectLater(
        apiService.deleteTask('t1', userId: 'u1'),
        completes,
      );
    });
  });

  group('getCategories', () {
    test('returns category list', () async {
      when(() => mockDio.get('/categories', queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async => ok([categoryJson]));
      final cats = await apiService.getCategories('u1');
      expect(cats.length, 1);
      expect(cats.first.name, 'career');
    });

    test('throws on error', () async {
      when(() => mockDio.get('/categories', queryParameters: any(named: 'queryParameters')))
          .thenThrow(DioException(
        response: Response(
          data: {'detail': 'Server error'},
          statusCode: 500,
          requestOptions: RequestOptions(path: ''),
        ),
        requestOptions: RequestOptions(path: ''),
      ));
      expect(() => apiService.getCategories('u1'), throwsA(equals('Server error')));
    });
  });

  group('createCategory', () {
    test('returns created category', () async {
      when(() => mockDio.post('/categories', data: any(named: 'data')))
          .thenAnswer((_) async => ok(categoryJson));
      final cat = await apiService.createCategory('u1', 'career');
      expect(cat.name, 'career');
    });
  });

  group('deleteCategory', () {
    test('completes without error', () async {
      when(() => mockDio.delete('/categories/cat-1',
              queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async => ok({'success': true}));
      await expectLater(
        apiService.deleteCategory('cat-1', userId: 'u1'),
        completes,
      );
    });
  });

  group('getTasksAdvanced', () {
    test('passes filter params', () async {
      when(() => mockDio.get('/tasks', queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async => ok({
                'tasks': [taskJson],
                'total_count': 1,
                'limit': 50,
                'offset': 0,
                'has_more': false,
              }));
      final resp = await apiService.getTasksAdvanced(
        userId: 'u1',
        category: 'career',
        priority: 'high',
        status: 'active',
        sort: 'priority:desc',
        limit: 10,
        offset: 5,
      );
      expect(resp.tasks.length, 1);

      // Verify query params were passed
      final captured = verify(
        () => mockDio.get('/tasks', queryParameters: captureAny(named: 'queryParameters')),
      ).captured.single as Map<String, dynamic>;
      expect(captured['category'], 'career');
      expect(captured['priority'], 'high');
      expect(captured['limit'], 10);
      expect(captured['offset'], 5);
    });
  });

  group('Error handling', () {
    test('detail string', () async {
      when(() => mockDio.get('/tasks', queryParameters: any(named: 'queryParameters')))
          .thenThrow(DioException(
        response: Response(
          data: {'detail': 'Not found'},
          statusCode: 404,
          requestOptions: RequestOptions(path: ''),
        ),
        requestOptions: RequestOptions(path: ''),
      ));
      expect(
        () => apiService.getTasks('u1'),
        throwsA(equals('Not found')),
      );
    });

    test('connection timeout', () async {
      when(() => mockDio.get('/tasks', queryParameters: any(named: 'queryParameters')))
          .thenThrow(DioException(
        type: DioExceptionType.connectionTimeout,
        requestOptions: RequestOptions(path: ''),
      ));
      expect(
        () => apiService.getTasks('u1'),
        throwsA(equals('Connection timeout')),
      );
    });
  });
}
