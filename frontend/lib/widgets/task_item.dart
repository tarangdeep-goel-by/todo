import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/theme.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../models/task.dart';
import '../providers/api_provider.dart';
import '../providers/tasks_provider.dart';
import '../providers/task_filter_provider.dart';
import '../services/haptic_service.dart';
import '../services/task_toggle_service.dart';
import '../utils/task_status_utils.dart';
import 'task_detail_sheet.dart';

/// Task item widget for flat view with swipe actions
class TaskItem extends ConsumerWidget {
  final Task task;
  final bool isDark;
  final List<Task> allTasks;

  const TaskItem({
    super.key,
    required this.task,
    required this.isDark,
    required this.allTasks,
  });

  /// Find the level 1 branch (top-level task under domain)
  String _getLevel1Branch() {
    // If task has no parent, it IS the level 1 branch
    if (task.parentId == null) {
      return task.title;
    }

    // Traverse up the parent chain to find level 1
    Task? current = task;
    Task? level1Task;
    final Set<String> visited = {}; // Prevent cycles

    while (current != null && current.parentId != null) {
      // Detect cycles
      if (visited.contains(current.id)) {
        return task.category; // Fallback if cycle detected
      }
      visited.add(current.id);

      // Find parent - use sentinel value instead of returning current
      final parent = allTasks.firstWhere(
        (t) => t.id == current!.parentId,
        orElse: () => Task(
          id: '',
          userId: '',
          title: '',
          category: '',
          status: '',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          transcription: '',
        ),
      );

      // Check if parent was found
      if (parent.id.isEmpty) {
        break; // Parent not found, exit loop
      }

      // If parent has no parent, it's level 1
      if (parent.parentId == null) {
        level1Task = parent;
        break;
      }

      current = parent;
    }

    return level1Task?.title ?? task.category;
  }

  Future<bool> _deleteTask(BuildContext context, WidgetRef ref) async {
    try {
      HapticService.medium();

      final apiService = ref.read(apiServiceProvider);
      await apiService.deleteTask(task.id);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted: ${task.title}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete task: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return false;
    }
  }

  void _refreshTasks(WidgetRef ref) {
    ref.read(taskStatusOverrideProvider.notifier).state = {};
    ref.invalidate(tasksProvider);
    ref.invalidate(paginatedTasksProvider);
  }

  void _showTaskDetail(BuildContext context) {
    HapticService.medium();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TaskDetailSheet(task: task),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final domain = DomainColors.getDomain(task.category, isDark);
    final level1Branch = _getLevel1Branch();
    final isCompleted = effectiveStatus(ref, task) == 'completed';

    return Dismissible(
      key: Key(task.id),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          await toggleTaskStatus(context, ref, task);
          return false; // Don't dismiss — row stays, override handles UI
        } else if (direction == DismissDirection.endToStart) {
          await _deleteTask(context, ref);
          _refreshTasks(ref);
          return false;
        }
        return false;
      },
      onDismissed: (_) => _refreshTasks(ref),
      // Complete background (right swipe)
      background: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: domain.primary,
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(AppSpacing.radiusMd),
            bottomRight: Radius.circular(AppSpacing.radiusMd),
          ),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: AppSpacing.lg),
        child: Icon(
          Icons.check_circle,
          color: domain.textOnPrimary,
          size: 32,
        ),
      ),
      // Delete background (left swipe)
      secondaryBackground: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFE84878), // Crimson rose
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(AppSpacing.radiusMd),
            bottomRight: Radius.circular(AppSpacing.radiusMd),
          ),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.lg),
        child: const Icon(
          Icons.delete_forever,
          color: Color(0xFF0D0B09),
          size: 32,
        ),
      ),
      child: GestureDetector(
        onTap: () async {
          await toggleTaskStatus(context, ref, task);
        },
        onLongPress: () => _showTaskDetail(context),
        child: Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: domain.surface,
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(AppSpacing.radiusMd),
              bottomRight: Radius.circular(AppSpacing.radiusMd),
            ),
            border: Border(
              left: BorderSide(
                color: domain.primary,
                width: AppSpacing.leftAccentBar,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Title (left side)
              Expanded(
                child: Text(
                  task.title,
                  style: AppTypography.metadataText(
                    color: isCompleted
                        ? domain.primary.withValues(alpha: 0.5)
                        : domain.primary,
                  ).copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    decoration: isCompleted
                        ? TextDecoration.lineThrough
                        : null,
                    decorationColor: domain.primary.withValues(alpha: 0.5),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              const SizedBox(width: AppSpacing.sm),

              // Level 1 branch pill (right side)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: domain.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  level1Branch,
                  style: AppTypography.metadataText(
                    color: domain.primary,
                  ).copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
