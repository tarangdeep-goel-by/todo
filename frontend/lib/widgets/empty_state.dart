import 'package:flutter/material.dart';
import '../config/typography.dart';
import '../config/spacing.dart';

/// Empty state widget for when there are no items
class EmptyState extends StatelessWidget {
  final String message;
  final Color? textColor;
  final IconData? icon;
  final VoidCallback? onRetry;

  const EmptyState({
    super.key,
    required this.message,
    this.textColor,
    this.icon,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 32,
              color: textColor?.withValues(alpha: 0.5),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Text(
            message,
            style: AppTypography.metadataText(
              color: textColor?.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: AppSpacing.md),
            TextButton.icon(
              onPressed: onRetry,
              icon: Icon(Icons.refresh, color: textColor),
              label: Text(
                'Retry',
                style: AppTypography.ctaLabelText(color: textColor),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
