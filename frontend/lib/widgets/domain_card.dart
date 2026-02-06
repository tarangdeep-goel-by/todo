import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/theme.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../config/constants.dart';
import '../models/task.dart';
import '../models/api_response.dart';
import '../providers/api_provider.dart';
import '../providers/task_store_provider.dart';
import '../services/haptic_service.dart';
import '../widgets/undo_snackbar.dart';
import 'task_detail_overlay.dart';

/// Domain card widget with focus/compressed states
class DomainCard extends ConsumerStatefulWidget {
  final DomainPalette domain;
  final List<Task> tasks;
  final bool isDark;
  final double focusProgress; // 0.0 = compressed, 1.0 = focused
  final double height;

  const DomainCard({
    super.key,
    required this.domain,
    required this.tasks,
    required this.isDark,
    required this.focusProgress,
    required this.height,
  });

  @override
  ConsumerState<DomainCard> createState() => _DomainCardState();
}

class _DomainCardState extends ConsumerState<DomainCard> {
  DomainPalette get domain => widget.domain;
  List<Task> get tasks => widget.tasks;
  double get height => widget.height;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppAnimations.cardExpand,
      curve: AppAnimations.easeOutCubic,
      width: double.infinity,
      height: height,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.cardMargin,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showFocused = constraints.maxHeight > 100;
          return showFocused
              ? _buildFocusedCard(context)
              : _buildCompressedCard(context);
        },
      ),
    );
  }

  Future<void> _toggleTask(Task task) async {
    final newStatus = task.isCompleted ? 'active' : 'completed';
    final store = ref.read(taskStoreProvider.notifier);

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
          onUndo: () => _undoToggle(task),
        );
      }
    } catch (e) {
      // Rollback
      store.upsertTask(task);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update task: $e')),
        );
      }
    }
  }

  Future<void> _undoToggle(Task original) async {
    final store = ref.read(taskStoreProvider.notifier);
    store.upsertTask(original);

    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.updateTask(
        original.id,
        UpdateTaskRequest(
          status: original.status,
          completedAt: original.isCompleted ? original.completedAt ?? DateTime.now() : null,
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

  String _formatDueDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(date.year, date.month, date.day);
    final diff = due.difference(today).inDays;
    if (diff < 0) return 'Overdue';
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff < 7) return '${diff}d';
    return '${date.day}/${date.month}';
  }

  Widget _buildTaskRow(Task task) {
    final isCompleted = task.isCompleted;
    final hasMeta = task.priority != null || task.dueDate != null;

    // Build metadata chips
    final metaParts = <Widget>[];
    if (task.priority != null) {
      metaParts.add(Text(
        task.priority!.substring(0, 1).toUpperCase() + task.priority!.substring(1),
        style: AppTypography.metadataText(
          color: domain.primary.withValues(alpha: 0.7),
        ).copyWith(fontSize: 11, fontWeight: FontWeight.w500),
      ));
    }
    if (task.priority != null && task.dueDate != null) {
      metaParts.add(Text(
        '  ·  ',
        style: AppTypography.metadataText(
          color: domain.primary.withValues(alpha: 0.4),
        ).copyWith(fontSize: 11),
      ));
    }
    if (task.dueDate != null) {
      metaParts.add(Text(
        _formatDueDate(task.dueDate!),
        style: AppTypography.metadataText(
          color: domain.primary.withValues(alpha: 0.7),
        ).copyWith(fontSize: 11, fontWeight: FontWeight.w500),
      ));
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggleTask(task),
      onLongPress: () => showTaskDetailOverlay(context, taskId: task.id),
      child: Opacity(
        opacity: isCompleted ? 0.5 : 1.0,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: domain.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 6,
          ),
          child: Row(
            children: [
              // Left accent bar
              Container(
                width: AppSpacing.leftAccentBar,
                height: hasMeta ? 32 : 20,
                decoration: BoxDecoration(
                  color: domain.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      task.title,
                      style: AppTypography.metadataText(
                        color: domain.primary,
                      ).copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        decoration: isCompleted ? TextDecoration.lineThrough : null,
                        decorationColor: domain.primary.withValues(alpha: 0.5),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (hasMeta) ...[
                      const SizedBox(height: 2),
                      Row(children: metaParts),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Focused card: full bleed, domain primary background
  Widget _buildFocusedCard(BuildContext context) {
    final activeTasks = tasks.where((t) => t.isActive).toList();
    final completedTasks = tasks.where((t) => t.isCompleted).toList();
    final displayTasks = [...activeTasks, ...completedTasks].take(5).toList();
    final taskCount = activeTasks.length;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: domain.primary,
        borderRadius: BorderRadius.circular(AppSpacing.radiusNone),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
              // Domain name and task count row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      domain.name,
                      style: AppTypography.domainTitle(
                        context,
                        color: domain.textOnPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '$taskCount ${taskCount == 1 ? 'task' : 'tasks'}',
                    style: AppTypography.metadataText(
                      color: domain.textOnPrimary.withValues(alpha: 0.8),
                    ).copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Dark inset task preview
              if (displayTasks.isNotEmpty)
                Expanded(
                  child: Container(
                    width: double.infinity,
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      color: AppColors.darkBg,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: displayTasks.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 4),
                      itemBuilder: (_, i) => _buildTaskRow(displayTasks[i]),
                    ),
                  ),
                ),
            ],
          ),
    );
  }

  /// Compressed card: surface background, left accent bar
  Widget _buildCompressedCard(BuildContext context) {
    final taskCount = tasks.where((t) => t.isActive).length;

    return Container(
      width: double.infinity,
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
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Domain name (smaller)
          Text(
            domain.name,
            style: AppTypography.ctaLabelText(color: domain.primary).copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),

          // Task count (right aligned, bolder)
          Text(
            '$taskCount ${taskCount == 1 ? 'task' : 'tasks'}',
            style: AppTypography.metadataText(
              color: domain.primary.withValues(alpha: 0.8),
            ).copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
