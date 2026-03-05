import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';

/// Top bar with app name and sign-out action
class TopBar extends ConsumerWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: AppSpacing.topBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: [
          Text(
            'Amble',
            style: AppTypography.ctaLabelText(
              color: AppColors.darkText,
            ).copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => _confirmSignOut(context, ref),
            child: Icon(
              Icons.logout_rounded,
              color: AppColors.secondaryText,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  void _confirmSignOut(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navBg,
        title: Text(
          'Sign out?',
          style: TextStyle(color: AppColors.darkText),
        ),
        content: Text(
          'Your tasks will be here when you return.',
          style: TextStyle(color: AppColors.secondaryText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.secondaryText),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(authServiceProvider).signOut();
            },
            child: Text(
              'Sign out',
              style: TextStyle(color: AppColors.snackbarError.primary),
            ),
          ),
        ],
      ),
    );
  }
}
