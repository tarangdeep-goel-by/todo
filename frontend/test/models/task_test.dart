import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/task.dart';

void main() {
  final now = DateTime(2025, 1, 15, 10, 30);
  final sampleJson = {
    'id': 'abc-123',
    'user_id': 'user-1',
    'title': 'Buy groceries',
    'description': 'Milk and eggs',
    'parent_id': 'parent-1',
    'category': 'personal',
    'status': 'active',
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
    'due_date': now.toIso8601String(),
    'completed_at': null,
    'audio_file_uri': null,
    'transcription': 'buy groceries',
    'ai_placement_json': {'confidence': 0.9, 'reasoning': 'test'},
    'priority': 'high',
  };

  group('Task.fromJson', () {
    test('parses all fields', () {
      final task = Task.fromJson(sampleJson);
      expect(task.id, 'abc-123');
      expect(task.userId, 'user-1');
      expect(task.title, 'Buy groceries');
      expect(task.description, 'Milk and eggs');
      expect(task.parentId, 'parent-1');
      expect(task.category, 'personal');
      expect(task.status, 'active');
      expect(task.priority, 'high');
    });

    test('handles nullable null fields', () {
      final json = Map<String, dynamic>.from(sampleJson)
        ..['description'] = null
        ..['parent_id'] = null
        ..['due_date'] = null
        ..['priority'] = null;
      final task = Task.fromJson(json);
      expect(task.description, isNull);
      expect(task.parentId, isNull);
      expect(task.dueDate, isNull);
      expect(task.priority, isNull);
    });

    test('parses dates correctly', () {
      final task = Task.fromJson(sampleJson);
      expect(task.createdAt, now);
      expect(task.updatedAt, now);
      expect(task.dueDate, now);
    });
  });

  group('Task.toJson', () {
    test('round trip preserves data', () {
      final task = Task.fromJson(sampleJson);
      final json = task.toJson();
      final roundTrip = Task.fromJson(json);
      expect(roundTrip.id, task.id);
      expect(roundTrip.title, task.title);
      expect(roundTrip.category, task.category);
    });

    test('nullable fields are included', () {
      final json = Map<String, dynamic>.from(sampleJson)
        ..['description'] = null
        ..['due_date'] = null;
      final task = Task.fromJson(json);
      final output = task.toJson();
      expect(output.containsKey('description'), true);
      expect(output['description'], isNull);
      expect(output['due_date'], isNull);
    });
  });

  group('Task.copyWith', () {
    test('changes single field', () {
      final task = Task.fromJson(sampleJson);
      final copy = task.copyWith(title: 'New title');
      expect(copy.title, 'New title');
      expect(copy.id, task.id); // unchanged
      expect(copy.category, task.category); // unchanged
    });

    test('no changes returns equivalent object', () {
      final task = Task.fromJson(sampleJson);
      final copy = task.copyWith();
      expect(copy.id, task.id);
      expect(copy.title, task.title);
      expect(copy.status, task.status);
    });
  });

  group('Task getters', () {
    test('isCompleted returns true for completed status', () {
      final task = Task.fromJson(
          Map<String, dynamic>.from(sampleJson)..['status'] = 'completed');
      expect(task.isCompleted, true);
      expect(task.isActive, false);
    });

    test('isActive returns true for active status', () {
      final task = Task.fromJson(sampleJson);
      expect(task.isActive, true);
      expect(task.isCompleted, false);
    });
  });
}
