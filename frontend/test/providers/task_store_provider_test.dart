import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:frontend/providers/task_store_provider.dart';
import 'package:frontend/providers/task_filter_provider.dart';
import 'package:frontend/providers/api_provider.dart';
import 'package:frontend/models/task_filter.dart';
import 'package:frontend/models/api_response.dart';
import '../helpers/test_helpers.dart';

void main() {
  late MockApiService mockApi;
  late ProviderContainer container;

  setUp(() {
    mockApi = MockApiService();
    final localData = createTestLocalData();
    container = ProviderContainer(overrides: [
      apiServiceProvider.overrideWithValue(mockApi),
      localData.override,
    ]);
  });

  tearDown(() => container.dispose());

  // ─── Helpers ───────────────────────────────────────────────

  void seedStore(List<Map<String, dynamic>> specs) {
    final notifier = container.read(taskStoreProvider.notifier);
    for (final s in specs) {
      notifier.upsertTask(createTestTask(
        id: s['id'] as String,
        title: s['title'] as String? ?? s['id'] as String,
        category: s['category'] as String? ?? 'career',
        status: s['status'] as String? ?? 'active',
        priority: s['priority'] as String?,
        parentId: s['parentId'] as String?,
        dueDate: s['dueDate'] as DateTime?,
        createdAt: s['createdAt'] as DateTime?,
      ));
    }
  }

  // ─── TaskStoreNotifier ─────────────────────────────────────

  group('TaskStoreNotifier', () {
    test('initial state is empty, not loading, no error', () {
      final state = container.read(taskStoreProvider);
      expect(state.tasks, isEmpty);
      expect(state.isLoading, false);
      expect(state.error, isNull);
    });

    test('fetchAll populates store from API', () async {
      final tasks = [
        createTestTask(id: 'a', title: 'Alpha'),
        createTestTask(id: 'b', title: 'Beta'),
      ];
      when(() => mockApi.getTasksAdvancedWithRetry(
        limit: any(named: 'limit'),
        offset: any(named: 'offset'),
      )).thenAnswer((_) async => TaskListResponse(
        tasks: tasks, totalCount: 2, limit: 100, offset: 0, hasMore: false,
      ));

      await container.read(taskStoreProvider.notifier).fetchAll();

      final state = container.read(taskStoreProvider);
      expect(state.tasks.length, 2);
      expect(state.tasks['a']!.title, 'Alpha');
      expect(state.tasks['b']!.title, 'Beta');
      expect(state.isLoading, false);
      expect(state.error, isNull);
    });

    test('fetchAll replaces existing tasks', () async {
      // Seed one task
      container.read(taskStoreProvider.notifier).upsertTask(
        createTestTask(id: 'old', title: 'Old'),
      );

      // Fetch returns different set
      when(() => mockApi.getTasksAdvancedWithRetry(
        limit: any(named: 'limit'),
        offset: any(named: 'offset'),
      )).thenAnswer((_) async => TaskListResponse(
        tasks: [createTestTask(id: 'new', title: 'New')],
        totalCount: 1, limit: 100, offset: 0, hasMore: false,
      ));

      await container.read(taskStoreProvider.notifier).fetchAll();

      final state = container.read(taskStoreProvider);
      expect(state.tasks.containsKey('old'), false);
      expect(state.tasks.containsKey('new'), true);
    });

    test('fetchAll sets error on failure, preserves existing tasks', () async {
      container.read(taskStoreProvider.notifier).upsertTask(
        createTestTask(id: 'existing'),
      );

      when(() => mockApi.getTasksAdvancedWithRetry(
        limit: any(named: 'limit'),
        offset: any(named: 'offset'),
      )).thenThrow(Exception('network'));

      await container.read(taskStoreProvider.notifier).fetchAll();

      final state = container.read(taskStoreProvider);
      expect(state.error, contains('network'));
      expect(state.isLoading, false);
      expect(state.tasks.containsKey('existing'), true);
    });

    test('upsertTask adds new task', () {
      container.read(taskStoreProvider.notifier).upsertTask(
        createTestTask(id: 't1', title: 'Task 1'),
      );

      expect(container.read(taskStoreProvider).tasks['t1']!.title, 'Task 1');
    });

    test('upsertTask updates existing task', () {
      final notifier = container.read(taskStoreProvider.notifier);
      notifier.upsertTask(createTestTask(id: 't1', title: 'Before'));
      notifier.upsertTask(createTestTask(id: 't1', title: 'After'));

      expect(container.read(taskStoreProvider).tasks['t1']!.title, 'After');
      expect(container.read(taskStoreProvider).tasks.length, 1);
    });

    test('removeTask removes task', () {
      final notifier = container.read(taskStoreProvider.notifier);
      notifier.upsertTask(createTestTask(id: 't1'));
      notifier.upsertTask(createTestTask(id: 't2'));

      notifier.removeTask('t1');

      final tasks = container.read(taskStoreProvider).tasks;
      expect(tasks.containsKey('t1'), false);
      expect(tasks.containsKey('t2'), true);
    });

    test('removeTask no-op for missing id', () {
      container.read(taskStoreProvider.notifier).upsertTask(
        createTestTask(id: 't1'),
      );

      container.read(taskStoreProvider.notifier).removeTask('nonexistent');

      expect(container.read(taskStoreProvider).tasks.length, 1);
    });
  });

  // ─── Derived providers ─────────────────────────────────────

  group('allTasksProvider', () {
    test('returns all tasks as list', () {
      seedStore([
        {'id': 'a'},
        {'id': 'b'},
        {'id': 'c'},
      ]);

      final all = container.read(allTasksProvider);
      expect(all.length, 3);
    });

    test('empty when store is empty', () {
      expect(container.read(allTasksProvider), isEmpty);
    });
  });

  group('tasksByCategoryProvider', () {
    test('filters by category case-insensitive', () {
      seedStore([
        {'id': 'w1', 'category': 'career'},
        {'id': 'w2', 'category': 'Career'},
        {'id': 'p1', 'category': 'home'},
      ]);

      final work = container.read(tasksByCategoryProvider('career'));
      expect(work.length, 2);

      final personal = container.read(tasksByCategoryProvider('Home'));
      expect(personal.length, 1);
    });

    test('returns empty for unknown category', () {
      seedStore([{'id': 'w1', 'category': 'career'}]);

      expect(container.read(tasksByCategoryProvider('health')), isEmpty);
    });
  });

  group('taskByIdProvider', () {
    test('returns task when exists', () {
      seedStore([{'id': 'x', 'title': 'Found'}]);

      expect(container.read(taskByIdProvider('x'))!.title, 'Found');
    });

    test('returns null when missing', () {
      expect(container.read(taskByIdProvider('nope')), isNull);
    });
  });

  group('childTasksProvider', () {
    test('returns direct children', () {
      seedStore([
        {'id': 'parent'},
        {'id': 'child1', 'parentId': 'parent'},
        {'id': 'child2', 'parentId': 'parent'},
        {'id': 'grandchild', 'parentId': 'child1'},
        {'id': 'other'},
      ]);

      final children = container.read(childTasksProvider('parent'));
      expect(children.length, 2);
      expect(children.map((t) => t.id).toSet(), {'child1', 'child2'});
    });

    test('returns empty when no children', () {
      seedStore([{'id': 'leaf'}]);
      expect(container.read(childTasksProvider('leaf')), isEmpty);
    });
  });

  // ─── Flat view: filter ─────────────────────────────────────

  group('flatViewTasksProvider filtering', () {
    test('no filter returns all tasks', () {
      seedStore([
        {'id': 'a'},
        {'id': 'b'},
      ]);

      expect(container.read(flatViewTasksProvider).length, 2);
    });

    test('filter by category', () {
      seedStore([
        {'id': 'w1', 'category': 'career'},
        {'id': 'p1', 'category': 'home'},
        {'id': 'w2', 'category': 'career'},
      ]);

      container.read(taskFilterProvider.notifier).state =
          const TaskFilter(categories: ['career']);

      final result = container.read(flatViewTasksProvider);
      expect(result.length, 2);
      expect(result.every((t) => t.category == 'career'), true);
    });

    test('filter by priority', () {
      seedStore([
        {'id': 'h1', 'priority': 'high'},
        {'id': 'l1', 'priority': 'low'},
        {'id': 'n1'}, // null priority
      ]);

      container.read(taskFilterProvider.notifier).state =
          const TaskFilter(priorities: ['high']);

      final result = container.read(flatViewTasksProvider);
      expect(result.length, 1);
      expect(result.first.id, 'h1');
    });

    test('filter by status', () {
      seedStore([
        {'id': 'a1', 'status': 'active'},
        {'id': 'c1', 'status': 'completed'},
      ]);

      container.read(taskFilterProvider.notifier).state =
          const TaskFilter(statuses: ['completed']);

      final result = container.read(flatViewTasksProvider);
      expect(result.length, 1);
      expect(result.first.id, 'c1');
    });

    test('filter by multiple dimensions (AND)', () {
      seedStore([
        {'id': 't1', 'category': 'career', 'priority': 'high', 'status': 'active'},
        {'id': 't2', 'category': 'career', 'priority': 'low', 'status': 'active'},
        {'id': 't3', 'category': 'home', 'priority': 'high', 'status': 'active'},
      ]);

      container.read(taskFilterProvider.notifier).state =
          const TaskFilter(categories: ['career'], priorities: ['high']);

      final result = container.read(flatViewTasksProvider);
      expect(result.length, 1);
      expect(result.first.id, 't1');
    });

    test('filter by createdAt date range', () {
      seedStore([
        {'id': 'old', 'createdAt': DateTime(2025, 1, 1)},
        {'id': 'mid', 'createdAt': DateTime(2025, 6, 15)},
        {'id': 'new', 'createdAt': DateTime(2025, 12, 31)},
      ]);

      container.read(taskFilterProvider.notifier).state = TaskFilter(
        createdAtGte: DateTime(2025, 6, 1),
        createdAtLte: DateTime(2025, 6, 30),
      );

      final result = container.read(flatViewTasksProvider);
      expect(result.length, 1);
      expect(result.first.id, 'mid');
    });

    test('filter by dueDate range excludes tasks without dueDate', () {
      seedStore([
        {'id': 'due', 'dueDate': DateTime(2025, 3, 15)},
        {'id': 'nodue'}, // null dueDate
      ]);

      container.read(taskFilterProvider.notifier).state = TaskFilter(
        dueDateGte: DateTime(2025, 1, 1),
        dueDateLte: DateTime(2025, 12, 31),
      );

      final result = container.read(flatViewTasksProvider);
      expect(result.length, 1);
      expect(result.first.id, 'due');
    });
  });

  // ─── Due Soon ──────────────────────────────────────────────

  group('due_soon status', () {
    test('_computeDisplayStatus returns due_soon for task due in 24h', () {
      seedStore([
        {
          'id': 'soon',
          'status': 'active',
          'dueDate': DateTime.now().add(const Duration(hours: 24)),
        },
      ]);

      container.read(taskFilterProvider.notifier).state =
          const TaskFilter(statuses: ['due_soon']);

      final result = container.read(flatViewTasksProvider);
      expect(result.length, 1);
      expect(result.first.id, 'soon');
    });

    test('task due in 49h is active, not due_soon', () {
      seedStore([
        {
          'id': 'later',
          'status': 'active',
          'dueDate': DateTime.now().add(const Duration(hours: 49)),
        },
      ]);

      container.read(taskFilterProvider.notifier).state =
          const TaskFilter(statuses: ['due_soon']);

      final result = container.read(flatViewTasksProvider);
      expect(result, isEmpty);
    });

    test('overdue task stays overdue, not due_soon', () {
      seedStore([
        {
          'id': 'past',
          'status': 'active',
          'dueDate': DateTime.now().subtract(const Duration(hours: 1)),
        },
      ]);

      container.read(taskFilterProvider.notifier).state =
          const TaskFilter(statuses: ['due_soon']);

      final result = container.read(flatViewTasksProvider);
      expect(result, isEmpty);
    });

    test('sort order: overdue < due_soon < active < completed', () {
      seedStore([
        {'id': 'completed', 'status': 'completed'},
        {'id': 'active', 'status': 'active'},
        {
          'id': 'due_soon',
          'status': 'active',
          'dueDate': DateTime.now().add(const Duration(hours: 24)),
        },
        {
          'id': 'overdue',
          'status': 'active',
          'dueDate': DateTime.now().subtract(const Duration(hours: 1)),
        },
      ]);

      final result = container.read(flatViewTasksProvider);
      expect(result[0].id, 'overdue');
      expect(result[1].id, 'due_soon');
      expect(result[2].id, 'active');
      expect(result[3].id, 'completed');
    });
  });

  // ─── Flat view: sort ───────────────────────────────────────

  group('flatViewTasksProvider sorting', () {
    test('default sort: active before completed', () {
      seedStore([
        {'id': 'c1', 'status': 'completed'},
        {'id': 'a1', 'status': 'active'},
      ]);

      final result = container.read(flatViewTasksProvider);
      expect(result.first.id, 'a1');
      expect(result.last.id, 'c1');
    });

    test('default sort: with due date before without (nulls last)', () {
      seedStore([
        {'id': 'nodue', 'status': 'active'},
        {'id': 'due', 'status': 'active', 'dueDate': DateTime(2025, 6, 1)},
      ]);

      final result = container.read(flatViewTasksProvider);
      expect(result.first.id, 'due');
      expect(result.last.id, 'nodue');
    });

    test('default sort: high priority before low (desc)', () {
      // Same status, same due date (null) → priority desc kicks in
      seedStore([
        {'id': 'low', 'status': 'active', 'priority': 'low'},
        {'id': 'high', 'status': 'active', 'priority': 'high'},
        {'id': 'med', 'status': 'active', 'priority': 'medium'},
      ]);

      final result = container.read(flatViewTasksProvider);
      expect(result[0].id, 'high');
      expect(result[1].id, 'med');
      expect(result[2].id, 'low');
    });

    test('default sort: null priority after explicit priority', () {
      seedStore([
        {'id': 'none', 'status': 'active'},
        {'id': 'low', 'status': 'active', 'priority': 'low'},
      ]);

      final result = container.read(flatViewTasksProvider);
      expect(result[0].id, 'low');
      expect(result[1].id, 'none');
    });

    test('default sort: newer createdAt first among equal tasks (desc)', () {
      seedStore([
        {'id': 'old', 'status': 'active', 'createdAt': DateTime(2025, 1, 1)},
        {'id': 'new', 'status': 'active', 'createdAt': DateTime(2025, 6, 1)},
      ]);

      final result = container.read(flatViewTasksProvider);
      expect(result[0].id, 'new');
      expect(result[1].id, 'old');
    });

    test('custom sort: title ascending', () {
      seedStore([
        {'id': 'c', 'title': 'Charlie'},
        {'id': 'a', 'title': 'Alpha'},
        {'id': 'b', 'title': 'Bravo'},
      ]);

      container.read(taskFilterProvider.notifier).state =
          const TaskFilter(sortOptions: [SortOption('title', ascending: true)]);

      final result = container.read(flatViewTasksProvider);
      expect(result[0].title, 'Alpha');
      expect(result[1].title, 'Bravo');
      expect(result[2].title, 'Charlie');
    });

    test('custom sort: title descending', () {
      seedStore([
        {'id': 'a', 'title': 'Alpha'},
        {'id': 'c', 'title': 'Charlie'},
      ]);

      container.read(taskFilterProvider.notifier).state =
          const TaskFilter(sortOptions: [SortOption('title', ascending: false)]);

      final result = container.read(flatViewTasksProvider);
      expect(result[0].title, 'Charlie');
      expect(result[1].title, 'Alpha');
    });

    test('custom sort: due_date ascending with nulls last', () {
      seedStore([
        {'id': 'none'},
        {'id': 'late', 'dueDate': DateTime(2025, 12, 1)},
        {'id': 'early', 'dueDate': DateTime(2025, 1, 1)},
      ]);

      container.read(taskFilterProvider.notifier).state =
          const TaskFilter(sortOptions: [SortOption('due_date', ascending: true)]);

      final result = container.read(flatViewTasksProvider);
      expect(result[0].id, 'early');
      expect(result[1].id, 'late');
      expect(result[2].id, 'none');
    });

    test('custom sort: multi-field sort', () {
      seedStore([
        {'id': 'a-low', 'status': 'active', 'priority': 'low'},
        {'id': 'a-high', 'status': 'active', 'priority': 'high'},
        {'id': 'c-high', 'status': 'completed', 'priority': 'high'},
      ]);

      container.read(taskFilterProvider.notifier).state = const TaskFilter(
        sortOptions: [
          SortOption('status', ascending: true),
          SortOption('priority', ascending: false),
        ],
      );

      final result = container.read(flatViewTasksProvider);
      expect(result[0].id, 'a-high'); // active, high
      expect(result[1].id, 'a-low'); // active, low
      expect(result[2].id, 'c-high'); // completed, high
    });
  });

  // ─── Reactivity ────────────────────────────────────────────

  group('reactivity', () {
    test('derived providers update when store changes', () {
      expect(container.read(allTasksProvider), isEmpty);

      container.read(taskStoreProvider.notifier).upsertTask(
        createTestTask(id: 'r1', category: 'career'),
      );

      expect(container.read(allTasksProvider).length, 1);
      expect(container.read(tasksByCategoryProvider('career')).length, 1);
      expect(container.read(taskByIdProvider('r1')), isNotNull);
      expect(container.read(flatViewTasksProvider).length, 1);
    });

    test('filter change updates flatViewTasksProvider', () {
      seedStore([
        {'id': 'w1', 'category': 'career'},
        {'id': 'p1', 'category': 'home'},
      ]);

      expect(container.read(flatViewTasksProvider).length, 2);

      container.read(taskFilterProvider.notifier).state =
          const TaskFilter(categories: ['career']);

      expect(container.read(flatViewTasksProvider).length, 1);

      // Clear filter
      container.read(taskFilterProvider.notifier).state = const TaskFilter();
      expect(container.read(flatViewTasksProvider).length, 2);
    });

    test('upsert reflects in taskByIdProvider immediately', () {
      container.read(taskStoreProvider.notifier).upsertTask(
        createTestTask(id: 'live', title: 'Version 1'),
      );
      expect(container.read(taskByIdProvider('live'))!.title, 'Version 1');

      container.read(taskStoreProvider.notifier).upsertTask(
        createTestTask(id: 'live', title: 'Version 2'),
      );
      expect(container.read(taskByIdProvider('live'))!.title, 'Version 2');
    });

    test('remove reflects in childTasksProvider', () {
      seedStore([
        {'id': 'parent'},
        {'id': 'child', 'parentId': 'parent'},
      ]);

      expect(container.read(childTasksProvider('parent')).length, 1);

      container.read(taskStoreProvider.notifier).removeTask('child');
      expect(container.read(childTasksProvider('parent')), isEmpty);
    });
  });

  // ─── TaskStoreState ────────────────────────────────────────

  group('TaskStoreState', () {
    test('copyWith preserves fields when not specified', () {
      final original = TaskStoreState(
        tasks: {'a': createTestTask(id: 'a')},
        isLoading: true,
        error: 'err',
      );

      final copy = original.copyWith();
      expect(copy.tasks.length, 1);
      expect(copy.isLoading, true);
      // error is nullable — copyWith(error: null) clears it
    });

    test('copyWith clears error when set to null', () {
      final original = TaskStoreState(error: 'err');
      final copy = original.copyWith(error: null);
      expect(copy.error, isNull);
    });
  });

  // ─── Cascade methods ────────────────────────────────────────

  group('completeWithDescendants', () {
    test('completes task and all children', () {
      seedStore([
        {'id': 'p', 'status': 'active'},
        {'id': 'c1', 'parentId': 'p', 'status': 'active'},
        {'id': 'c2', 'parentId': 'p', 'status': 'active'},
      ]);

      container.read(taskStoreProvider.notifier).completeWithDescendants('p');

      expect(container.read(taskByIdProvider('p'))!.status, 'completed');
      expect(container.read(taskByIdProvider('c1'))!.status, 'completed');
      expect(container.read(taskByIdProvider('c2'))!.status, 'completed');
    });

    test('handles deep tree (grandchildren)', () {
      seedStore([
        {'id': 'gp', 'status': 'active'},
        {'id': 'p', 'parentId': 'gp', 'status': 'active'},
        {'id': 'c', 'parentId': 'p', 'status': 'active'},
      ]);

      container.read(taskStoreProvider.notifier).completeWithDescendants('gp');

      expect(container.read(taskByIdProvider('gp'))!.status, 'completed');
      expect(container.read(taskByIdProvider('p'))!.status, 'completed');
      expect(container.read(taskByIdProvider('c'))!.status, 'completed');
    });

    test('skips already-completed descendants', () {
      seedStore([
        {'id': 'p', 'status': 'active'},
        {'id': 'c', 'parentId': 'p', 'status': 'completed'},
      ]);

      container.read(taskStoreProvider.notifier).completeWithDescendants('p');

      expect(container.read(taskByIdProvider('p'))!.status, 'completed');
      expect(container.read(taskByIdProvider('c'))!.status, 'completed');
    });
  });

  group('activateAncestorChain', () {
    test('activates completed parent', () {
      seedStore([
        {'id': 'p', 'status': 'completed'},
        {'id': 'c', 'parentId': 'p', 'status': 'active'},
      ]);

      container.read(taskStoreProvider.notifier).activateAncestorChain('c');

      expect(container.read(taskByIdProvider('p'))!.status, 'active');
    });

    test('activates entire ancestor chain', () {
      seedStore([
        {'id': 'gp', 'status': 'completed'},
        {'id': 'p', 'parentId': 'gp', 'status': 'completed'},
        {'id': 'c', 'parentId': 'p', 'status': 'active'},
      ]);

      container.read(taskStoreProvider.notifier).activateAncestorChain('c');

      expect(container.read(taskByIdProvider('gp'))!.status, 'active');
      expect(container.read(taskByIdProvider('p'))!.status, 'active');
    });

    test('no-op for root task (no parent)', () {
      seedStore([
        {'id': 'root', 'status': 'active'},
      ]);

      // Should not throw
      container.read(taskStoreProvider.notifier).activateAncestorChain('root');

      expect(container.read(taskByIdProvider('root'))!.status, 'active');
    });

    test('skips already-active ancestors', () {
      seedStore([
        {'id': 'gp', 'status': 'active'},
        {'id': 'p', 'parentId': 'gp', 'status': 'completed'},
        {'id': 'c', 'parentId': 'p', 'status': 'active'},
      ]);

      container.read(taskStoreProvider.notifier).activateAncestorChain('c');

      expect(container.read(taskByIdProvider('p'))!.status, 'active');
      expect(container.read(taskByIdProvider('gp'))!.status, 'active');
    });
  });

  // ─── Flat view: parent-hiding ───────────────────────────────

  group('flatViewTasksProvider parent-hiding', () {
    test('hides parent with active children', () {
      seedStore([
        {'id': 'parent', 'title': 'Parent Task'},
        {'id': 'child1', 'parentId': 'parent', 'status': 'active'},
        {'id': 'child2', 'parentId': 'parent', 'status': 'active'},
      ]);

      final result = container.read(flatViewTasksProvider);
      expect(result.map((t) => t.id).toList(), isNot(contains('parent')));
      expect(result.length, 2);
    });

    test('shows parent when all children are completed', () {
      seedStore([
        {'id': 'parent', 'title': 'Parent Task'},
        {'id': 'child1', 'parentId': 'parent', 'status': 'completed'},
        {'id': 'child2', 'parentId': 'parent', 'status': 'completed'},
      ]);

      final result = container.read(flatViewTasksProvider);
      expect(result.map((t) => t.id).toList(), contains('parent'));
    });

    test('handles 3-level chains — hides middle and root', () {
      seedStore([
        {'id': 'root', 'title': 'Root'},
        {'id': 'mid', 'parentId': 'root', 'status': 'active'},
        {'id': 'leaf', 'parentId': 'mid', 'status': 'active'},
      ]);

      final result = container.read(flatViewTasksProvider);
      // root hidden (mid is active child), mid hidden (leaf is active child)
      expect(result.map((t) => t.id).toList(), isNot(contains('root')));
      expect(result.map((t) => t.id).toList(), isNot(contains('mid')));
      expect(result.map((t) => t.id).toList(), contains('leaf'));
    });

    test('leaf-only tasks are always shown', () {
      seedStore([
        {'id': 'standalone', 'title': 'No Children'},
      ]);

      final result = container.read(flatViewTasksProvider);
      expect(result.length, 1);
      expect(result.first.id, 'standalone');
    });

    test('parent hidden even when children filtered out by category', () {
      seedStore([
        {'id': 'parent', 'title': 'Career Parent', 'category': 'career'},
        {'id': 'child', 'parentId': 'parent', 'status': 'active', 'category': 'home'},
      ]);

      container.read(taskFilterProvider.notifier).state =
          const TaskFilter(categories: ['career']);

      final result = container.read(flatViewTasksProvider);
      // parent is hidden because child is active (uses unfiltered list)
      expect(result, isEmpty);
    });
  });

  // ─── L1 parent names ────────────────────────────────────────

  group('l1ParentNamesProvider', () {
    test('maps child to root parent title', () {
      seedStore([
        {'id': 'root', 'title': 'Root Task'},
        {'id': 'child', 'title': 'Child', 'parentId': 'root'},
      ]);

      final names = container.read(l1ParentNamesProvider);
      expect(names['child'], 'Root Task');
      expect(names.containsKey('root'), false);
    });

    test('maps grandchild to root parent title', () {
      seedStore([
        {'id': 'root', 'title': 'Root'},
        {'id': 'mid', 'title': 'Mid', 'parentId': 'root'},
        {'id': 'leaf', 'title': 'Leaf', 'parentId': 'mid'},
      ]);

      final names = container.read(l1ParentNamesProvider);
      expect(names['mid'], 'Root');
      expect(names['leaf'], 'Root');
    });

    test('returns empty map for root-only tasks', () {
      seedStore([
        {'id': 'a', 'title': 'Task A'},
        {'id': 'b', 'title': 'Task B'},
      ]);

      final names = container.read(l1ParentNamesProvider);
      expect(names, isEmpty);
    });
  });
}
