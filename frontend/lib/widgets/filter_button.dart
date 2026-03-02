import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/theme.dart';
import '../config/spacing.dart';
import '../providers/task_filter_provider.dart';
import '../providers/task_store_provider.dart';
import '../services/haptic_service.dart';
import 'filter_sheet.dart';

class FilterButton extends ConsumerWidget {
  const FilterButton({super.key});

  void _openFilterSheet(BuildContext context) {
    HapticService.medium();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const FilterSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(taskFilterProvider);
    final activeCount = filter.activeFilterCount;
    final paletteMap = ref.watch(domainPalettesProvider);
    final accent = paletteMap.values.isNotEmpty
        ? paletteMap.values.first
        : DomainColors.palettes.first.withName('');

    return Positioned(
      top: AppSpacing.topBarHeight + 8,
      right: AppSpacing.md,
      child: GestureDetector(
        onTap: () => _openFilterSheet(context),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.darkBg,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(
              color: activeCount > 0
                  ? accent.primary
                  : AppColors.darkText.withValues(alpha: 0.3),
              width: 2,
            ),
            boxShadow: activeCount > 0
                ? [
                    BoxShadow(
                      color: accent.glow ?? accent.primary.withValues(alpha: 0.3),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Stack(
            children: [
              Center(
                child: Icon(
                  Icons.tune_rounded,
                  color: activeCount > 0
                      ? accent.primary
                      : AppColors.darkText,
                  size: 24,
                ),
              ),
              if (activeCount > 0)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: accent.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$activeCount',
                        style: const TextStyle(
                          color: AppColors.darkBg,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
