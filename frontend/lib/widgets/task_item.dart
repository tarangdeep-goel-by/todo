import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/theme.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../models/task.dart';
import '../models/api_response.dart';
import '../providers/api_provider.dart';
import '../providers/task_store_provider.dart';
import '../services/haptic_service.dart';
import '../widgets/undo_snackbar.dart';
import 'task_detail_overlay.dart';

/// Task item widget for flat view with swipe actions
class TaskItem extends ConsumerWidget {
  final Task task;
  final bool isDark;

  const TaskItem({
    super.key,
    required this.task,
    required this.isDark,
  });

  /// Find the level 1 branch (top-level task under domain)
  String _getLevel1Branch(List<Task> allTasks) {
    if (task.parentId == null) return task.title;

    Task? current = task;
    Task? level1Task;
    final visited = <String>{};

    while (current != null && current.parentId != null) {
      if (visited.contains(current.id)) return task.category;
      visited.add(current.id);

      final parent = allTasks.cast<Task?>().firstWhere(
        (t) => t!.id == current!.parentId,
        orElse: () => null,
      );
      if (parent == null) break;
      if (parent.parentId == null) {
        level1Task = parent;
        break;
      }
      current = parent;
    }

    return level1Task?.title ?? task.category;
  }

  Future<void> _toggleTask(BuildContext context, WidgetRef ref) async {
    final newStatus = task.isCompleted ? 'active' : 'completed';
    final store = ref.read(taskStoreProvider.notifier);
    final domain = DomainColors.getDomain(task.category, isDark);

    HapticService.light();

    // Optimistic upsert
    final optimistic = task.copyWith(
      status: newStatus,
      completedAt: newStatus == 'completed' ? DateTime.now() : null,
    );
    store.upsertTask(optimistic);

    try {
      final apiService = ref.read(apiServiceProvider);
      final updated = await apiService.updateTask(
        task.id,
        UpdateTaskRequest(
          status: newStatus,
          completedAt: newStatus == 'completed' ? DateTime.now() : null,
          clearFields: newStatus == 'active' ? const {'completed_at'} : const {},
        ),
      );
      store.upsertTask(updated);

      if (context.mounted) {
        final message = newStatus == 'completed'
            ? 'Completed: ${task.title}'
            : 'Restored: ${task.title}';
        showUndoSnackbar(
          context,
          message: message,
          domain: domain,
          onUndo: () => _undoToggle(context, ref),
        );
      }
    } catch (e) {
      store.upsertTask(task);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update task: $e')),
        );
      }
    }
  }

  Future<void> _undoToggle(BuildContext context, WidgetRef ref) async {
    final store = ref.read(taskStoreProvider.notifier);
    store.upsertTask(task);

    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.updateTask(
        task.id,
        UpdateTaskRequest(
          status: task.status,
          completedAt: task.isCompleted ? task.completedAt ?? DateTime.now() : null,
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Undo failed: $e')),
        );
      }
    }
  }

  Future<bool> _deleteTask(BuildContext context, WidgetRef ref) async {
    final store = ref.read(taskStoreProvider.notifier);

    try {
      HapticService.medium();

      // Optimistic remove
      store.removeTask(task.id);

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
      // Rollback
      store.upsertTask(task);
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allTasks = ref.watch(allTasksProvider);
    final domain = DomainColors.getDomain(task.category, isDark);
    final level1Branch = _getLevel1Branch(allTasks);
    final isCompleted = task.isCompleted;
    final isOverdue = task.isOverdue;

    return Dismissible(
      key: Key(task.id),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          await _toggleTask(context, ref);
          return false;
        } else if (direction == DismissDirection.endToStart) {
          await _deleteTask(context, ref);
          return false;
        }
        return false;
      },
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
        onTap: () => _toggleTask(context, ref),
        onLongPress: () => showTaskDetailOverlay(context, taskId: task.id),
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
              Expanded(
                child: Text(
                  task.title,
                  style: AppTypography.metadataText(
                    color: isCompleted
                        ? domain.primary.withValues(alpha: 0.5)
                        : isOverdue
                            ? const Color(0xFFFF6B6B)
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
              if (isOverdue) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B6B).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Overdue',
                    style: AppTypography.metadataText(
                      color: const Color(0xFFFF6B6B),
                    ).copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
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
