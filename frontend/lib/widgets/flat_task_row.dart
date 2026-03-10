import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../config/spacing.dart';
import '../models/task.dart';
import '../providers/api_provider.dart';
import '../providers/mutation_provider.dart';
import '../providers/task_store_provider.dart';
import '../services/haptic_service.dart';
import '../services/onboarding_service.dart';
import '../utils/string_extensions.dart';
import 'task_detail_overlay.dart';
import 'undo_snackbar.dart';
import 'styled_snackbar.dart';
import '../services/tracker/tracker.dart';

/// Flat task row widget for the new Paper design style.
///
/// Used by both Flat View and Calendar View. Clean flat rows with accent bar,
/// no gradient backgrounds. Swipe behavior:
/// - Active: right swipe = complete, left swipe = delete/archive
/// - Completed: left swipe only = restore
class FlatTaskRow extends ConsumerStatefulWidget {
  final Task task;
  final DomainPalette domain;
  final String? parentName;
  final ValueChanged<int>? onTutorialStepComplete;
  final bool showSwipeActions;
  final bool detailOnTap;

  const FlatTaskRow({
    super.key,
    required this.task,
    required this.domain,
    this.parentName,
    this.onTutorialStepComplete,
    this.showSwipeActions = true,
    this.detailOnTap = false,
  });

  @override
  ConsumerState<FlatTaskRow> createState() => _FlatTaskRowState();
}

class _FlatTaskRowState extends ConsumerState<FlatTaskRow> {
  bool get _isDemoTask => widget.task.id == OnboardingService.demoTaskId;

  Future<void> _toggleTask(BuildContext context) async {
    final task = widget.task;
    final newStatus = task.isCompleted ? 'active' : 'completed';
    final store = ref.read(taskStoreProvider.notifier);
    final domain = widget.domain;

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

    if (newStatus == 'completed') {
      Tracker.instance
          .outcome(type: 'task_completed', method: 'toggle', category: task.category);
    }

    // Offline-first: optimistic update + enqueue for sync
    final optimistic = task.copyWith(
      status: newStatus,
      completedAt: newStatus == 'completed' ? DateTime.now() : null,
    );
    final payload = <String, dynamic>{
      'status': newStatus,
    };
    if (newStatus == 'completed') {
      payload['completed_at'] = DateTime.now().toIso8601String();
    }

    final mutation = ref.read(taskMutationServiceProvider);
    await mutation.updateTask(optimistic, payload);

    if (context.mounted) {
      final message = newStatus == 'completed'
          ? 'Completed: ${task.sentenceTitle}'
          : 'Restored: ${task.sentenceTitle}';
      showUndoSnackbar(
        context,
        message: message,
        domain: domain,
        onUndo: () {
          // Capture mutation & task before widget disposal (list re-sort disposes old row)
          final reversePayload = <String, dynamic>{'status': task.status};
          if (task.isCompleted) {
            reversePayload['completed_at'] =
                (task.completedAt ?? DateTime.now()).toIso8601String();
          }
          mutation.updateTask(task, reversePayload);
        },
      );
    }
  }

  Future<bool> _deleteTask(BuildContext context) async {
    final task = widget.task;
    final store = ref.read(taskStoreProvider.notifier);
    final domain = widget.domain;

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

    // Offline-first: remove from store + enqueue delete for sync
    final mutation = ref.read(taskMutationServiceProvider);
    final apiService = ref.read(apiServiceProvider);
    await mutation.deleteTask(task);

    if (context.mounted) {
      showUndoSnackbar(
        context,
        message: 'Archived: ${task.sentenceTitle}',
        domain: domain,
        onUndo: () async {
          // apiService captured before widget disposal (delete removes row from list)
          try {
            final restoredTask = await apiService.restoreTask(task.id);
            store.upsertTask(restoredTask);
          } catch (_) {
            if (context.mounted) {
              showStyledSnackbar(
                context,
                message: 'Couldn\'t restore task. Check your connection.',
                style: SnackbarStyle.error,
              );
            }
          }
        },
      );
    }

    return true;
  }

