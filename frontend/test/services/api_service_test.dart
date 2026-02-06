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
    'category': 'work',
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

  Response<dynamic> _ok(dynamic data, {int statusCode = 200}) {
    return Response(
      data: data,
      statusCode: statusCode,
      requestOptions: RequestOptions(path: ''),
    );
  }

  group('getTasks', () {
    test('returns task list', () async {
      when(() => mockDio.get('/tasks', queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async => _ok({
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
          .thenAnswer((_) async => _ok({
                'tasks': [taskJson],
                'total_count': 1,
                'limit': 50,
                'offset': 0,
                'has_more': false,
              }));
      final resp = await apiService.getTasksByCategory('u1', 'work');
      expect(resp.tasks.length, 1);
    });
  });

  group('processVoiceCommand', () {
    test('returns agent response', () async {
      when(() => mockDio.post('/agent/process', data: any(named: 'data')))
          .thenAnswer((_) async => _ok({
                'success': true,
                'message': 'Created',
                'type': 'confirmation',
                'data': null,
              }));
      final resp = await apiService.processVoiceCommand('add task', 'u1');
      expect(resp.success, true);
    });
  });

  group('resolveQuestion', () {
    test('success', () async {
      when(() => mockDio.post('/agent/resolve', data: any(named: 'data')))
          .thenAnswer((_) async => _ok({
                'success': true,
                'message': 'Done',
                'type': 'confirmation',
                'data': null,
              }));
      final resp = await apiService.resolveQuestion(
        userId: 'u1',
        action: 'complete',
        selectedTaskId: 't1',
      );
      expect(resp.success, true);
    });

    test('with data map', () async {
      when(() => mockDio.post('/agent/resolve', data: any(named: 'data')))
          .thenAnswer((_) async => _ok({
                'success': true,
                'message': 'Moved',
                'type': 'confirmation',
                'data': null,
              }));
      final resp = await apiService.resolveQuestion(
        userId: 'u1',
        action: 'move',
        selectedTaskId: 't1',
        data: {'targetParentQuery': 'Project'},
      );
      expect(resp.message, 'Moved');
    });

    test('returns question type for chained', () async {
      when(() => mockDio.post('/agent/resolve', data: any(named: 'data')))
          .thenAnswer((_) async => _ok({
                'success': false,
                'message': 'Which one?',
                'type': 'question',
                'data': {
                  'matches': [
                    {'id': '1', 'title': 'A'}
                  ],
                  'action': 'select_parent'
                },
              }));
      final resp = await apiService.resolveQuestion(
        userId: 'u1',
        action: 'move',
        selectedTaskId: 't1',
        data: {'targetParentQuery': 'Meeting'},
      );
      expect(resp.type, 'question');
    });
  });

  group('createTask', () {
    test('returns created task', () async {
      when(() => mockDio.post('/tasks', data: any(named: 'data')))
          .thenAnswer((_) async => _ok(taskJson));
      final req = CreateTaskRequest(
        userId: 'u1',
        title: 'Task',
        category: 'work',
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
              _ok(Map<String, dynamic>.from(taskJson)..['title'] = 'Updated'));
      final req = UpdateTaskRequest(title: 'Updated');
      final task = await apiService.updateTask('t1', req);
      expect(task.title, 'Updated');
    });
  });

  group('deleteTask', () {
    test('completes without error', () async {
      when(() => mockDio.delete('/tasks/t1',
              queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async => _ok({'success': true}));
      await expectLater(
        apiService.deleteTask('t1', userId: 'u1'),
        completes,
      );
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
