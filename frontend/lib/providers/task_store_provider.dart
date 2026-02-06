import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/task.dart';
import '../models/task_filter.dart';
import '../config/constants.dart';
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

  TaskStoreNotifier(this._ref) : super(const TaskStoreState());

  /// Fetch all tasks from backend and replace the store.
  Future<void> fetchAll() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final apiService = _ref.read(apiServiceProvider);
      final tasks = await apiService.getTasks(AppConstants.defaultUserId);
      final map = {for (final t in tasks) t.id: t};
      state = TaskStoreState(tasks: map);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Upsert a single task into the store.
  void upsertTask(Task task) {
    state = state.copyWith(tasks: {...state.tasks, task.id: task});
  }

  /// Remove a task from the store.
  void removeTask(String taskId) {
    final updated = Map<String, Task>.from(state.tasks)..remove(taskId);
    state = state.copyWith(tasks: updated);
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

/// Tasks filtered by category (for domain cards).
final tasksByCategoryProvider = Provider.family<List<Task>, String>((ref, category) {
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
final childTasksProvider = Provider.family<List<Task>, String>((ref, parentId) {
  final all = ref.watch(allTasksProvider);
  return all.where((t) => t.parentId == parentId).toList();
});

/// Flat view tasks: filtered + sorted client-side using TaskFilter.
final flatViewTasksProvider = Provider<List<Task>>((ref) {
  final all = ref.watch(allTasksProvider);
  final filter = ref.watch(taskFilterProvider);
  return _filterAndSort(all, filter);
});

// --- Client-side filter + sort ---

List<Task> _filterAndSort(List<Task> tasks, TaskFilter filter) {
  var result = tasks.toList();

  // Filter by category
  if (filter.categories != null && filter.categories!.isNotEmpty) {
    final cats = filter.categories!.map((c) => c.toLowerCase()).toSet();
    result = result.where((t) => cats.contains(t.category.toLowerCase())).toList();
  }

  // Filter by priority
  if (filter.priorities != null && filter.priorities!.isNotEmpty) {
    final pris = filter.priorities!.map((p) => p.toLowerCase()).toSet();
    result = result.where((t) => t.priority != null && pris.contains(t.priority!.toLowerCase())).toList();
  }

  // Filter by status
  if (filter.statuses != null && filter.statuses!.isNotEmpty) {
    final stats = filter.statuses!.map((s) => s.toLowerCase()).toSet();
    result = result.where((t) => stats.contains(t.status.toLowerCase())).toList();
  }

  // Filter by date ranges
  if (filter.createdAtGte != null) {
    result = result.where((t) => !t.createdAt.isBefore(filter.createdAtGte!)).toList();
  }
  if (filter.createdAtLte != null) {
    result = result.where((t) => !t.createdAt.isAfter(filter.createdAtLte!)).toList();
  }
  if (filter.dueDateGte != null) {
    result = result.where((t) => t.dueDate != null && !t.dueDate!.isBefore(filter.dueDateGte!)).toList();
  }
  if (filter.dueDateLte != null) {
    result = result.where((t) => t.dueDate != null && !t.dueDate!.isAfter(filter.dueDateLte!)).toList();
  }

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

int _compareField(Task a, Task b, String field, bool ascending) {
  int result;
  switch (field) {
    case 'status':
      result = _statusRank(a.status).compareTo(_statusRank(b.status));
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

int _statusRank(String status) => status == 'active' ? 0 : 1;

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
