import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../models/task.dart';
import '../providers/mutation_provider.dart';
import '../providers/task_store_provider.dart';
import '../services/app_logger.dart';
import '../services/haptic_service.dart';
import '../services/tracker/tracker.dart';
import '../utils/string_extensions.dart';
import 'task_detail_overlay.dart';
import 'undo_snackbar.dart';


/// Shared flat task row used by Flat View and Calendar View.
///
/// Two-line layout with accent bar, swipe-to-complete/delete/restore.
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
  final _log = AppLogger.instance;

  // ── Actions ──────────────────────────────────────────────────────────

  Future<void> _toggleTask(BuildContext context) async {
    final task = widget.task;
    final newStatus = task.isCompleted ? 'active' : 'completed';
    final domain = widget.domain;

    HapticService.light();

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
          // Capture mutation & task in closure BEFORE widget disposal
          // (list re-sort after status change can dispose this row)
          final reversePayload = <String, dynamic>{
            'status': task.status,
            'completed_at': task.isCompleted
                ? (task.completedAt ?? DateTime.now()).toIso8601String()
                : null,
          };
          mutation.updateTask(task, reversePayload);
        },
      );
    }
  }

  Future<bool> _deleteTask(BuildContext context) async {
    final task = widget.task;
    final domain = widget.domain;

    HapticService.medium();

    // Offline-first: archive in store + enqueue for sync
    final mutation = ref.read(taskMutationServiceProvider);
    await mutation.archiveTask(task);

    if (context.mounted) {
      showUndoSnackbar(
        context,
        message: 'Archived: ${task.sentenceTitle}',
        domain: domain,
        onUndo: () async {
          await mutation.restoreTask(task);
        },
      );
    }

    return true;
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  Color _priorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return AppColors.priorityHigh;
      case 'medium':
        return AppColors.priorityMedium;
      case 'low':
        return AppColors.priorityLow;
      default:
        return const Color(0x66F0EBE5);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────

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

    // Subtitle text: parent name for children, category for root tasks
    final subtitleText = (widget.parentName ?? task.category).capitalize;

    // ── Row content ──

    // Row content
    Widget rowContent = GestureDetector(
      onTap: isTutorialMode
          ? null
          : () => showTaskDetailOverlay(context, taskId: task.id),
      child: Container(
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
            // Right side: date + priority (no "Done" pill)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Line 1: date with optional red dot for overdue
                if (task.dueDate != null)
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
                      color: _priorityColor(task.priority!),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );

    // Completed state: reduce opacity for entire row
    if (isCompleted) {
      rowContent = Opacity(opacity: 0.4, child: rowContent);
    }

    // Pending mutation indicator
    if (isPending) {
      rowContent = Opacity(opacity: 0.6, child: rowContent);
    }

    // If swipe actions disabled, return without Dismissible
    if (!widget.showSwipeActions) {
      return rowContent;
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
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.undo_rounded, color: domain.textOnPrimary, size: 32),
      );
      secondaryBackground = null;
    } else {
      // Active: right = complete, left = delete
      direction = DismissDirection.horizontal;
      background = Container(
        color: domain.primary,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        child:
            Icon(Icons.check_circle, color: domain.textOnPrimary, size: 32),
      );
      secondaryBackground = Container(
        color: AppColors.deleteAction,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.archive_rounded,
            color: AppColors.darkBg, size: 32),
      );
    }

    return Dismissible(
      key: Key(task.id),
      direction: direction,
      confirmDismiss: (dir) async {
        _log.debug('row.swipe', logger: 'FlatTaskRow', data: {
          'taskId': task.id, 'direction': dir.name, 'isCompleted': isCompleted,
          'isTutorial': widget.onTutorialStepComplete != null,
        });
        if (isCompleted) {
          // Left swipe on completed -> restore (mark active)
          await _toggleTask(context);
          if (widget.onTutorialStepComplete != null) {
            _log.debug('row.tutorial_step', logger: 'FlatTaskRow', data: {'step': 2});
            widget.onTutorialStepComplete!(2);
          }
          return false;
        }
        if (dir == DismissDirection.startToEnd) {
          // Right swipe on active -> complete
          await _toggleTask(context);
          if (widget.onTutorialStepComplete != null) {
            _log.debug('row.tutorial_step', logger: 'FlatTaskRow', data: {'step': 1});
            widget.onTutorialStepComplete!(1);
          }
          return false;
        } else if (dir == DismissDirection.endToStart) {
          // Left swipe on active -> archive
          await _deleteTask(context);
          if (widget.onTutorialStepComplete != null) {
            _log.debug('row.tutorial_step', logger: 'FlatTaskRow', data: {'step': 3});
            widget.onTutorialStepComplete!(3);
          }
          return false;
        }
        return false;
      },
      background: background,
      secondaryBackground: secondaryBackground,
      child: rowContent,
    );
  }
}
