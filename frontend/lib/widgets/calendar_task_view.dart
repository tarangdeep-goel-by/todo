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
import 'task_detail_overlay.dart';
import 'empty_state.dart';
import 'loading_state.dart';
import 'undo_snackbar.dart';

/// Calendar timeline view — tasks grouped by due date sections.
class CalendarTaskView extends ConsumerStatefulWidget {
  const CalendarTaskView({super.key});

  @override
  ConsumerState<CalendarTaskView> createState() => _CalendarTaskViewState();
}

class _CalendarTaskViewState extends ConsumerState<CalendarTaskView> {
  bool _showNoDates = false;

  @override
  Widget build(BuildContext context) {
    final storeState = ref.watch(taskStoreProvider);
    final allTasks = ref.watch(allTasksProvider);

    if (storeState.isLoading && allTasks.isEmpty) {
      return const LoadingState();
    }

    if (storeState.error != null && allTasks.isEmpty) {
      return EmptyState(
        message: 'Unable to load tasks\n${storeState.error}',
        textColor: AppColors.darkText,
        icon: Icons.error_outline,
        onRetry: () => ref.read(taskStoreProvider.notifier).fetchAll(),
      );
    }

    // Only show active/overdue/due_soon tasks
    final activeTasks = allTasks.where((t) => t.isActive).toList();
    final datedTasks = activeTasks.where((t) => t.dueDate != null).toList()
      ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
    final undatedTasks = activeTasks.where((t) => t.dueDate == null).toList();

    if (datedTasks.isEmpty && undatedTasks.isEmpty) {
      return const EmptyState(
        message: 'No active tasks\nTap the button below to add one',
        textColor: AppColors.darkText,
        icon: Icons.calendar_today,
      );
    }

    final sections = _buildSections(datedTasks, undatedTasks);

    return RefreshIndicator(
      color: AppColors.darkText,
      backgroundColor: AppColors.darkBg,
      onRefresh: () => ref.read(taskStoreProvider.notifier).fetchAll(),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.only(bottom: 120),
        itemCount: sections.length,
        itemBuilder: (context, index) => sections[index],
      ),
    );
  }

  List<Widget> _buildSections(List<Task> datedTasks, List<Task> undatedTasks) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final endOf7Days = today.add(const Duration(days: 7));

    // Partition into sections
    final overdue = <Task>[];
    final todayTasks = <Task>[];
    final tomorrowTasks = <Task>[];
    final next7DayTasks = <Task>[]; // days 2-6
    final laterTasks = <Task>[];

    for (final t in datedTasks) {
      final dueDay = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
      if (dueDay.isBefore(today)) {
        overdue.add(t);
      } else if (dueDay == today) {
        todayTasks.add(t);
      } else if (dueDay == tomorrow) {
        tomorrowTasks.add(t);
      } else if (dueDay.isBefore(endOf7Days)) {
        next7DayTasks.add(t);
      } else {
        laterTasks.add(t);
      }
    }

    final widgets = <Widget>[];

    if (overdue.isNotEmpty) {
      widgets.add(_buildSection('Overdue', overdue, const Color(0xFFFF6B6B)));
    }
    if (todayTasks.isNotEmpty) {
      widgets.add(_buildSection('Today', todayTasks, AppColors.darkText));
    }
    if (tomorrowTasks.isNotEmpty) {
      widgets.add(_buildSection('Tomorrow', tomorrowTasks, AppColors.darkText));
    }
    if (next7DayTasks.isNotEmpty) {
      // Group by individual day
      final byDay = <DateTime, List<Task>>{};
      for (final t in next7DayTasks) {
        final day = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
        byDay.putIfAbsent(day, () => []).add(t);
      }
      final sortedDays = byDay.keys.toList()..sort();
      for (final day in sortedDays) {
        final label = _dayLabel(day);
        widgets.add(_buildSection(label, byDay[day]!, AppColors.darkText));
      }
    }
    if (laterTasks.isNotEmpty) {
      widgets.add(_buildSection('Later', laterTasks, AppColors.darkText.withValues(alpha: 0.7)));
    }
    if (undatedTasks.isNotEmpty) {
      widgets.add(_buildCollapsibleSection('No Date', undatedTasks));
    }

    return widgets;
  }

  String _dayLabel(DateTime date) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${days[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
  }

  Widget _buildSection(String title, List<Task> tasks, Color headerColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xs),
          child: Text(
            title,
            style: AppTypography.metadataText(color: headerColor).copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        ...tasks.map((t) => _buildTaskTile(t)),
      ],
    );
  }

  Widget _buildCollapsibleSection(String title, List<Task> tasks) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _showNoDates = !_showNoDates),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xs),
            child: Row(
              children: [
                Text(
                  title,
                  style: AppTypography.metadataText(
                    color: AppColors.darkText.withValues(alpha: 0.5),
                  ).copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '(${tasks.length})',
                  style: AppTypography.metadataText(
                    color: AppColors.darkText.withValues(alpha: 0.4),
                  ).copyWith(fontSize: 12),
                ),
                const SizedBox(width: 4),
                Icon(
                  _showNoDates ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: AppColors.darkText.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
        if (_showNoDates) ...tasks.map((t) => _buildTaskTile(t)),
      ],
    );
  }

  Future<void> _toggleTask(Task task) async {
    final newStatus = task.isCompleted ? 'active' : 'completed';
    final store = ref.read(taskStoreProvider.notifier);
    final paletteMap = ref.read(domainPalettesProvider);
    final domain = DomainColors.getDomain(task.category, true, paletteMap);

    HapticService.light();

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

      if (mounted) {
        final message = newStatus == 'completed'
            ? 'Completed: ${task.sentenceTitle}'
            : 'Restored: ${task.sentenceTitle}';
        showUndoSnackbar(
          context,
          message: message,
          domain: domain,
          onUndo: () async {
            store.upsertTask(task);
            try {
              await apiService.updateTask(
                task.id,
                UpdateTaskRequest(
                  status: task.status,
                  completedAt: task.isCompleted ? task.completedAt ?? DateTime.now() : null,
                ),
              );
            } catch (_) {}
          },
        );
      }
    } catch (e) {
      store.upsertTask(task);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update task: $e')),
        );
      }
    }
  }

  Widget _buildTaskTile(Task task) {
    final paletteMap = ref.watch(domainPalettesProvider);
    final domain = DomainColors.getDomain(task.category, true, paletteMap);
    return GestureDetector(
      onTap: () => _toggleTask(task),
      onLongPress: () => showTaskDetailOverlay(context, taskId: task.id),
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 3,
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
          children: [
            Expanded(
              child: Text(
                task.sentenceTitle,
                style: AppTypography.metadataText(
                  color: domain.primary,
                ).copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // Priority pill
            if (task.priority != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: domain.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  task.priority!.substring(0, 1).toUpperCase() + task.priority!.substring(1),
                  style: AppTypography.metadataText(
                    color: domain.primary.withValues(alpha: 0.8),
                  ).copyWith(fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
