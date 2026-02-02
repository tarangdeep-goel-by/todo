import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/task_filter_provider.dart';
import '../config/theme.dart';
import '../widgets/task_item.dart';
import '../widgets/empty_state.dart';

/// Flat all-tasks view with pagination and filtering
class FlatTaskView extends ConsumerStatefulWidget {
  const FlatTaskView({super.key});

  @override
  ConsumerState<FlatTaskView> createState() => _FlatTaskViewState();
}

class _FlatTaskViewState extends ConsumerState<FlatTaskView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      // Load more when 200px from bottom
      final paginatedState = ref.read(paginatedTasksProvider);
      paginatedState.whenData((data) {
        if (data.hasMore) {
          ref.read(paginationStateProvider.notifier).loadMore();
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tasksState = ref.watch(paginatedTasksProvider);

    return tasksState.when(
      loading: () => const Center(
        child: CircularProgressIndicator(
          color: AppColors.darkText,
        ),
      ),
      error: (error, stack) {
        return EmptyState(
          message: 'Unable to load tasks\n$error',
          textColor: AppColors.darkText,
          icon: Icons.error_outline,
        );
      },
      data: (paginatedData) {
        final tasks = paginatedData.tasks;
        final hasMore = paginatedData.hasMore;

        if (tasks.isEmpty) {
          return const EmptyState(
            message: 'No tasks found\nTap and hold the button below to add one',
            textColor: AppColors.darkText,
            icon: Icons.task_alt,
          );
        }

        return ListView.builder(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 120), // Space for CTA button
          itemCount: tasks.length + (hasMore ? 1 : 0), // +1 for loading indicator
          itemBuilder: (context, index) {
            if (index == tasks.length) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(
                    color: AppColors.darkText,
                  ),
                ),
              );
            }
            return TaskItem(
              task: tasks[index],
              isDark: true, // Dark mode only
              allTasks: tasks, // Pass all tasks for level 1 lookup
            );
          },
        );
      },
    );
  }
}
