import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/theme.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../models/task_filter.dart';
import '../providers/task_filter_provider.dart';
import '../providers/task_store_provider.dart';
import '../services/haptic_service.dart';

class FilterSheet extends ConsumerStatefulWidget {
  const FilterSheet({super.key});

  @override
  ConsumerState<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<FilterSheet> {
  late TaskFilter _currentFilter;

  @override
  void initState() {
    super.initState();
    _currentFilter = ref.read(taskFilterProvider);
  }

  void _applyFilters() {
    HapticService.medium();
    ref.read(taskFilterProvider.notifier).state = _currentFilter;
    Navigator.pop(context);
  }

  void _clearAll() {
    HapticService.medium();
    setState(() {
      _currentFilter = TaskFilter();
    });
  }

  void _toggleFilter(String value, List<String>? Function(TaskFilter) getter, TaskFilter Function(List<String>?) updater) {
    HapticService.light();
    setState(() {
      final current = getter(_currentFilter)?.toList() ?? [];
      if (current.contains(value)) {
        current.remove(value);
      } else {
        current.add(value);
      }
      _currentFilter = updater(current.isEmpty ? null : current);
    });
  }

  void _toggleCategory(String category) => _toggleFilter(
    category, (f) => f.categories, (v) => _currentFilter.copyWith(categories: v),
  );

  void _togglePriority(String priority) => _toggleFilter(
    priority, (f) => f.priorities, (v) => _currentFilter.copyWith(priorities: v),
  );

  void _toggleStatus(String status) => _toggleFilter(
    status, (f) => f.statuses, (v) => _currentFilter.copyWith(statuses: v),
  );

  void _setDatePreset(String preset) {
    HapticService.medium();
    final now = DateTime.now();
    setState(() {
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
    });
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
                        isSelected: false,
                        onTap: () => _setDatePreset('today'),
                        color: accentColor,
                      ),
                      _buildFilterChip(
                        label: 'THIS WEEK',
                        isSelected: false,
                        onTap: () => _setDatePreset('week'),
                        color: accentColor,
                      ),
                      _buildFilterChip(
                        label: 'OVERDUE',
                        isSelected: false,
                        onTap: () => _setDatePreset('overdue'),
                        color: AppColors.overdue,
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
                      height: 48,
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
                    onTap: _applyFilters,
                    child: Container(
                      height: 48,
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
