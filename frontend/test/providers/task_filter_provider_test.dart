import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/providers/task_filter_provider.dart';
import 'package:frontend/models/task_filter.dart';

void main() {
  group('TaskFilter model', () {
    test('default TaskFilter has isActive false', () {
      const filter = TaskFilter();
      expect(filter.isActive, isFalse);
    });

    test('default activeFilterCount is 0', () {
      const filter = TaskFilter();
      expect(filter.activeFilterCount, 0);
    });

    test('copyWith with categories sets categories', () {
      const filter = TaskFilter();
      final updated = filter.copyWith(categories: ['career', 'home']);
      expect(updated.categories, ['career', 'home']);
    });

    test('isActive true when any filter set', () {
      final withCategories =
          const TaskFilter().copyWith(categories: ['career']);
      expect(withCategories.isActive, isTrue);

      final withPriorities =
          const TaskFilter().copyWith(priorities: ['high']);
      expect(withPriorities.isActive, isTrue);

      final withStatuses =
          const TaskFilter().copyWith(statuses: ['active']);
      expect(withStatuses.isActive, isTrue);

      final withDueDateGte =
          const TaskFilter().copyWith(dueDateGte: DateTime(2025, 1, 1));
      expect(withDueDateGte.isActive, isTrue);

      final withSort = const TaskFilter().copyWith(
        sortOptions: [const SortOption('title')],
      );
      expect(withSort.isActive, isTrue);
    });

    test('activeFilterCount correctly counts multiple filters', () {
      final filter = const TaskFilter().copyWith(
        categories: ['career'],
        priorities: ['high'],
        dueDateGte: DateTime(2025, 1, 1),
        sortOptions: [const SortOption('title')],
      );
      expect(filter.activeFilterCount, 4);
    });
  });

  group('taskFilterProvider', () {
    test('defaults to const TaskFilter()', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final filter = container.read(taskFilterProvider);
      expect(filter.isActive, isFalse);
      expect(filter.activeFilterCount, 0);
      expect(filter.categories, isNull);
      expect(filter.priorities, isNull);
      expect(filter.statuses, isNull);
    });
  });
}
