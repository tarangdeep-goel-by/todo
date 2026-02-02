import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/tasks_provider.dart';
import '../config/theme.dart';
import '../widgets/task_item.dart';
import '../widgets/empty_state.dart';

/// Flat all-tasks view with focus scaling
class FlatTaskView extends ConsumerWidget {
  const FlatTaskView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(tasksProvider);

    return tasksAsync.when(
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
      data: (tasks) {
        // Filter only active tasks
        final activeTasks = tasks
            .where((task) => task.status == 'active')
            .toList();

        // Sort by due date (closest first), then by created date
        activeTasks.sort((a, b) {
          if (a.dueDate != null && b.dueDate != null) {
            return a.dueDate!.compareTo(b.dueDate!);
          } else if (a.dueDate != null) {
            return -1;
          } else if (b.dueDate != null) {
            return 1;
          } else {
            return b.createdAt.compareTo(a.createdAt);
          }
        });

        if (activeTasks.isEmpty) {
          return const EmptyState(
            message: 'No active tasks\nTap and hold the button below to add one',
            textColor: AppColors.darkText,
            icon: Icons.task_alt,
          );
        }

        return ListView.builder(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 120), // Space for CTA button
          itemCount: activeTasks.length,
          itemBuilder: (context, index) {
            return TaskItem(
              task: activeTasks[index],
              isDark: true, // Dark mode only
              allTasks: activeTasks, // Pass all tasks for level 1 lookup
            );
          },
        );
      },
    );
  }
}
