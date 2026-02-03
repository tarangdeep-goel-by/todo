import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/theme.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../models/task_filter.dart';
import '../providers/task_filter_provider.dart';
import '../services/haptic_service.dart';

class ActiveFilterChips extends ConsumerWidget {
  const ActiveFilterChips({super.key});

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'work':
        return DomainColors.workDark.primary;
      case 'personal':
        return DomainColors.personalDark.primary;
      case 'projects':
        return DomainColors.projectsDark.primary;
      case 'learning':
        return DomainColors.learningDark.primary;
      default:
        return AppColors.darkText;
    }
  }

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

    if (!filter.isActive) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 40,
      margin: const EdgeInsets.only(top: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        children: [
          // Category chips
          if (filter.categories?.isNotEmpty ?? false)
            ...filter.categories!.map((cat) => _buildChip(
                  label: cat.toUpperCase(),
                  color: _getCategoryColor(cat),
                  onRemove: () {
                    HapticService.light();
                    final updated = filter.categories!.toList()..remove(cat);
                    ref.read(taskFilterProvider.notifier).state = filter.copyWith(
                      categories: updated.isEmpty ? null : updated,
                    );
                    ref.read(paginationStateProvider.notifier).reset();
                  },
                )),

          // Priority chips
          if (filter.priorities?.isNotEmpty ?? false)
            ...filter.priorities!.map((priority) {
              final color = priority == 'high'
                  ? const Color(0xFFFF6B6B)
                  : priority == 'medium'
                      ? const Color(0xFFFFA726)
                      : const Color(0xFF66BB6A);
              return _buildChip(
                label: 'PRI: ${priority.toUpperCase()}',
                color: color,
                onRemove: () {
                  HapticService.light();
                  final updated = filter.priorities!.toList()..remove(priority);
                  ref.read(taskFilterProvider.notifier).state = filter.copyWith(
                    priorities: updated.isEmpty ? null : updated,
                  );
                  ref.read(paginationStateProvider.notifier).reset();
                },
              );
            }),

          // Status chips
          if (filter.statuses?.isNotEmpty ?? false)
            ...filter.statuses!.map((status) {
              final color = status == 'completed'
                  ? const Color(0xFF66BB6A)
                  : DomainColors.workDark.primary;
              return _buildChip(
                label: status.toUpperCase(),
                color: color,
                onRemove: () {
                  HapticService.light();
                  final updated = filter.statuses!.toList()..remove(status);
                  ref.read(taskFilterProvider.notifier).state = filter.copyWith(
                    statuses: updated.isEmpty ? null : updated,
                  );
                  ref.read(paginationStateProvider.notifier).reset();
                },
              );
            }),

          // Date chips
          if (filter.createdAtGte != null || filter.createdAtLte != null)
            _buildChip(
              label: 'DATE RANGE',
              color: DomainColors.projectsDark.primary,
              onRemove: () {
                HapticService.light();
                ref.read(taskFilterProvider.notifier).state = filter.copyWith(
                  createdAtGte: null,
                  createdAtLte: null,
                );
                ref.read(paginationStateProvider.notifier).reset();
              },
            ),

          if (filter.dueDateGte != null || filter.dueDateLte != null)
            _buildChip(
              label: 'DUE DATE',
              color: const Color(0xFFFF6B6B),
              onRemove: () {
                HapticService.light();
                ref.read(taskFilterProvider.notifier).state = filter.copyWith(
                  dueDateGte: null,
                  dueDateLte: null,
                );
                ref.read(paginationStateProvider.notifier).reset();
              },
            ),

          // Sort chips
          if (filter.sortOptions.isNotEmpty)
            ...filter.sortOptions.map((sortOption) => _buildChip(
                  label:
                      'SORT: ${sortOption.field.toUpperCase()} ${sortOption.ascending ? '↑' : '↓'}',
                  color: DomainColors.learningDark.primary,
                  onRemove: () {
                    HapticService.light();
                    final updated = filter.sortOptions.toList()..remove(sortOption);
                    ref.read(taskFilterProvider.notifier).state = filter.copyWith(
                      sortOptions: updated,
                    );
                    ref.read(paginationStateProvider.notifier).reset();
                  },
                )),

          // Clear all button
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: GestureDetector(
              onTap: () {
                HapticService.medium();
                ref.read(taskFilterProvider.notifier).state = TaskFilter();
                ref.read(paginationStateProvider.notifier).reset();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: DomainColors.projectsDark.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(
                    color: DomainColors.projectsDark.primary,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    'Clear All',
                    style: AppTypography.metadataText(
                      color: DomainColors.projectsDark.primary,
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
