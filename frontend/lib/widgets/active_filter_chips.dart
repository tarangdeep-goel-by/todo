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

class ActiveFilterChips extends ConsumerWidget {
  const ActiveFilterChips({super.key});

  Widget _buildChip({
    required String label,
    required Color color,
    required VoidCallback onRemove,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: color, width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppTypography.metadataText(color: color)
                  .copyWith(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            Semantics(
              button: true,
              label: 'Remove $label filter',
              child: GestureDetector(
                onTap: onRemove,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: AppSpacing.minTouchTarget,
                  height: AppSpacing.minTouchTarget,
                  child: Center(
                    child: Icon(Icons.close, size: 14, color: color),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDueDateLabel(TaskFilter filter) {
    final fmt = DateFormat('MMM d');
    if (filter.dueDateGte != null && filter.dueDateLte != null) {
      return '${fmt.format(filter.dueDateGte!)} - ${fmt.format(filter.dueDateLte!)}';
    }
    if (filter.dueDateLte != null) return 'OVERDUE';
    if (filter.dueDateGte != null) return 'DUE AFTER ${fmt.format(filter.dueDateGte!)}';
    return 'DUE DATE';
  }

  VoidCallback _removeFromList({
    required WidgetRef ref,
    required TaskFilter filter,
    required String value,
    required List<String> list,
    required TaskFilter Function(List<String>?) updater,
  }) {
    return () {
      HapticService.light();
      final updated = list.toList()..remove(value);
      ref.read(taskFilterProvider.notifier).state =
          updater(updated.isEmpty ? null : updated);
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(taskFilterProvider);
    final paletteMap = ref.watch(domainPalettesProvider);

    if (!filter.isActive) {
      return const SizedBox.shrink();
    }

    // Use first domain's color as accent fallback
    final accentColor = paletteMap.values.isNotEmpty
        ? paletteMap.values.first.primary
        : DomainColors.palettes.first.primary;

    return Container(
      height: 40,
      margin: const EdgeInsets.only(top: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        children: [
          // Category chips — use domain palette color
          if (filter.categories?.isNotEmpty ?? false)
            ...filter.categories!.map((cat) {
              final domain = DomainColors.getDomain(cat, true, paletteMap);
              return _buildChip(
                label: cat.toUpperCase(),
                color: domain.primary,
                onRemove: _removeFromList(
                  ref: ref,
                  filter: filter,
                  value: cat,
                  list: filter.categories!,
                  updater: (v) => filter.copyWith(categories: v),
                ),
              );
            }),

          // Priority chips
          if (filter.priorities?.isNotEmpty ?? false)
            ...filter.priorities!.map((priority) {
              final color = priority == 'high'
                  ? AppColors.priorityHigh
                  : priority == 'medium'
                      ? AppColors.priorityMedium
                      : AppColors.priorityLow;
              return _buildChip(
                label: 'PRI: ${priority.toUpperCase()}',
                color: color,
                onRemove: _removeFromList(
                  ref: ref,
                  filter: filter,
                  value: priority,
                  list: filter.priorities!,
                  updater: (v) => filter.copyWith(priorities: v),
                ),
              );
            }),

          // Status chips
          if (filter.statuses?.isNotEmpty ?? false)
            ...filter.statuses!.map((status) {
              final color = status == 'overdue'
                  ? AppColors.overdue
                  : status == 'completed'
                      ? AppColors.completed
                      : accentColor;
              return _buildChip(
                label: status.toUpperCase(),
                color: color,
                onRemove: _removeFromList(
                  ref: ref,
                  filter: filter,
                  value: status,
                  list: filter.statuses!,
                  updater: (v) => filter.copyWith(statuses: v),
                ),
              );
            }),

          // Date chips
          if (filter.createdAtGte != null || filter.createdAtLte != null)
            _buildChip(
              label: 'DATE RANGE',
              color: accentColor,
              onRemove: () {
                HapticService.light();
                ref.read(taskFilterProvider.notifier).state = filter.copyWith(
                  createdAtGte: null,
                  createdAtLte: null,
                );
              },
            ),

          if (filter.dueDateGte != null || filter.dueDateLte != null)
            _buildChip(
              label: _formatDueDateLabel(filter),
              color: AppColors.overdue,
              onRemove: () {
                HapticService.light();
                ref.read(taskFilterProvider.notifier).state = filter.copyWith(
                  dueDateGte: null,
                  dueDateLte: null,
                );
              },
            ),

          // Sort chips
          if (filter.sortOptions.isNotEmpty)
            ...filter.sortOptions.map((sortOption) => _buildChip(
                  label:
                      'SORT: ${sortOption.field.toUpperCase()} ${sortOption.ascending ? '↑' : '↓'}',
                  color: accentColor,
                  onRemove: () {
                    HapticService.light();
                    final updated = filter.sortOptions.toList()..remove(sortOption);
                    ref.read(taskFilterProvider.notifier).state = filter.copyWith(
                      sortOptions: updated,
                    );
                  },
                )),

          // Clear all button
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: GestureDetector(
              onTap: () {
                HapticService.medium();
                ref.read(taskFilterProvider.notifier).state = TaskFilter();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(
                    color: accentColor,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    'Clear All',
                    style: AppTypography.metadataText(
                      color: accentColor,
                    ).copyWith(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
