import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/spacing.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../providers/recording_provider.dart';

/// Overlay pill for processing state (sits above bottom nav)
class PttInputOverlay extends ConsumerWidget {
  const PttInputOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordingState = ref.watch(recordingStateProvider);

    if (recordingState != RecordingState.processing) {
      return const SizedBox.shrink();
    }

    final activeBg = DomainColors.careerDark.primary;
    final activeText = DomainColors.careerDark.textOnPrimary;

    return Center(
      child: AnimatedContainer(
        duration: AppAnimations.ctaExpand,
        curve: AppAnimations.easeOutQuint,
        width: AppSpacing.ctaActiveWidth,
        height: AppSpacing.ctaActiveHeight,
        decoration: BoxDecoration(
          color: activeBg,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (index) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: AnimatedOpacity(
                opacity: 0.5 + (0.5 * ((index + 1) % 3) / 2),
                duration: const Duration(milliseconds: 500),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: activeText,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
