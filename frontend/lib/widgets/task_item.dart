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
import '../widgets/styled_snackbar.dart';
import 'task_detail_overlay.dart';
import '../utils/string_extensions.dart';

/// Task item widget for flat view with swipe actions
class TaskItem extends ConsumerWidget {
  final Task task;
  final bool isDark;
  final String? parentName;

  const TaskItem({
    super.key,
    required this.task,
    required this.isDark,
    this.parentName,
  });

  Future<void> _toggleTask(BuildContext context, WidgetRef ref) async {
    final newStatus = task.isCompleted ? 'active' : 'completed';
    final store = ref.read(taskStoreProvider.notifier);
    final paletteMap = ref.read(domainPalettesProvider);
    final domain = DomainColors.getDomain(task.category, isDark, paletteMap);

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
            ? 'Completed: ${task.sentenceTitle}'
            : 'Restored: ${task.sentenceTitle}';
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
        showStyledSnackbar(context,
          message: 'Failed to update task: $e',
          style: SnackbarStyle.error,
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
        showStyledSnackbar(context,
          message: 'Undo failed: $e',
          style: SnackbarStyle.error,
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
        showStyledSnackbar(context,
          message: 'Deleted: ${task.sentenceTitle}',
          style: SnackbarStyle.success,
        );
      }

      return true;
    } catch (e) {
      // Rollback
      store.upsertTask(task);
      if (context.mounted) {
        showStyledSnackbar(context,
          message: 'Failed to delete task: $e',
          style: SnackbarStyle.error,
        );
      }
      return false;
    }
  }

  Widget _buildBadge({
    required String text,
    required Color color,
    double backgroundAlpha = 0.2,
    FontWeight fontWeight = FontWeight.w700,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 6,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: backgroundAlpha),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: AppTypography.metadataText(
          color: color,
        ).copyWith(
          fontSize: 10,
          fontWeight: fontWeight,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paletteMap = ref.watch(domainPalettesProvider);
    final domain = DomainColors.getDomain(task.category, isDark, paletteMap);
    final isCompleted = task.isCompleted;
    final isOverdue = task.isOverdue;
    final isDueSoon = task.isDueSoon;

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
        margin: const EdgeInsets.symmetric(vertical: 2),
        color: domain.primary,
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
        margin: const EdgeInsets.symmetric(vertical: 2),
        color: AppColors.deleteAction,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.lg),
        child: const Icon(
          Icons.delete_forever,
          color: AppColors.darkBg,
          size: 32,
        ),
      ),
      child: GestureDetector(
        onTap: () => _toggleTask(context, ref),
        onLongPress: () => showTaskDetailOverlay(context, taskId: task.id),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                domain.surface,
                Color.lerp(domain.surface, domain.darkShade, 0.15)!,
                domain.surface.withValues(alpha: 0.85),
              ],
              stops: const [0.0, 0.5, 1.0],
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      task.sentenceTitle,
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (parentName != null)
                      Text(
                        parentName!.capitalize,
                        style: AppTypography.metadataText(
                          color: domain.primary.withValues(alpha: 0.4),
                        ).copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (isOverdue) ...[
                _buildBadge(text: 'Overdue', color: AppColors.overdue),
                const SizedBox(width: 4),
              ],
              if (isDueSoon) ...[
                _buildBadge(text: 'Due Soon', color: AppColors.dueSoon),
                const SizedBox(width: 4),
              ],
              if (task.priority != null)
                _buildBadge(
                  text: task.priority!.capitalize,
                  color: domain.primary.withValues(alpha: 0.8),
                  backgroundAlpha: 0.15,
                  fontWeight: FontWeight.w600,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
