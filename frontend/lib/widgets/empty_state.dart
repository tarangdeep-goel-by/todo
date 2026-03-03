import 'package:flutter/material.dart';
import '../config/typography.dart';
import '../config/spacing.dart';

/// Empty state widget with optional rich content for onboarding contexts.
///
/// Basic usage (error states, simple empty):
///   EmptyState(message: 'No items', icon: Icons.inbox)
///
/// Rich usage (onboarding, first-use):
///   EmptyState(
///     title: 'Your world, organized',
///     message: 'Speak a task to get started.',
///     icon: Icons.auto_awesome,
///     examples: ['Add groceries to home'],
///     actionLabel: 'Add Domain',
///     onAction: () => ...,
///   )
class EmptyState extends StatelessWidget {
  final String message;
  final Color? textColor;
  final IconData? icon;
  final VoidCallback? onRetry;
  final String? title;
  final List<String>? examples;
  final VoidCallback? onAction;
  final String? actionLabel;

  const EmptyState({
    super.key,
    required this.message,
    this.textColor,
    this.icon,
    this.onRetry,
    this.title,
    this.examples,
    this.onAction,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    final color = textColor ?? Colors.white;
    final isRich = title != null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: isRich ? 44 : 32,
                color: color.withValues(alpha: isRich ? 0.2 : 0.5),
              ),
              SizedBox(height: isRich ? AppSpacing.md : AppSpacing.sm),
            ],
            if (isRich) ...[
              Text(
                title!,
                style: AppTypography.ctaLabelText(color: color).copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            Text(
              message,
              style: AppTypography.metadataText(
                color: color.withValues(alpha: isRich ? 0.45 : 0.6),
              ).copyWith(
                fontSize: isRich ? 14 : 11,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            if (examples != null && examples!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              ...examples!.map((ex) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.04),
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusSm),
                        border: Border.all(
                          color: color.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '\u201C',
                            style: TextStyle(
                              color: color.withValues(alpha: 0.2),
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              ex,
                              style: AppTypography.metadataText(
                                color: color.withValues(alpha: 0.55),
                              ).copyWith(
                                fontSize: 13,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )),
            ],
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: AppSpacing.lg),
              TextButton.icon(
                onPressed: onAction,
                icon: Icon(Icons.add, size: 18, color: color),
                label: Text(
                  actionLabel!,
                  style: AppTypography.ctaLabelText(color: color),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusSm),
                    side: BorderSide(
                      color: color.withValues(alpha: 0.2),
                    ),
                  ),
                ),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.md),
              TextButton.icon(
                onPressed: onRetry,
                icon: Icon(Icons.refresh, color: color),
                label: Text(
                  'Retry',
                  style: AppTypography.ctaLabelText(color: color),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
