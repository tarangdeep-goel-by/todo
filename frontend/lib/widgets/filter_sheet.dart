import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../models/task_filter.dart';
import '../providers/task_filter_provider.dart';
import '../providers/task_store_provider.dart';
import '../services/haptic_service.dart';
import '../services/tracker/tracker.dart';
import '../services/tracker/tracker_keys.dart';

class FilterSheet extends ConsumerStatefulWidget {
  const FilterSheet({super.key});

  @override
  ConsumerState<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<FilterSheet> {
  late TaskFilter _currentFilter;
  String? _activeDatePreset;

  @override
  void initState() {
    super.initState();
    _currentFilter = ref.read(taskFilterProvider);
    // Detect active date preset from initial filter
    if (_currentFilter.dueDateLte != null && _currentFilter.dueDateGte == null && _currentFilter.createdAtGte == null) {
      _activeDatePreset = 'overdue';
    } else if (_currentFilter.createdAtGte != null && _currentFilter.createdAtLte != null) {
      _activeDatePreset = 'today';
    } else if (_currentFilter.createdAtGte != null && _currentFilter.createdAtLte == null) {
      _activeDatePreset = 'week';
    } else if (_currentFilter.dueDateGte != null && _currentFilter.dueDateLte != null) {
      _activeDatePreset = 'custom';
    }
  }

  void _applyFilters() {
    HapticService.medium();
    ref.read(taskFilterProvider.notifier).state = _currentFilter;
    Tracker.instance.outcome(type: 'filter_applied', detail: _currentFilter.toString());
    Navigator.pop(context);
  }

  void _clearAll() {
    HapticService.medium();
    setState(() {
      _currentFilter = TaskFilter();
      _activeDatePreset = null;
    });
  }

  void _toggleCategory(String category) {
    HapticService.light();
    setState(() {
      final current = _currentFilter.categories?.toList() ?? [];
      if (current.contains(category)) {
        current.remove(category);
      } else {
        current.add(category);
      }
      _currentFilter = _currentFilter.copyWith(
        categories: current.isEmpty ? null : current,
      );
    });
  }

  void _togglePriority(String priority) {
    HapticService.light();
    setState(() {
      final current = _currentFilter.priorities?.toList() ?? [];
      if (current.contains(priority)) {
        current.remove(priority);
      } else {
        current.add(priority);
      }
      _currentFilter = _currentFilter.copyWith(
        priorities: current.isEmpty ? null : current,
      );
    });
  }

  void _toggleStatus(String status) {
    HapticService.light();
    setState(() {
      final current = _currentFilter.statuses?.toList() ?? [];
      if (current.contains(status)) {
        current.remove(status);
      } else {
        current.add(status);
      }
      _currentFilter = _currentFilter.copyWith(
        statuses: current.isEmpty ? null : current,
      );
    });
  }

  void _setDatePreset(String preset) {
    HapticService.medium();
    setState(() {
      // Toggle off if same preset tapped again
      if (_activeDatePreset == preset) {
        _activeDatePreset = null;
        _currentFilter = _currentFilter.copyWith(
          createdAtGte: null, createdAtLte: null,
          dueDateGte: null, dueDateLte: null,
        );
        return;
      }

      // Clear all date fields first
      _currentFilter = _currentFilter.copyWith(
        createdAtGte: null, createdAtLte: null,
        dueDateGte: null, dueDateLte: null,
      );

      final now = DateTime.now();
      switch (preset) {
        case 'today':
          _currentFilter = _currentFilter.copyWith(
            createdAtGte: DateTime(now.year, now.month, now.day),
            createdAtLte: DateTime(now.year, now.month, now.day, 23, 59, 59),
          );
          break;
        case 'week':
          final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
          _currentFilter = _currentFilter.copyWith(
            createdAtGte: DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day),
          );
          break;
        case 'overdue':
          _currentFilter = _currentFilter.copyWith(
            dueDateLte: now,
          );
          break;
      }
      _activeDatePreset = preset;
    });
  }

