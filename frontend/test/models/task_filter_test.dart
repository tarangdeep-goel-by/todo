import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/task_filter.dart';

void main() {
  group('TaskFilter.copyWith sentinel pattern', () {
    test('set value', () {
      const f = TaskFilter();
      final updated = f.copyWith(categories: ['work']);
      expect(updated.categories, ['work']);
    });

    test('clear value to null', () {
      final f = const TaskFilter(categories: ['work']);
      final cleared = f.copyWith(categories: null);
      expect(cleared.categories, isNull);
    });

    test('no change preserves existing', () {
      const f = TaskFilter(categories: ['work'], priorities: ['high']);
      final same = f.copyWith();
      expect(same.categories, ['work']);
      expect(same.priorities, ['high']);
    });
  });

  group('TaskFilter.isActive', () {
    test('false when no filters', () {
      const f = TaskFilter();
      expect(f.isActive, false);
    });

    test('true with categories', () {
      const f = TaskFilter(categories: ['work']);
      expect(f.isActive, true);
    });

    test('true with sort options', () {
      final f = TaskFilter(sortOptions: [SortOption('title')]);
      expect(f.isActive, true);
    });
  });

  group('TaskFilter.activeFilterCount', () {
    test('zero when empty', () {
      const f = TaskFilter();
      expect(f.activeFilterCount, 0);
    });

    test('counts multiple filters', () {
      final f = TaskFilter(
        categories: ['work'],
        priorities: ['high'],
        sortOptions: [SortOption('title')],
      );
      expect(f.activeFilterCount, 3);
    });
  });

  group('SortOption.toQueryString', () {
    test('ascending', () {
      const s = SortOption('title', ascending: true);
      expect(s.toQueryString(), 'title:asc');
    });

    test('descending', () {
      const s = SortOption('created_at', ascending: false);
      expect(s.toQueryString(), 'created_at:desc');
    });
  });
}
