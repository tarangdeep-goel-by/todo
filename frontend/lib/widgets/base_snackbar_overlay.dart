import 'dart:async';
import 'package:flutter/material.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../config/spacing.dart';

/// Base state for animated snackbar overlays.
///
/// Provides shared slide-up + fade-in animation, auto-hide timer, and the
/// decorated container shell. Subclasses override [build] and call
/// [buildSnackbarShell] to wrap their content.
abstract class BaseSnackbarOverlayState<T extends StatefulWidget> extends State<T>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  late final Animation<Offset> slideAnimation;
  late final Animation<double> fadeAnimation;
  Timer? autoHideTimer;

  /// The domain palette for theming the snackbar.
  DomainPalette get palette;

  /// How long the snackbar stays visible before auto-dismissing.
  Duration get duration;

  /// Called when the snackbar is fully dismissed (after reverse animation).
  VoidCallback get onDismiss;

  @override
  void initState() {
    super.initState();

    controller = AnimationController(
      vsync: this,
      duration: AppAnimations.snackbarIn,
      reverseDuration: AppAnimations.snackbarOut,
    );

    slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: controller,
      curve: AppAnimations.easeOutCubic,
      reverseCurve: Curves.easeIn,
    ));

    fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: controller, curve: Curves.easeOut),
    );

    controller.forward();
    autoHideTimer = Timer(duration, animateOut);
  }

  Future<void> animateOut() async {
    if (!mounted) return;
    await controller.reverse();
    if (mounted) onDismiss();
  }

  @override
  void dispose() {
    autoHideTimer?.cancel();
    controller.dispose();
    super.dispose();
  }

  /// Builds the positioned, animated container shell. Subclasses provide the
  /// inner [child] (icon + message row, undo button, etc.).
  Widget buildSnackbarShell({required Widget child}) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Positioned(
      left: AppSpacing.md,
      right: AppSpacing.md,
      bottom: bottomPadding + 96,
      child: SlideTransition(
        position: slideAnimation,
        child: FadeTransition(
          opacity: fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 14,
              ),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(
                  color: palette.primary.withValues(alpha: 0.2),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