  Future<void> _pickCustomDateRange() async {
    HapticService.medium();
    final paletteMap = ref.read(domainPalettesProvider);
    final accentColor = paletteMap.values.isNotEmpty
        ? paletteMap.values.first.primary
        : DomainColors.palettes.first.primary;

    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 3)),
      initialDateRange: (_currentFilter.dueDateGte != null && _currentFilter.dueDateLte != null)
          ? DateTimeRange(start: _currentFilter.dueDateGte!, end: _currentFilter.dueDateLte!)
          : null,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(
              primary: accentColor,
              surface: AppColors.darkBg,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _currentFilter = _currentFilter.copyWith(
          createdAtGte: null, createdAtLte: null,
          dueDateGte: picked.start,
          dueDateLte: picked.end,
        );
        _activeDatePreset = 'custom';
      });
    }
  }

  String _formatCustomRange() {
    if (_currentFilter.dueDateGte != null && _currentFilter.dueDateLte != null) {
      final fmt = DateFormat('MMM d');
      return '${fmt.format(_currentFilter.dueDateGte!)} - ${fmt.format(_currentFilter.dueDateLte!)}';
    }
    return 'CUSTOM';
  }

  void _toggleSort(String field) {
    HapticService.medium();
    setState(() {
      final current = _currentFilter.sortOptions.toList();
      final existingIndex = current.indexWhere((s) => s.field == field);

      if (existingIndex != -1) {
        final existing = current[existingIndex];
        if (existing.ascending) {
          current[existingIndex] = SortOption(field, ascending: false);
        } else {
          current.removeAt(existingIndex);
        }
      } else {
        current.add(SortOption(field, ascending: true));
      }

      _currentFilter = _currentFilter.copyWith(sortOptions: current);
    });
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: AppTypography.metadataText(color: AppColors.darkText)
            .copyWith(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required Color color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : AppColors.darkBg,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: isSelected ? color : AppColors.darkText.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.metadataText(
            color: isSelected ? color : AppColors.darkText,
          ).copyWith(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildSortChip({
    required String label,
    required String field,
    required Color accentColor,
  }) {
    final existingIndex = _currentFilter.sortOptions.indexWhere((s) => s.field == field);
    final isSelected = existingIndex != -1;
    final isAscending = isSelected && _currentFilter.sortOptions[existingIndex].ascending;

    return GestureDetector(
      onTap: () => _toggleSort(field),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withValues(alpha: 0.2)
              : AppColors.darkBg,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: isSelected
                ? accentColor
                : AppColors.darkText.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppTypography.metadataText(
                color: isSelected ? accentColor : AppColors.darkText,
              ).copyWith(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            if (isSelected) ...[
              const SizedBox(width: 6),
              Icon(
                isAscending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 16,
                color: accentColor,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Read domain palettes from provider for consistent colors
    final paletteMap = ref.watch(domainPalettesProvider);
    final domains = paletteMap.values.toList();

    // Use first domain's color as accent, or fallback
    final accentColor = domains.isNotEmpty
        ? domains.first.primary
        : DomainColors.palettes.first.primary;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: AppColors.darkBg,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppSpacing.radiusLg),
          topRight: Radius.circular(AppSpacing.radiusLg),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: AppColors.darkText.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Filters & Sort',
                  style: AppTypography.metadataText(color: AppColors.darkText)
                      .copyWith(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                GestureDetector(
                  key: TK.clearAllButton,
                  onTap: _clearAll,
                  child: Text(
                    'Clear All',
                    style: AppTypography.metadataText(
                      color: accentColor,
                    ).copyWith(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category — dynamic from actual domains
                  _buildSectionTitle('CATEGORY'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: domains.map((domain) {
                      final cat = domain.name.toLowerCase();
                      return _buildFilterChip(
                        label: domain.name.toUpperCase(),
                        isSelected: _currentFilter.categories?.contains(cat) ?? false,
                        onTap: () => _toggleCategory(cat),
                        color: domain.primary,
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 24),

                  // Priority
                  _buildSectionTitle('PRIORITY'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildFilterChip(
                        label: 'HIGH',
                        isSelected: _currentFilter.priorities?.contains('high') ?? false,
                        onTap: () => _togglePriority('high'),
                        color: AppColors.priorityHigh,
                      ),
                      _buildFilterChip(
                        label: 'MEDIUM',
                        isSelected: _currentFilter.priorities?.contains('medium') ?? false,
                        onTap: () => _togglePriority('medium'),
                        color: AppColors.priorityMedium,
                      ),
                      _buildFilterChip(
                        label: 'LOW',
                        isSelected: _currentFilter.priorities?.contains('low') ?? false,
                        onTap: () => _togglePriority('low'),
                        color: AppColors.priorityLow,
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Status
                  _buildSectionTitle('STATUS'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildFilterChip(
                        label: 'ACTIVE',
                        isSelected: _currentFilter.statuses?.contains('active') ?? false,
                        onTap: () => _toggleStatus('active'),
                        color: accentColor,
                      ),
                      _buildFilterChip(
                        label: 'DUE SOON',
                        isSelected: _currentFilter.statuses?.contains('due_soon') ?? false,
                        onTap: () => _toggleStatus('due_soon'),
                        color: AppColors.dueSoon,
                      ),
                      _buildFilterChip(
                        label: 'OVERDUE',
                        isSelected: _currentFilter.statuses?.contains('overdue') ?? false,
                        onTap: () => _toggleStatus('overdue'),
                        color: AppColors.overdue,
                      ),
                      _buildFilterChip(
                        label: 'COMPLETED',
                        isSelected: _currentFilter.statuses?.contains('completed') ?? false,
                        onTap: () => _toggleStatus('completed'),
                        color: AppColors.completed,
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Date Presets
                  _buildSectionTitle('DATE RANGE'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildFilterChip(
                        label: 'TODAY',
                        isSelected: _activeDatePreset == 'today',
                        onTap: () => _setDatePreset('today'),
                        color: accentColor,
                      ),
                      _buildFilterChip(
                        label: 'THIS WEEK',
                        isSelected: _activeDatePreset == 'week',
                        onTap: () => _setDatePreset('week'),
                        color: accentColor,
                      ),
                      _buildFilterChip(
                        label: 'OVERDUE',
                        isSelected: _activeDatePreset == 'overdue',
                        onTap: () => _setDatePreset('overdue'),
                        color: AppColors.overdue,
                      ),
                      _buildFilterChip(
                        label: _activeDatePreset == 'custom' ? _formatCustomRange() : 'CUSTOM',
                        isSelected: _activeDatePreset == 'custom',
                        onTap: () => _pickCustomDateRange(),
                        color: accentColor,
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Sort
                  _buildSectionTitle('SORT BY'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildSortChip(label: 'Priority', field: 'priority', accentColor: accentColor),
                      _buildSortChip(label: 'Due Date', field: 'due_date', accentColor: accentColor),
                      _buildSortChip(label: 'Created', field: 'created_at', accentColor: accentColor),
                      _buildSortChip(label: 'Title', field: 'title', accentColor: accentColor),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Action Buttons
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: AppColors.darkText.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticService.light();
                      Navigator.pop(context);
                    },
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 48),
                      decoration: BoxDecoration(
                        color: AppColors.darkBg,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                        border: Border.all(
                          color: AppColors.darkText.withValues(alpha: 0.3),
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'Cancel',
                          style: AppTypography.metadataText(color: AppColors.darkText)
                              .copyWith(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    key: TK.applyFiltersButton,
                    onTap: _applyFilters,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 48),
                      decoration: BoxDecoration(
                        color: accentColor,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                        boxShadow: [
                          BoxShadow(
                            color: accentColor.withValues(alpha: 0.2),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          'Apply Filters',
                          style: AppTypography.metadataText(
                            color: AppColors.darkBg,
                          ).copyWith(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
