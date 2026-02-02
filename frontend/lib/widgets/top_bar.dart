import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../config/theme.dart';
import 'view_toggle.dart';

/// Top bar with app name, context, and controls
class TopBar extends ConsumerWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: AppSpacing.topBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // App name
          Text(
            'VOKL',
            style: AppTypography.ctaLabelText(
              color: AppColors.darkText,
            ).copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),

          // View toggle
          const ViewToggle(),

          // Spacer for balance (removed theme toggle)
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}
