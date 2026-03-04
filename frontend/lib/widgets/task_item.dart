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
import '../services/onboarding_service.dart';
import '../widgets/undo_snackbar.dart';
import '../widgets/styled_snackbar.dart';
import 'task_detail_overlay.dart';
import '../utils/string_extensions.dart';

/// Task item widget for flat view with swipe actions.
///
/// Swipe behavior varies by status:
/// - Active: right = complete, left = delete
/// - Completed: left only = restore
class TaskItem extends ConsumerStatefulWidget {
  final Task task;
  final bool isDark;
  final String? parentName;
  final ValueChanged<int>? onTutorialStepComplete;

  const TaskItem({
    super.key,
    required this.task,
    required this.isDark,
    this.parentName,
    this.onTutorialStepComplete,
  });

  @override
  ConsumerState<TaskItem> createState() => _TaskItemState();
}

class _TaskItemState extends ConsumerState<TaskItem> {
  bool get _isDemoTask => widget.task.id == OnboardingService.demoTaskId;

  Future<void> _toggleTask(BuildContext context) async {
    final task = widget.task;
    final newStatus = task.isCompleted ? 'active' : 'completed';
    final store = ref.read(taskStoreProvider.notifier);
    final paletteMap = ref.read(domainPalettesProvider);
    final domain =
        DomainColors.getDomain(task.category, widget.isDark, paletteMap);

    HapticService.light();

    // Demo task: just update locally, no API call
    if (_isDemoTask) {
      final optimistic = task.copyWith(
        status: newStatus,
        completedAt: newStatus == 'completed' ? DateTime.now() : null,
      );
      store.upsertTask(optimistic);
      if (context.mounted) {
        final message = newStatus == 'completed'
            ? 'Completed: ${task.sentenceTitle}'
            : 'Restored: ${task.sentenceTitle}';
        showStyledSnackbar(context,
            message: message, style: SnackbarStyle.success);
      }
      return;
    }

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
          clearFields:
              newStatus == 'active' ? const {'completed_at'} : const {},
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
          onUndo: () => _undoToggle(context),
        );
      }
    } catch (e) {
      store.upsertTask(task);
      if (context.mounted) {
        showStyledSnackbar(
          context,
          message: 'Couldn\'t update task. Check your connection.',
          style: SnackbarStyle.error,
        );
      }
    }
  }

  Future<void> _undoToggle(BuildContext context) async {
    final task = widget.task;
    final store = ref.read(taskStoreProvider.notifier);
    store.upsertTask(task);

    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.updateTask(
        task.id,
        UpdateTaskRequest(
          status: task.status,
          completedAt:
              task.isCompleted ? task.completedAt ?? DateTime.now() : null,
        ),
      );
    } catch (e) {
      if (context.mounted) {
        showStyledSnackbar(
          context,
          message: 'Couldn\'t undo. Check your connection.',
          style: SnackbarStyle.error,
        );
      }
    }
  }

  Future<bool> _deleteTask(BuildContext context) async {
    final task = widget.task;
    final store = ref.read(taskStoreProvider.notifier);

    HapticService.medium();

    // Demo task: just remove locally, no API call
    if (_isDemoTask) {
      store.removeTask(task.id);
      if (context.mounted) {
        showStyledSnackbar(context,
            message: 'Deleted: ${task.sentenceTitle}',
            style: SnackbarStyle.success);
      }
      return true;
    }

    try {
      // Optimistic remove
      store.removeTask(task.id);

      final apiService = ref.read(apiServiceProvider);
      await apiService.deleteTask(task.id);

      if (context.mounted) {
        showStyledSnackbar(
          context,
          message: 'Deleted: ${task.sentenceTitle}',
          style: SnackbarStyle.success,
        );
      }

      return true;
    } catch (e) {
      // Rollback
      store.upsertTask(task);
      if (context.mounted) {
        showStyledSnackbar(
          context,
          message: 'Couldn\'t delete task. Check your connection.',
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
  Widget build(BuildContext context) {
    final task = widget.task;
    final paletteMap = ref.watch(domainPalettesProvider);
    final domain =
        DomainColors.getDomain(task.category, widget.isDark, paletteMap);
    final isCompleted = task.isCompleted;
    final isOverdue = task.isOverdue;
    final isDueSoon = task.isDueSoon;

    // During tutorial, disable tap/long-press to prevent bypassing swipe steps
    final isTutorialMode = widget.onTutorialStepComplete != null;

    Widget taskContent = GestureDetector(
      onTap: isTutorialMode ? null : () => _toggleTask(context),
      onLongPress:
          isTutorialMode ? null : () => showTaskDetailOverlay(context, taskId: task.id),
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
                      decoration:
                          isCompleted ? TextDecoration.lineThrough : null,
                      decorationColor: domain.primary.withValues(alpha: 0.5),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.parentName != null)
                    Text(
                      widget.parentName!.capitalize,
                      style: AppTypography.metadataText(
                        color: domain.primary.withValues(alpha: 0.6),
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
    );

    // Swipe direction and background based on task status
    final DismissDirection direction;
    final Widget? background;
    final Widget? secondaryBackground;

    if (isCompleted) {
      // Completed: left swipe only → restore
      // Note: Dismissible requires background != null when secondaryBackground is set.
      // With endToStart direction only, background serves as the revealed layer.
      direction = DismissDirection.endToStart;
      background = Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        color: domain.primary,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.lg),
        child: Icon(
          Icons.undo_rounded,
          color: domain.textOnPrimary,
          size: 32,
        ),
      );
      secondaryBackground = null;
    } else {
      // Active: right = complete, left = delete
      direction = DismissDirection.horizontal;
      background = Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        color: domain.primary,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: AppSpacing.lg),
        child: Icon(
          Icons.check_circle,
          color: domain.textOnPrimary,
          size: 32,
        ),
      );
      secondaryBackground = Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        color: AppColors.deleteAction,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.lg),
        child: const Icon(
          Icons.delete_forever,
          color: AppColors.darkBg,
          size: 32,
        ),
      );
    }

    return Dismissible(
      key: Key(task.id),
      direction: direction,
      confirmDismiss: (dir) async {
        if (isCompleted) {
          // Left swipe on completed → restore
          await _toggleTask(context);
          widget.onTutorialStepComplete?.call(2);
          return false;
        }
        if (dir == DismissDirection.startToEnd) {
          // Right swipe on active → complete
          await _toggleTask(context);
          widget.onTutorialStepComplete?.call(1);
          return false;
        } else if (dir == DismissDirection.endToStart) {
          // Left swipe on active → delete
          await _deleteTask(context);
          widget.onTutorialStepComplete?.call(3);
          return false;
        }
        return false;
      },
      background: background,
      secondaryBackground: secondaryBackground,
      child: taskContent,
    );
  }
}
