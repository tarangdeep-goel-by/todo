import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/task.dart';
import '../models/task_filter.dart';
import '../models/category.dart';
import '../config/theme.dart';
import '../services/app_logger.dart';
import 'api_provider.dart';
import 'task_filter_provider.dart';

// --- State ---

class TaskStoreState {
  final Map<String, Task> tasks;
  final bool isLoading;
  final String? error;

  const TaskStoreState({
    this.tasks = const {},
    this.isLoading = false,
    this.error,
  });

  TaskStoreState copyWith({
    Map<String, Task>? tasks,
    bool? isLoading,
    String? error,
  }) {
    return TaskStoreState(
      tasks: tasks ?? this.tasks,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

// --- Notifier ---

class TaskStoreNotifier extends StateNotifier<TaskStoreState> {
  final Ref _ref;
  final _logger = AppLogger.instance;

  TaskStoreNotifier(this._ref) : super(const TaskStoreState());

  /// Fetch all tasks from backend and replace the store.
  /// Paginates through all results (backend max limit=100).
  Future<void> fetchAll() async {
    _logger.info('store.fetch', logger: 'TaskStore');
    state = state.copyWith(isLoading: true, error: null);
    try {
      final apiService = _ref.read(apiServiceProvider);
      final allTasks = <Task>[];
      int offset = 0;
      const limit = 100;

      while (true) {
        final response = await apiService.getTasksAdvanced(
          limit: limit,
          offset: offset,
        );
        allTasks.addAll(response.tasks);
        if (!response.hasMore) break;
        offset += limit;
      }

      final map = {for (final t in allTasks) t.id: t};
      _logger.info('store.fetch', logger: 'TaskStore', data: {'task_count': map.length});
      state = TaskStoreState(tasks: map);

      // Fetch categories and update provider
      try {
        final categories = await apiService.getCategories();
        _ref.read(categoriesProvider.notifier).state = categories;
      } catch (_) {
        // Non-fatal — categories may not be available
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Upsert a single task into the store.
  void upsertTask(Task task) {
    _logger.debug('store.upsert', logger: 'TaskStore', data: {'task_id': task.id});
    state = state.copyWith(tasks: {...state.tasks, task.id: task});
  }

  /// Remove a task from the store.
  void removeTask(String taskId) {
    _logger.debug('store.delete', logger: 'TaskStore', data: {'task_id': taskId});
    final updated = Map<String, Task>.from(state.tasks)..remove(taskId);
    state = state.copyWith(tasks: updated);
  }

  /// Optimistically complete a task and all its descendants (BFS).
  void completeWithDescendants(String taskId) {
    final tasks = Map<String, Task>.from(state.tasks);
    final now = DateTime.now();
    final toProcess = [taskId];
    final visited = <String>{};

    while (toProcess.isNotEmpty) {
      final currentId = toProcess.removeAt(0);
      if (visited.contains(currentId)) continue;
      visited.add(currentId);

      final task = tasks[currentId];
      if (task != null && task.status != 'completed') {
        tasks[currentId] = task.copyWith(status: 'completed', completedAt: now);
      }
      // Find children of currentId
      for (final t in tasks.values) {
        if (t.parentId == currentId && !visited.contains(t.id)) {
          toProcess.add(t.id);
        }
      }
    }

    state = state.copyWith(tasks: tasks);
  }

  /// Activate entire ancestor chain (set completed ancestors to active).
  void activateAncestorChain(String taskId) {
    final tasks = Map<String, Task>.from(state.tasks);
    String? currentId = tasks[taskId]?.parentId;

    while (currentId != null) {
      final ancestor = tasks[currentId];
      if (ancestor == null) break;
      if (ancestor.isCompleted) {
        tasks[currentId] = ancestor.copyWith(status: 'active', completedAt: null);
      }
      currentId = ancestor.parentId;
    }

    state = state.copyWith(tasks: tasks);
  }
}

// --- Main provider ---

final taskStoreProvider =
    StateNotifierProvider<TaskStoreNotifier, TaskStoreState>((ref) {
  return TaskStoreNotifier(ref);
});

// --- Derived providers ---

/// All tasks as a list (for node view).
final allTasksProvider = Provider<List<Task>>((ref) {
  return ref.watch(taskStoreProvider).tasks.values.toList();
});

/// Backend-sourced categories (persisted independently of tasks).
final categoriesProvider = StateProvider<List<Category>>((ref) => []);

/// Canonical domain→palette mapping derived from backend categories.
/// Uses category.position as the palette index for stable colors.
final domainPalettesProvider = Provider<Map<String, DomainPalette>>((ref) {
  final cats = ref.watch(categoriesProvider);
  final map = <String, DomainPalette>{};
  for (final cat in cats) {
    map[cat.name] = DomainColors.byIndex(cat.position, cat.displayName);
  }
  return map;
});

/// Tasks filtered by category (for domain cards).
final tasksByCategoryProvider = Provider.autoDispose.family<List<Task>, String>((ref, category) {
  final all = ref.watch(allTasksProvider);
  return all
      .where((t) => t.category.toLowerCase() == category.toLowerCase())
      .toList();
});

/// Single task by ID (for overlay).
final taskByIdProvider = Provider.family<Task?, String>((ref, id) {
  return ref.watch(taskStoreProvider).tasks[id];
});

/// Children of a given task (for overlay subtasks).
final childTasksProvider = Provider.autoDispose.family<List<Task>, String>((ref, parentId) {
  final all = ref.watch(allTasksProvider);
  return all.where((t) => t.parentId == parentId).toList();
});

/// Flat view tasks: filtered + sorted, with parent-hiding.
/// Parents that have active children are hidden — children show instead.
final flatViewTasksProvider = Provider<List<Task>>((ref) {
  final all = ref.watch(allTasksProvider);
  final filter = ref.watch(taskFilterProvider);
  final filtered = _filterAndSort(all, filter);

  // Build set of parents that have active children (using unfiltered list)
  final parentsWithActiveChildren = <String>{};
  for (final task in all) {
    if (task.parentId != null && task.status == 'active') {
      parentsWithActiveChildren.add(task.parentId!);
    }
  }

  return filtered.where((t) => !parentsWithActiveChildren.contains(t.id)).toList();
});

/// Maps task ID → L1 (root) parent title for subtitle display.
/// Uses memoized root-finding with path compression for O(n) amortized.
final l1ParentNamesProvider = Provider<Map<String, String>>((ref) {
  final tasks = ref.watch(taskStoreProvider).tasks;
  final rootCache = <String, String?>{}; // taskId → root title (cached)

  String? findRoot(String id) {
    if (rootCache.containsKey(id)) return rootCache[id];
    final task = tasks[id];
    if (task == null) { rootCache[id] = null; return null; }
    if (task.parentId == null) { rootCache[id] = task.title; return task.title; }
    final parentRoot = findRoot(task.parentId!);
    rootCache[id] = parentRoot;
    return parentRoot;
  }

  final result = <String, String>{};
  for (final task in tasks.values) {
    if (task.parentId == null) continue;
    final rootTitle = findRoot(task.parentId!);
    if (rootTitle != null) result[task.id] = rootTitle;
  }
  return result;
});

// --- Client-side filter + sort ---

List<Task> _filterAndSort(List<Task> tasks, TaskFilter filter) {
  // Chain .where() predicates without intermediate .toList()
  Iterable<Task> filtered = tasks;

  // Filter by category
  if (filter.categories != null && filter.categories!.isNotEmpty) {
    final cats = filter.categories!.map((c) => c.toLowerCase()).toSet();
    filtered = filtered.where((t) => cats.contains(t.category.toLowerCase()));
  }

  // Filter by priority
  if (filter.priorities != null && filter.priorities!.isNotEmpty) {
    final pris = filter.priorities!.map((p) => p.toLowerCase()).toSet();
    filtered = filtered.where((t) => t.priority != null && pris.contains(t.priority!.toLowerCase()));
  }

  // Filter by status (overdue is computed: active + past due)
  if (filter.statuses != null && filter.statuses!.isNotEmpty) {
    final stats = filter.statuses!.map((s) => s.toLowerCase()).toSet();
    filtered = filtered.where((t) {
      final displayStatus = _computeDisplayStatus(t);
      return stats.contains(displayStatus);
    });
  }

  // Filter by date ranges
  if (filter.createdAtGte != null) {
    filtered = filtered.where((t) => !t.createdAt.isBefore(filter.createdAtGte!));
  }
  if (filter.createdAtLte != null) {
    filtered = filtered.where((t) => !t.createdAt.isAfter(filter.createdAtLte!));
  }
  if (filter.dueDateGte != null) {
    filtered = filtered.where((t) => t.dueDate != null && !t.dueDate!.isBefore(filter.dueDateGte!));
  }
  if (filter.dueDateLte != null) {
    filtered = filtered.where((t) => t.dueDate != null && !t.dueDate!.isAfter(filter.dueDateLte!));
  }

  // Single materialization before sort
  final result = filtered.toList();

  // Sort — default: status asc, due_date asc, priority desc, created_at desc
  if (filter.sortOptions.isNotEmpty) {
    result.sort((a, b) => _multiSort(a, b, filter.sortOptions));
  } else {
    result.sort((a, b) => _multiSort(a, b, const [
      SortOption('status', ascending: true),
      SortOption('due_date', ascending: true),
      SortOption('priority', ascending: false),
      SortOption('created_at', ascending: false),
    ]));
  }

  return result;
}

int _multiSort(Task a, Task b, List<SortOption> sorts) {
  for (final sort in sorts) {
    final cmp = _compareField(a, b, sort.field, sort.ascending);
    if (cmp != 0) return cmp;
  }
  return 0;
}

/// Compute display status: active tasks past due become 'overdue',
/// active tasks due within 48h become 'due_soon'.
String _computeDisplayStatus(Task t) {
  if (t.status == 'active' && t.dueDate != null) {
    final now = DateTime.now();
    if (t.dueDate!.isBefore(now)) {
      return 'overdue';
    }
    if (t.dueDate!.isBefore(now.add(const Duration(hours: 48)))) {
      return 'due_soon';
    }
  }
  return t.status;
}

int _compareField(Task a, Task b, String field, bool ascending) {
  int result;
  switch (field) {
    case 'status':
      result = _statusRank(_computeDisplayStatus(a)).compareTo(_statusRank(_computeDisplayStatus(b)));
    case 'priority':
      result = _priorityRank(a.priority).compareTo(_priorityRank(b.priority));
    case 'due_date':
      result = _compareNullableDate(a.dueDate, b.dueDate);
    case 'created_at':
      result = a.createdAt.compareTo(b.createdAt);
    case 'updated_at':
      result = a.updatedAt.compareTo(b.updatedAt);
    case 'title':
      result = a.title.toLowerCase().compareTo(b.title.toLowerCase());
    default:
      result = 0;
  }
  return ascending ? result : -result;
}

int _statusRank(String status) {
  switch (status) {
    case 'overdue':
      return 0;
    case 'due_soon':
      return 1;
    case 'active':
      return 2;
    default:
      return 3; // completed
  }
}

int _priorityRank(String? priority) {
  switch (priority) {
    case 'high':
      return 3;
    case 'medium':
      return 2;
    case 'low':
      return 1;
    default:
      return 0; // null/none
  }
}

int _compareNullableDate(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1; // nulls last
  if (b == null) return -1;
  return a.compareTo(b);
}