  Widget _buildStatusBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        text,
        style: GoogleFonts.dmSans(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final domain = widget.domain;
    final isCompleted = task.isCompleted;
    final isOverdue = task.isOverdue;
    final isDueSoon = task.isDueSoon;
    final isPending =
        ref.watch(taskStoreProvider).pendingMutations.contains(task.id);

    // During tutorial, disable tap/long-press to prevent bypassing swipe steps
    final isTutorialMode = widget.onTutorialStepComplete != null;

    // Left side line 2: domain name for root tasks, L1 parent for child tasks
    final String subtitleText = (widget.parentName ?? task.category).capitalize;

    // Row content
    Widget rowContent = Container(
      decoration: BoxDecoration(
        // Subtle red tint for overdue rows
        color: isOverdue
            ? AppColors.overdue.withValues(alpha: 0.05)
            : Colors.transparent,
        border: const Border(
          bottom: BorderSide(
            color: Color(0x0FF0EBE5),
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Accent bar
          Container(
            width: 4,
            height: 36,
            decoration: BoxDecoration(
              color: domain.primary,
              borderRadius: const BorderRadius.all(Radius.circular(2)),
            ),
          ),
          const SizedBox(width: 10),
          // Left side: title + subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  task.sentenceTitle,
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                    color: AppColors.darkText,
                    decoration:
                        isCompleted ? TextDecoration.lineThrough : null,
                    decorationColor:
                        isCompleted ? AppColors.darkText.withValues(alpha: 0.5) : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitleText,
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: domain.primary.withValues(alpha: 0.5),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Right side: line 1 (date or status pill) + line 2 (priority)
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Line 1: date with optional red dot for overdue
              if (isCompleted)
                _buildStatusBadge('Done', AppColors.completed)
              else if (task.dueDate != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isOverdue) ...[
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.overdue,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      DateFormat('MMM d').format(task.dueDate!),
                      style: GoogleFonts.dmSans(
                        fontSize: 10,
                        color: isOverdue
                            ? AppColors.overdue
                            : isDueSoon
                                ? AppColors.dueSoon
                                : const Color(0x66F0EBE5),
                      ),
                    ),
                  ],
                ),
              // Line 2: priority (semantic colors)
              if (task.priority != null) ...[
                const SizedBox(height: 4),
                Text(
                  task.priority!.capitalize,
                  style: GoogleFonts.dmSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: switch (task.priority!.toLowerCase()) {
                      'high' => AppColors.priorityHigh,
                      'medium' => AppColors.priorityMedium,
                      'low' => AppColors.priorityLow,
                      _ => const Color(0x66F0EBE5),
                    },
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );

    // Completed state: reduce opacity for entire row
    if (isCompleted) {
      rowContent = Opacity(opacity: 0.4, child: rowContent);
    }

    // Wrap with gesture detector
    Widget taskContent = GestureDetector(
      onTap: isTutorialMode
          ? null
          : widget.detailOnTap
              ? () => showTaskDetailOverlay(context, taskId: task.id)
              : () => _toggleTask(context),
      onLongPress: isTutorialMode
          ? null
          : () => showTaskDetailOverlay(context, taskId: task.id),
      child: rowContent,
    );

    // Pending mutation indicator
    if (isPending) {
      taskContent = Opacity(opacity: 0.6, child: taskContent);
    }

    // If swipe actions disabled, return without Dismissible
    if (!widget.showSwipeActions) {
      return taskContent;
    }

    // Swipe direction and background based on task status
    final DismissDirection direction;
    final Widget? background;
    final Widget? secondaryBackground;

    if (isCompleted) {
      // Completed: left swipe only -> restore
      direction = DismissDirection.endToStart;
      background = Container(
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
        color: AppColors.deleteAction,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.lg),
        child: const Icon(
          Icons.archive_rounded,
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
          // Left swipe on completed -> restore
          await _toggleTask(context);
          widget.onTutorialStepComplete?.call(2);
          return false;
        }
        if (dir == DismissDirection.startToEnd) {
          // Right swipe on active -> complete
          await _toggleTask(context);
          widget.onTutorialStepComplete?.call(1);
          return false;
        } else if (dir == DismissDirection.endToStart) {
          // Left swipe on active -> delete
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
