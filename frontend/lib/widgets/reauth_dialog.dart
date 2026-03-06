import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../config/typography.dart';

/// Non-dismissible dialog shown when token refresh fails.
/// User must acknowledge before being signed out.
class ReauthDialog extends StatelessWidget {
  const ReauthDialog({super.key});

  static bool _isShowing = false;

  static void show(BuildContext context) {
    if (_isShowing) return;
    _isShowing = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ReauthDialog(),
    ).then((_) => _isShowing = false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: AppColors.darkBg,
        title: Text(
          'Session expired',
          style: AppTypography.ctaLabelText(color: AppColors.darkText)
              .copyWith(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Please sign in again to continue.',
          style: AppTypography.metadataText(
            color: AppColors.darkText.withValues(alpha: 0.8),
          ).copyWith(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await FirebaseAuth.instance.signOut();
            },
            child: Text(
              'Sign Out',
              style: AppTypography.ctaLabelText(color: AppColors.darkText)
                  .copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
