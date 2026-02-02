import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/theme.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../models/task_filter.dart';
import '../providers/task_filter_provider.dart';
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
    ref.read(paginationStateProvider.notifier).reset();
    Navigator.pop(context);
  }

  void _clearAll() {
    HapticService.medium();
    setState(() {
      _currentFilter = TaskFilter();
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
          // Toggle to descending
          current[existingIndex] = SortOption(field, ascending: false);
        } else {
          // Remove
          current.removeAt(existingIndex);
        }
      } else {
        // Add ascending
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
              ? DomainColors.workDark.primary.withValues(alpha: 0.2)
              : AppColors.darkBg,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: isSelected
                ? DomainColors.workDark.primary
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
                color: isSelected ? DomainColors.workDark.primary : AppColors.darkText,
              ).copyWith(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            if (isSelected) ...[
              const SizedBox(width: 6),
              Icon(
                isAscending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 16,
                color: DomainColors.workDark.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                      color: DomainColors.projectsDark.primary,
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
                  // Category
                  _buildSectionTitle('CATEGORY'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildFilterChip(
                        label: 'WORK',
                        isSelected: _currentFilter.categories?.contains('work') ?? false,
                        onTap: () => _toggleCategory('work'),
                        color: DomainColors.workDark.primary,
                      ),
                      _buildFilterChip(
                        label: 'PERSONAL',
                        isSelected: _currentFilter.categories?.contains('personal') ?? false,
                        onTap: () => _toggleCategory('personal'),
                        color: DomainColors.personalDark.primary,
                      ),
                      _buildFilterChip(
                        label: 'PROJECTS',
                        isSelected: _currentFilter.categories?.contains('projects') ?? false,
                        onTap: () => _toggleCategory('projects'),
                        color: DomainColors.projectsDark.primary,
                      ),
                      _buildFilterChip(
                        label: 'LEARNING',
                        isSelected: _currentFilter.categories?.contains('learning') ?? false,
                        onTap: () => _toggleCategory('learning'),
                        color: DomainColors.learningDark.primary,
                      ),
                    ],
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
                        color: const Color(0xFFFF6B6B),
                      ),
                      _buildFilterChip(
                        label: 'MEDIUM',
                        isSelected: _currentFilter.priorities?.contains('medium') ?? false,
                        onTap: () => _togglePriority('medium'),
                        color: const Color(0xFFFFA726),
                      ),
                      _buildFilterChip(
                        label: 'LOW',
                        isSelected: _currentFilter.priorities?.contains('low') ?? false,
                        onTap: () => _togglePriority('low'),
                        color: const Color(0xFF66BB6A),
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
                        color: DomainColors.workDark.primary,
                      ),
                      _buildFilterChip(
                        label: 'COMPLETED',
                        isSelected: _currentFilter.statuses?.contains('completed') ?? false,
                        onTap: () => _toggleStatus('completed'),
                        color: const Color(0xFF66BB6A),
                      ),
                      _buildFilterChip(
                        label: 'ARCHIVED',
                        isSelected: _currentFilter.statuses?.contains('archived') ?? false,
                        onTap: () => _toggleStatus('archived'),
                        color: AppColors.darkText,
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
                        color: DomainColors.projectsDark.primary,
                      ),
                      _buildFilterChip(
                        label: 'THIS WEEK',
                        isSelected: false,
                        onTap: () => _setDatePreset('week'),
                        color: DomainColors.projectsDark.primary,
                      ),
                      _buildFilterChip(
                        label: 'OVERDUE',
                        isSelected: false,
                        onTap: () => _setDatePreset('overdue'),
                        color: const Color(0xFFFF6B6B),
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
                      _buildSortChip(label: 'Priority', field: 'priority'),
                      _buildSortChip(label: 'Due Date', field: 'due_date'),
                      _buildSortChip(label: 'Created', field: 'created_at'),
                      _buildSortChip(label: 'Title', field: 'title'),
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
                        color: DomainColors.workDark.primary,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                        boxShadow: [
                          BoxShadow(
                            color: DomainColors.workDark.glow!,
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          'Apply Filters',
                          style: AppTypography.metadataText(
                            color: const Color(0xFF0D0B09),
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
