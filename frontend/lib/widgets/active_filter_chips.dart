import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onRemove,
              child: Icon(Icons.close, size: 14, color: color),
            ),
          ],
        ),
      ),
    );
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
                onRemove: () {
                  HapticService.light();
                  final updated = filter.categories!.toList()..remove(cat);
                  ref.read(taskFilterProvider.notifier).state = filter.copyWith(
                    categories: updated.isEmpty ? null : updated,
                  );
                },
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
                onRemove: () {
                  HapticService.light();
                  final updated = filter.priorities!.toList()..remove(priority);
                  ref.read(taskFilterProvider.notifier).state = filter.copyWith(
                    priorities: updated.isEmpty ? null : updated,
                  );
                },
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
                onRemove: () {
                  HapticService.light();
                  final updated = filter.statuses!.toList()..remove(status);
                  ref.read(taskFilterProvider.notifier).state = filter.copyWith(
                    statuses: updated.isEmpty ? null : updated,
                  );
                },
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
              label: 'DUE DATE',
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
