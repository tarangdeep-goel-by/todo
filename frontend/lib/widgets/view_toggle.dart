import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../config/theme.dart';
import '../providers/view_mode_provider.dart';
import '../services/haptic_service.dart';

/// View toggle button (Node/Flat)
class ViewToggle extends ConsumerWidget {
  const ViewToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewMode = ref.watch(viewModeProvider);

    final bgColor = AppColors.darkBg;
    final textColor = AppColors.darkText;
    final activeColor = AppColors.darkText;
    final inactiveColor = textColor.withValues(alpha: 0.5);

    return Container(
      width: 140,
      height: 36,
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(
          color: textColor.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Stack(
        children: [
          // Sliding indicator
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            left: viewMode == ViewMode.node ? 0 : 70,
            top: 0,
            bottom: 0,
            width: 70,
            child: Container(
              decoration: BoxDecoration(
                color: activeColor,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              ),
            ),
          ),

          // Buttons
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticService.selection();
                    ref.read(viewModeProvider.notifier).state = ViewMode.node;
                  },
                  child: Container(
                    color: Colors.transparent,
                    child: Center(
                      child: Text(
                        'Node',
                        style: AppTypography.metadataText(
                          color: viewMode == ViewMode.node
                              ? bgColor
                              : inactiveColor,
                        ).copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticService.selection();
                    ref.read(viewModeProvider.notifier).state = ViewMode.flat;
                  },
                  child: Container(
                    color: Colors.transparent,
                    child: Center(
                      child: Text(
                        'Flat',
                        style: AppTypography.metadataText(
                          color: viewMode == ViewMode.flat
                              ? bgColor
                              : inactiveColor,
                        ).copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
