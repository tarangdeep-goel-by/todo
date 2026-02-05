import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/task_filter.dart';
import '../models/task.dart';
import '../config/constants.dart';
import 'api_provider.dart';

// Current filter state
final taskFilterProvider = StateProvider<TaskFilter>((ref) => const TaskFilter());

// Pagination state (offset/limit tracking only)
class PaginationState {
  final int limit;
  final int offset;
  final bool isLoadingMore;

  PaginationState({
    this.limit = 50,
    this.offset = 0,
    this.isLoadingMore = false,
  });

  PaginationState copyWith({
    int? limit,
    int? offset,
    bool? isLoadingMore,
  }) {
    return PaginationState(
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

class PaginationNotifier extends StateNotifier<PaginationState> {
  PaginationNotifier() : super(PaginationState());

  void loadMore() {
    state = state.copyWith(
      offset: state.offset + state.limit,
      isLoadingMore: true,
    );
  }

  void reset() {
    state = PaginationState();
  }
}

final paginationStateProvider = StateNotifierProvider<PaginationNotifier, PaginationState>(
  (ref) => PaginationNotifier(),
);

// Accumulated tasks storage — read (not watched) by paginatedTasksProvider
// to append pages without causing rebuild loops
final _accumulatedTasksProvider = StateProvider<List<Task>>((ref) => []);

/// Optimistic status overrides: taskId -> overridden status
final taskStatusOverrideProvider = StateProvider<Map<String, String>>((ref) => {});

/// Update a single task's status in the accumulated list (no refetch)
final updateAccumulatedTaskStatusProvider = Provider<void Function(String, String)>((ref) {
  return (String taskId, String newStatus) {
    final current = ref.read(_accumulatedTasksProvider);
    final updated = current.map((t) => t.id == taskId
        ? t.copyWith(
            status: newStatus,
            completedAt: newStatus == 'completed' ? DateTime.now() : null,
          )
        : t).toList();
    ref.read(_accumulatedTasksProvider.notifier).state = updated;
  };
});

// Paginated tasks with filters
class PaginatedTasksState {
  final List<Task> tasks;
  final bool hasMore;
  final int totalCount;

  PaginatedTasksState({
    required this.tasks,
    required this.hasMore,
    required this.totalCount,
  });
}

final paginatedTasksProvider = FutureProvider<PaginatedTasksState>((ref) async {
  final apiService = ref.watch(apiServiceProvider);
  final filter = ref.watch(taskFilterProvider);
  final pagination = ref.watch(paginationStateProvider);

  final response = await apiService.getTasksAdvanced(
    userId: AppConstants.defaultUserId,
    category: filter.categories?.join(','),
    priority: filter.priorities?.join(','),
    status: filter.statuses?.join(','),
    parentId: filter.parentId,
    tags: filter.tags?.join(','),
    createdAtGte: filter.createdAtGte,
    createdAtLte: filter.createdAtLte,
    dueDateGte: filter.dueDateGte,
    dueDateLte: filter.dueDateLte,
    sort: filter.sortOptions.isEmpty
        ? null
        : filter.sortOptions.map((s) => s.toQueryString()).join(','),
    limit: pagination.limit,
    offset: pagination.offset,
  );

  // Accumulate tasks for load-more, or replace for fresh loads
  final List<Task> allTasks;
  if (pagination.isLoadingMore) {
    final accumulated = ref.read(_accumulatedTasksProvider);
    allTasks = [...accumulated, ...response.tasks];
  } else {
    allTasks = response.tasks;
  }

  // Store for next loadMore (ref.read — won't trigger rebuild)
  ref.read(_accumulatedTasksProvider.notifier).state = allTasks;

  return PaginatedTasksState(
    tasks: allTasks,
    hasMore: response.hasMore,
    totalCount: response.totalCount,
  );
});
