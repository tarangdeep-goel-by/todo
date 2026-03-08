import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../models/task.dart';
import '../providers/sync_provider.dart';
import '../providers/task_store_provider.dart';
import 'flat_task_row.dart';
import 'empty_state.dart';
import 'loading_state.dart';

/// Calendar month grid view — select a day to see its tasks below.
class CalendarTaskView extends ConsumerStatefulWidget {
  const CalendarTaskView({super.key});

  @override
  ConsumerState<CalendarTaskView> createState() => _CalendarTaskViewState();
}

class _CalendarTaskViewState extends ConsumerState<CalendarTaskView> {
  late DateTime _displayedMonth;
  DateTime? _selectedDate;
  bool _showNoDates = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _displayedMonth = DateTime(now.year, now.month);
    _selectedDate = DateTime(now.year, now.month, now.day);
  }

  void _previousMonth() {
    setState(() {
      _displayedMonth =
          DateTime(_displayedMonth.year, _displayedMonth.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _displayedMonth =
          DateTime(_displayedMonth.year, _displayedMonth.month + 1);
    });
  }

  Widget _buildMonthHeader() {
    final label = DateFormat('MMMM yyyy').format(_displayedMonth);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: _previousMonth,
            child: const Icon(Icons.chevron_left,
                color: Color(0x66F0EBE5), size: 24),
          ),
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.darkText,
            ),
          ),
          GestureDetector(
            onTap: _nextMonth,
            child: const Icon(Icons.chevron_right,
                color: Color(0x66F0EBE5), size: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildDayHeaders() {
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: days
            .map((d) => Expanded(
                  child: Center(
                    child: Text(
                      d,
                      style: GoogleFonts.dmSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: const Color(0x40F0EBE5),
                        letterSpacing: 0.5,
                        height: 2.4,
                      ),
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildCalendarGrid(Map<DateTime, List<Task>> tasksByDay) {
    final year = _displayedMonth.year;
    final month = _displayedMonth.month;
    final firstDay = DateTime(year, month, 1);
    final lastDay = DateTime(year, month + 1, 0);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Monday = 1 in Dart, we want Monday-first grid
    final startWeekday = firstDay.weekday; // 1=Mon, 7=Sun
    final leadingBlanks = startWeekday - 1;
    final totalCells = leadingBlanks + lastDay.day;
    final rows = (totalCells / 7).ceil();
    final paletteMap = ref.watch(domainPalettesProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: List.generate(rows, (row) {
          return SizedBox(
            height: 44,
            child: Row(
              children: List.generate(7, (col) {
                final cellIndex = row * 7 + col;
                final dayNum = cellIndex - leadingBlanks + 1;

                if (dayNum < 1 || dayNum > lastDay.day) {
                  return const Expanded(child: SizedBox());
                }

                final date = DateTime(year, month, dayNum);
                final isToday = date == today;
                final isPast = date.isBefore(today);
                final isSelected =
                    _selectedDate != null && date == _selectedDate;
                final dayTasks = tasksByDay[date] ?? [];

                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedDate = date),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0x20FF9A50)
                            : isToday
                                ? const Color(0x10FF9A50)
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$dayNum',
                            style: GoogleFonts.dmSans(
                              fontSize: 13,
                              fontWeight:
                                  isToday ? FontWeight.w700 : FontWeight.w400,
                              color: isToday
                                  ? const Color(0xFFFF9A50)
                                  : isPast
                                      ? const Color(0x66F0EBE5)
                                      : AppColors.darkText,
                            ),
                          ),
                          if (dayTasks.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children:
                                  _buildDotIndicators(dayTasks, paletteMap),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          );
        }),
      ),
    );
  }

  List<Widget> _buildDotIndicators(
      List<Task> tasks, Map<String, DomainPalette> paletteMap) {
    // Get unique domain colors (max 4)
    final seen = <Color>{};
    final dots = <Widget>[];
    for (final task in tasks) {
      final domain = DomainColors.getDomain(task.category, true, paletteMap);
      if (seen.add(domain.primary) && dots.length < 4) {
        if (dots.isNotEmpty) dots.add(const SizedBox(width: 2));
        dots.add(Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            color: domain.primary,
            shape: BoxShape.circle,
          ),
        ));
      }
    }
    return dots;
  }

  Widget _buildSelectedDayTasks(
      List<Task> allActiveTasks, List<Task> undatedTasks) {
    final paletteMap = ref.watch(domainPalettesProvider);

    // Tasks for selected day
    List<Task> dayTasks = [];
    String headerLabel = '';

    if (_selectedDate != null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      dayTasks = allActiveTasks.where((t) {
        if (t.dueDate == null) return false;
        final dueDay =
            DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
        return dueDay == _selectedDate;
      }).toList();

      if (_selectedDate == today) {
        headerLabel = 'Today, ${DateFormat('MMM d').format(_selectedDate!)}';
      } else {
        headerLabel = DateFormat('EEE, MMM d').format(_selectedDate!);
      }
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics()),
      children: [
        // Selected day header
        if (_selectedDate != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              headerLabel,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFFF9A50),
              ),
            ),
          ),

        // Tasks for selected day
        if (dayTasks.isEmpty && _selectedDate != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              children: [
                Text(
                  'No tasks on this day',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: const Color(0x66F0EBE5),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap the mic or type to add one',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: const Color(0x40F0EBE5),
                  ),
                ),
              ],
            ),
          )
        else
          ...dayTasks.map((task) {
            final domain =
                DomainColors.getDomain(task.category, true, paletteMap);
            return FlatTaskRow(
              key: ValueKey(task.id),
              task: task,
              domain: domain,
            );
          }),

        // Undated tasks section
        if (undatedTasks.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildUndatedSection(undatedTasks, paletteMap),
        ],
      ],
    );
  }

  Widget _buildUndatedSection(
      List<Task> tasks, Map<String, DomainPalette> paletteMap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _showNoDates = !_showNoDates),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Text(
                  'No due date',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0x80F0EBE5),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '(${tasks.length})',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: const Color(0x66F0EBE5),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _showNoDates ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: const Color(0x80F0EBE5),
                ),
              ],
            ),
          ),
        ),
        if (_showNoDates)
          ...tasks.map((task) {
            final domain =
                DomainColors.getDomain(task.category, true, paletteMap);
            return FlatTaskRow(
              key: ValueKey(task.id),
              task: task,
              domain: domain,
            );
          }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final storeState = ref.watch(taskStoreProvider);
    final allTasks = ref.watch(allTasksProvider);

    if (storeState.isLoading && allTasks.isEmpty) {
      return const LoadingState();
    }

    if (storeState.error != null &&
        !storeState.hasLoadedOnce &&
        allTasks.isEmpty) {
      return EmptyState(
        message: 'Something went wrong loading your tasks.',
        textColor: AppColors.darkText,
        icon: Icons.error_outline,
        onRetry: () => ref.read(taskStoreProvider.notifier).fetchAll(),
      );
    }

    final activeTasks = allTasks.where((t) => t.isActive).toList();
    final undatedTasks = activeTasks.where((t) => t.dueDate == null).toList();
    final datedTasks = activeTasks.where((t) => t.dueDate != null).toList();

    if (datedTasks.isEmpty && undatedTasks.isEmpty) {
      return const EmptyState(
        title: 'Calendar is clear',
        message: 'Add a due date to any task\nand it will show up here.',
        textColor: AppColors.darkText,
        icon: Icons.calendar_today,
        examples: [
          'Add dentist appointment, due Friday',
          'Schedule team review for next week',
        ],
      );
    }

    // Build tasks-by-day map for dot indicators
    final tasksByDay = <DateTime, List<Task>>{};
    for (final task in datedTasks) {
      final day = DateTime(
          task.dueDate!.year, task.dueDate!.month, task.dueDate!.day);
      tasksByDay.putIfAbsent(day, () => []).add(task);
    }

    return Column(
      children: [
        _buildMonthHeader(),
        _buildDayHeaders(),
        _buildCalendarGrid(tasksByDay),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          height: 1,
          color: const Color(0x0FF0EBE5),
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.darkText,
            backgroundColor: AppColors.darkBg,
            onRefresh: () => ref.read(syncServiceProvider).sync(),
            child: _buildSelectedDayTasks(activeTasks, undatedTasks),
          ),
        ),
      ],
    );
  }
}
