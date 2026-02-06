import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/utils/task_status_utils.dart';
import '../helpers/test_helpers.dart';

void main() {
  group('TaskStatusExtension.effectiveStatusFrom', () {
    test('returns override when present', () {
      final task = createTestTask(id: 't1', status: 'active');
      final overrides = {'t1': 'completed'};
      expect(task.effectiveStatusFrom(overrides), 'completed');
    });

    test('returns original status when no override', () {
      final task = createTestTask(id: 't1', status: 'active');
      expect(task.effectiveStatusFrom({}), 'active');
    });
  });

  group('TaskStatusExtension.isEffectivelyCompletedFrom', () {
    test('true with completed override', () {
      final task = createTestTask(id: 't1', status: 'active');
      expect(task.isEffectivelyCompletedFrom({'t1': 'completed'}), true);
    });

    test('false without override on active task', () {
      final task = createTestTask(id: 't1', status: 'active');
      expect(task.isEffectivelyCompletedFrom({}), false);
    });
  });
}
