import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/theme.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../providers/auth_provider.dart';
import '../widgets/grain_texture_painter.dart';
import '../widgets/styled_snackbar.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;

  late final AnimationController _controller;
  late final List<CurvedAnimation> _intervals;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    // 7 elements, staggered ~100ms apart
    _intervals = List.generate(7, (i) {
      final start = (i * 0.08).clamp(0.0, 1.0);
      final end = (start + 0.5).clamp(0.0, 1.0);
      return CurvedAnimation(
        parent: _controller,
        curve: Interval(start, end, curve: Curves.easeOutCubic),
      );
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);

    try {
      final authService = ref.read(authServiceProvider);
      await authService.signInWithGoogle();
    } on String catch (msg) {
      if (mounted) {
        showStyledSnackbar(context, message: msg, style: SnackbarStyle.error);
      }
    } catch (_) {
      if (mounted) {
        showStyledSnackbar(
          context,
          message: 'Something went wrong. Please try again.',
          style: SnackbarStyle.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _staggered(int index, Widget child) {
    return AnimatedBuilder(
      animation: _intervals[index],
      builder: (context, _) {
        final value = _intervals[index].value;
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - value)),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final accentColors = DomainColors.palettes.map((p) => p.primary).toList();

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Stack(
        children: [
          // Grain texture background
          Positioned.fill(
            child: CustomPaint(
              painter: GrainTexturePainter(
                color: AppColors.darkText,
                opacity: 0.03,
              ),
            ),
          ),

          // Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                children: [
                  SizedBox(height: screenHeight * 0.12),

                  // Domain color dots
                  _staggered(
                    0,
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: accentColors
                          .map((c) => Container(
                                width: 8,
                                height: 8,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                decoration: BoxDecoration(
                                  color: c,
                                  shape: BoxShape.circle,
                                ),
                              ))
                          .toList(),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.lg),

                  // Brand name
                  _staggered(
                    1,
                    Text(
                      'Amble',
                      style: AppTypography.domainTitle(
                        context,
                        color: AppColors.darkText,
                      ).copyWith(fontSize: AppTypography.emptyStateDisplay),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.sm),

                  // Tagline
                  _staggered(
                    2,
                    Text(
                      'Your voice, organized.',
                      style: AppTypography.ctaLabelText(
                        color: AppColors.secondaryText,
                      ).copyWith(fontSize: 16),
                    ),
                  ),

                  SizedBox(height: screenHeight * 0.07),

                  // Teaching point 1
                  _staggered(
                    3,
                    _buildPoint(
                      Icons.mic_none_rounded,
                      'Say it, done.',
                      'Just speak \u2014 Amble finds the right\ndomain and creates the task.',
                      accentColors[0],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.lg),

                  // Teaching point 2
                  _staggered(
                    4,
                    _buildPoint(
                      Icons.auto_awesome,
                      'AI handles the rest',
                      'Swipe, long-press, hold the mic \u2014\nyou\u2019ll discover as you go.',
                      accentColors[1],
                    ),
                  ),

                  const Spacer(),

                  // Google sign-in button
                  _staggered(
                    5,
                    GestureDetector(
                      onTap: _isLoading ? null : _signInWithGoogle,
                      child: Container(
                        width: double.infinity,
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppColors.darkText,
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusPill),
                        ),
                        alignment: Alignment.center,
                        child: _isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.darkBg,
                                ),
                              )
                            : Text(
                                'Continue with Google',
                                style: AppTypography.ctaLabelText(
                                  color: AppColors.darkBg,
                                ).copyWith(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.md),

                  // Footer text
                  _staggered(
                    6,
                    Text(
                      'Sign in to get started',
                      style: AppTypography.metadataText(
                        color: AppColors.secondaryText,
                      ).copyWith(fontSize: 13),
                    ),
                  ),

                  SizedBox(height: screenHeight * 0.05),
                ],
              ),
            ),
          ),
        ],
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
