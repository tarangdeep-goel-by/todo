import 'package:flutter/material.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../services/haptic_service.dart';

/// First-launch welcome overlay. Single screen, three teaching points.
class WelcomeOverlay extends StatefulWidget {
  final VoidCallback onDismiss;

  const WelcomeOverlay({super.key, required this.onDismiss});

  @override
  State<WelcomeOverlay> createState() => _WelcomeOverlayState();
}

class _WelcomeOverlayState extends State<WelcomeOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppAnimations.overlayFade,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _scaleAnimation = Tween(begin: 0.96, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
  }

  Future<void> _dismiss() async {
    HapticService.medium();
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    // Domain palette colors for the accent dots
    final accentColors = DomainColors.palettes.map((p) => p.primary).toList();

    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Material(
          color: AppColors.darkBg,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                children: [
                  SizedBox(height: screenHeight * 0.12),

                  // Domain color dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: accentColors
                        .map((c) => Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                              ),
                            ))
                        .toList(),
                  ),

                  const SizedBox(height: AppSpacing.lg),

                  // Brand
                  Text(
                    'Amble',
                    style: AppTypography.domainTitle(
                      context,
                      color: AppColors.darkText,
                    ).copyWith(fontSize: AppTypography.emptyStateDisplay),
                  ),

                  const SizedBox(height: AppSpacing.sm),

                  Text(
                    'Your voice, organized.',
                    style: AppTypography.ctaLabelText(
                      color: AppColors.secondaryText,
                    ).copyWith(fontSize: 16),
                  ),

                  SizedBox(height: screenHeight * 0.07),

                  // Teaching points
                  _buildPoint(
                    Icons.mic_none_rounded,
                    'Say it, done.',
                    'Just speak \u2014 Amble finds the right\ndomain and creates the task.',
                    accentColors[0],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _buildPoint(
                    Icons.auto_awesome,
                    'AI handles the rest',
                    'Swipe, long-press, hold the mic \u2014\nyou\u2019ll discover as you go.',
                    accentColors[1],
                  ),

                  const Spacer(),

                  // Get Started button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: TextButton(
                      onPressed: _dismiss,
                      style: TextButton.styleFrom(
                        backgroundColor: AppColors.darkText,
                        foregroundColor: AppColors.darkBg,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusPill),
                        ),
                      ),
                      child: Text(
                        'Get Started',
                        style: AppTypography.ctaLabelText(
                          color: AppColors.darkBg,
                        ).copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.md),

                  // Skip option
                  Semantics(
                    button: true,
                    label: 'Skip onboarding',
                    child: GestureDetector(
                      onTap: _dismiss,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          "I'll explore on my own",
                          style: AppTypography.metadataText(
                            color: AppColors.secondaryText,
                          ).copyWith(fontSize: 13),
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: screenHeight * 0.05),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPoint(
      IconData icon, String title, String desc, Color accent) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: accent),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.ctaLabelText(
                  color: AppColors.darkText,
                ).copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                desc,
                style: AppTypography.metadataText(
                  color: AppColors.secondaryText,
                ).copyWith(fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
