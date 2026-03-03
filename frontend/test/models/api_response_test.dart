import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/api_response.dart';

void main() {
  group('CreateTaskRequest.toJson', () {
    test('serializes required and optional fields', () {
      final req = CreateTaskRequest(
        userId: 'u1',
        title: 'Task',
        category: 'career',
        transcription: 'task',
        description: 'desc',
        dueDate: DateTime(2025, 6, 15),
      );
      final json = req.toJson();
      expect(json['user_id'], 'u1');
      expect(json['title'], 'Task');
      expect(json['category'], 'career');
      expect(json['description'], 'desc');
      expect(json['due_date'], isNotNull);
    });
  });

  group('TaskListResponse.fromJson', () {
    test('parses empty list', () {
      final r = TaskListResponse.fromJson({
        'tasks': [],
        'total_count': 0,
        'limit': 50,
        'offset': 0,
        'has_more': false,
      });
      expect(r.tasks, isEmpty);
      expect(r.totalCount, 0);
      expect(r.hasMore, false);
    });

    test('parses populated list', () {
      final r = TaskListResponse.fromJson({
        'tasks': [
          {
            'id': 't1',
            'user_id': 'u1',
            'title': 'Task 1',
            'description': null,
            'parent_id': null,
            'category': 'career',
            'status': 'active',
            'created_at': '2025-01-15T00:00:00.000',
            'updated_at': '2025-01-15T00:00:00.000',
            'due_date': null,
            'completed_at': null,
            'audio_file_uri': null,
            'transcription': 'task 1',
            'ai_placement_json': null,
            'priority': null,
          }
        ],
        'total_count': 1,
        'limit': 50,
        'offset': 0,
        'has_more': false,
      });
      expect(r.tasks.length, 1);
      expect(r.tasks.first.title, 'Task 1');
      expect(r.totalCount, 1);
    });
  });

  group('UpdateTaskRequest.toJson', () {
    test('partial — only set fields included', () {
      final req = UpdateTaskRequest(title: 'New');
      final json = req.toJson();
      expect(json['title'], 'New');
      expect(json.containsKey('description'), false);
      expect(json.containsKey('status'), false);
    });

    test('all fields', () {
      final req = UpdateTaskRequest(
        title: 'T',
        description: 'D',
        status: 'completed',
        category: 'home',
        priority: 'high',
        dueDate: DateTime(2025, 6, 15),
        completedAt: DateTime(2025, 6, 15),
      );
      final json = req.toJson();
      expect(json.length, 7);
    });

    test('empty request produces empty map', () {
      final req = UpdateTaskRequest();
      expect(req.toJson(), isEmpty);
    });
  });
}
