import 'package:flutter/material.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../config/theme.dart';

/// Top bar with app name
class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppSpacing.topBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      alignment: Alignment.centerLeft,
      child: Text(
        'VOKL',
        style: AppTypography.ctaLabelText(
          color: AppColors.darkText,
        ).copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    );
  }
}
