import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../models/task.dart';
import '../providers/mutation_provider.dart';
import '../providers/task_store_provider.dart';
import '../services/haptic_service.dart';
import '../utils/string_extensions.dart';
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

    if (storeState.error != null && !storeState.hasLoadedOnce && allTasks.isEmpty) {
      return EmptyState(
        message: 'Something went wrong loading your tasks.',
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
        title: 'Timeline is clear',
        message: 'Add a due date to any task\nand it will show up here.',
        textColor: AppColors.darkText,
        icon: Icons.calendar_today,
        examples: [
          'Add dentist appointment, due Friday',
          'Schedule team review for next week',
        ],
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
      widgets.add(_buildSection('Overdue', overdue, AppColors.overdue));
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

  String _dayLabel(DateTime date) =>
      DateFormat('EEEE, MMM d').format(date);

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
                    color: AppColors.secondaryText,
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
    final paletteMap = ref.read(domainPalettesProvider);
    final domain = DomainColors.getDomain(task.category, true, paletteMap);

    HapticService.light();

    // Offline-first: optimistic update + enqueue for sync
    final optimistic = task.copyWith(
      status: newStatus,
      completedAt: newStatus == 'completed' ? DateTime.now() : null,
    );
    final payload = <String, dynamic>{'status': newStatus};
    if (newStatus == 'completed') {
      payload['completed_at'] = DateTime.now().toIso8601String();
    }

    final mutation = ref.read(taskMutationServiceProvider);
    await mutation.updateTask(optimistic, payload);

    if (mounted) {
      final message = newStatus == 'completed'
          ? 'Completed: ${task.sentenceTitle}'
          : 'Restored: ${task.sentenceTitle}';
      showUndoSnackbar(
        context,
        message: message,
        domain: domain,
        onUndo: () async {
          final undoPayload = <String, dynamic>{'status': task.status};
          if (task.isCompleted) {
            undoPayload['completed_at'] = (task.completedAt ?? DateTime.now()).toIso8601String();
          }
          await mutation.updateTask(task, undoPayload);
        },
      );
    }
  }

  Widget _buildTaskTile(Task task) {
    final paletteMap = ref.watch(domainPalettesProvider);
    final domain = DomainColors.getDomain(task.category, true, paletteMap);
    return GestureDetector(
      onTap: () => _toggleTask(task),
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
                  task.priority!.capitalize,
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
