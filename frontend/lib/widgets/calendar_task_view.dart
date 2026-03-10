import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../models/task.dart';
import '../providers/task_store_provider.dart';
import '../providers/sync_provider.dart';
import 'flat_task_row.dart';
import 'empty_state.dart';
import 'loading_state.dart';

/// Calendar month-grid view — dot indicators per day, task list for selected day.
class CalendarTaskView extends ConsumerStatefulWidget {
  const CalendarTaskView({super.key});

  @override
  ConsumerState<CalendarTaskView> createState() => _CalendarTaskViewState();
}

class _CalendarTaskViewState extends ConsumerState<CalendarTaskView> {
  late DateTime _displayedMonth;
  late DateTime _selectedDate;
  bool _showNoDates = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _displayedMonth = DateTime(now.year, now.month);
    _selectedDate = DateTime(now.year, now.month, now.day);
  }

  // ── Grid helpers ────────────────────────────────────────────────────

  int _daysInMonth(DateTime month) {
    return DateTime(month.year, month.month + 1, 0).day;
  }

  int _firstWeekdayOffset(DateTime month) {
    // Monday = 0, Sunday = 6
    return DateTime(month.year, month.month, 1).weekday - 1;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return _isSameDay(date, DateTime(now.year, now.month, now.day));
  }

  bool _isPast(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return date.isBefore(today);
  }

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final storeState = ref.watch(taskStoreProvider);
    final allTasks = ref.watch(allTasksProvider);
    final paletteMap = ref.watch(domainPalettesProvider);

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

    // Filter: only active tasks
    final activeTasks =
        allTasks.where((t) => t.status == 'active').toList();

    // Split: dated vs undated
    final datedTasks = activeTasks.where((t) => t.dueDate != null).toList();
    final undatedTasks = activeTasks.where((t) => t.dueDate == null).toList();

    // Build tasks-per-day map for dot indicators
    final Map<String, List<Task>> tasksByDay = {};
    for (final t in datedTasks) {
      final key = DateFormat('yyyy-MM-dd').format(t.dueDate!);
      tasksByDay.putIfAbsent(key, () => []).add(t);
    }

    // Tasks for selected day
    final selectedKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final selectedDayTasks = tasksByDay[selectedKey] ?? [];

    return RefreshIndicator(
      color: AppColors.darkText,
      backgroundColor: AppColors.darkBg,
      onRefresh: () => ref.read(syncServiceProvider).sync(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Month header ──
            _buildMonthHeader(),

            // ── Day-of-week headers ──
            _buildDayOfWeekHeaders(),

            // ── Calendar grid ──
            _buildCalendarGrid(tasksByDay, paletteMap),

            // ── Divider ──
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                height: 1,
                color: const Color(0x0FF0EBE5),
              ),
            ),

            // ── Selected day header ──
            _buildSelectedDayHeader(),

            // ── Task list for selected day ──
            if (selectedDayTasks.isEmpty)
              _buildEmptyDayState()
            else
              ...selectedDayTasks.map((task) {
                final domain =
                    DomainColors.getDomain(task.category, true, paletteMap);
                return FlatTaskRow(task: task, domain: domain);
              }),

            // ── Collapsible "No Date" section ──
            if (undatedTasks.isNotEmpty)
              _buildNoDatesSection(undatedTasks, paletteMap),

            const SizedBox(height: 120),
          ],
        ),
      ),
    );
  }

  // ── Month header ──────────────────────────────────────────────────

  Widget _buildMonthHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(
            DateFormat('MMMM yyyy').format(_displayedMonth),
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.darkText,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () {
              setState(() {
                final prev = DateTime(
                  _displayedMonth.year,
                  _displayedMonth.month - 1,
                );
                _displayedMonth = prev;
                // Keep selected day in the new month, clamped to last day
                final day = _selectedDate.day > _daysInMonth(prev)
                    ? _daysInMonth(prev)
                    : _selectedDate.day;
                _selectedDate = DateTime(prev.year, prev.month, day);
              });
            },
            child: const Icon(
              Icons.chevron_left,
              size: 20,
              color: Color(0x66F0EBE5),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              setState(() {
                final next = DateTime(
                  _displayedMonth.year,
                  _displayedMonth.month + 1,
                );
                _displayedMonth = next;
                final day = _selectedDate.day > _daysInMonth(next)
                    ? _daysInMonth(next)
                    : _selectedDate.day;
                _selectedDate = DateTime(next.year, next.month, day);
              });
            },
            child: const Icon(
              Icons.chevron_right,
              size: 20,
              color: Color(0x66F0EBE5),
            ),
          ),
        ],
      ),
    );
  }

  // ── Day-of-week headers ───────────────────────────────────────────

  Widget _buildDayOfWeekHeaders() {
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 4),
      child: Row(
        children: days
            .map(
              (d) => Expanded(
                child: Center(
                  child: Text(
                    d,
                    style: GoogleFonts.dmSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: const Color(0x40F0EBE5),
                      letterSpacing: 0.5,
                      height: 24 / 10,
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  // ── Calendar grid ─────────────────────────────────────────────────

  Widget _buildCalendarGrid(
    Map<String, List<Task>> tasksByDay,
    Map<String, DomainPalette> paletteMap,
  ) {
    final daysInMonth = _daysInMonth(_displayedMonth);
    final offset = _firstWeekdayOffset(_displayedMonth);
    final totalCells = offset + daysInMonth;
    final rows = (totalCells / 7).ceil();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: List.generate(rows, (row) {
          return Row(
            children: List.generate(7, (col) {
              final index = row * 7 + col;
              if (index < offset || index >= offset + daysInMonth) {
                return const Expanded(
                  child: SizedBox(height: 44),
                );
              }

              final day = index - offset + 1;
              final date = DateTime(
                _displayedMonth.year,
                _displayedMonth.month,
                day,
              );
              final key = DateFormat('yyyy-MM-dd').format(date);
              final dayTasks = tasksByDay[key] ?? [];

              return Expanded(
                child: _buildDayCell(date, day, dayTasks, paletteMap),
              );
            }),
          );
        }),
      ),
    );
  }

  Widget _buildDayCell(
    DateTime date,
    int day,
    List<Task> dayTasks,
    Map<String, DomainPalette> paletteMap,
  ) {
    final isSelected = _isSameDay(date, _selectedDate);
    final today = _isToday(date);
    final past = _isPast(date) && !today;

    // Day number color
    Color dayColor;
    FontWeight dayWeight = FontWeight.normal;
    if (today) {
      dayColor = const Color(0xFFFF9A50);
      dayWeight = FontWeight.w700;
    } else if (past) {
      dayColor = const Color(0x66F0EBE5);
    } else {
      dayColor = const Color(0xFFF0EBE5);
    }

    // Background
    BoxDecoration? bgDecoration;
    if (today) {
      bgDecoration = BoxDecoration(
        color: const Color(0x20FF9A50),
        borderRadius: BorderRadius.circular(10),
      );
    } else if (isSelected) {
      bgDecoration = BoxDecoration(
        color: const Color(0x15F0EBE5),
        borderRadius: BorderRadius.circular(10),
      );
    }

    // Dot colors (max 3)
    final dotColors = <Color>[];
    final seen = <String>{};
    for (final t in dayTasks) {
      if (dotColors.length >= 3) break;
      final palette =
          DomainColors.getDomain(t.category, true, paletteMap);
      final colorKey = palette.primary.toARGB32().toString();
      if (!seen.contains(colorKey)) {
        seen.add(colorKey);
        dotColors.add(palette.primary);
      }
    }

    return GestureDetector(
      onTap: () => setState(() => _selectedDate = date),
      child: Container(
        height: 44,
        decoration: bgDecoration,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$day',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: dayWeight,
                color: dayColor,
              ),
            ),
            if (dotColors.isNotEmpty) ...[
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: dotColors.map((c) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Selected day header ───────────────────────────────────────────

  Widget _buildSelectedDayHeader() {
    final today = _isToday(_selectedDate);
    final String label;
    final Color color;

    if (today) {
      label = 'Today, ${DateFormat('MMM d').format(_selectedDate)}';
      color = const Color(0xFFFF9A50);
    } else {
      label = DateFormat('EEE, MMM d').format(_selectedDate);
      color = AppColors.darkText;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  // ── Empty day state ───────────────────────────────────────────────

  Widget _buildEmptyDayState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          children: [
            Text(
              'No tasks on this day',
              style: GoogleFonts.dmSans(
                fontSize: 14,
                color: AppColors.secondaryText,
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
      ),
    );
  }

  // ── No-date collapsible section ───────────────────────────────────

  Widget _buildNoDatesSection(
    List<Task> undatedTasks,
    Map<String, DomainPalette> paletteMap,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Divider before section
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Container(
            height: 1,
            color: const Color(0x0FF0EBE5),
          ),
        ),
        GestureDetector(
          onTap: () => setState(() => _showNoDates = !_showNoDates),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  'No due date',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: const Color(0x66F0EBE5),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${undatedTasks.length}',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: const Color(0x40F0EBE5),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _showNoDates ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: const Color(0x66F0EBE5),
                ),
              ],
            ),
          ),
        ),
        if (_showNoDates)
          ...undatedTasks.map((task) {
            final domain =
                DomainColors.getDomain(task.category, true, paletteMap);
            return FlatTaskRow(task: task, domain: domain);
          }),
      ],
    );
  }
}
