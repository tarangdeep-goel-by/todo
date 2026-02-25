import 'dart:async';
import 'package:flutter/material.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../services/haptic_service.dart';

/// Shows a domain-colored floating undo bar at the bottom of the screen.
///
/// Returns a [VoidCallback] that dismisses the bar early (used on navigation).
/// Calls [onUndo] if the user taps "Undo" before timeout.
VoidCallback showUndoSnackbar(
  BuildContext context, {
  required String message,
  required DomainPalette domain,
  required VoidCallback onUndo,
  Duration duration = const Duration(seconds: 4),
}) {
  // Clear any existing material snackbars to avoid stacking
  ScaffoldMessenger.of(context).clearSnackBars();

  late OverlayEntry entry;
  bool dismissed = false;

  void dismiss() {
    if (dismissed) return;
    dismissed = true;
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (context) => _UndoSnackbarOverlay(
      message: message,
      domain: domain,
      duration: duration,
      onUndo: () {
        HapticService.light();
        dismiss();
        onUndo();
      },
      onDismiss: dismiss,
    ),
  );

  Overlay.of(context).insert(entry);

  return dismiss;
}

class _UndoSnackbarOverlay extends StatefulWidget {
  final String message;
  final DomainPalette domain;
  final Duration duration;
  final VoidCallback onUndo;
  final VoidCallback onDismiss;

  const _UndoSnackbarOverlay({
    required this.message,
    required this.domain,
    required this.duration,
    required this.onUndo,
    required this.onDismiss,
  });

  @override
  State<_UndoSnackbarOverlay> createState() => _UndoSnackbarOverlayState();
}

class _UndoSnackbarOverlayState extends State<_UndoSnackbarOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;
  Timer? _autoHideTimer;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: AppAnimations.snackbarIn,
      reverseDuration: AppAnimations.snackbarOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: AppAnimations.easeOutCubic,
      reverseCurve: Curves.easeIn,
    ));

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _controller.forward();

    _autoHideTimer = Timer(widget.duration, _animateOut);
  }

  Future<void> _animateOut() async {
    if (!mounted) return;
    await _controller.reverse();
    if (mounted) widget.onDismiss();
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Positioned(
      left: AppSpacing.md,
      right: AppSpacing.md,
      bottom: bottomPadding + 96, // above the CTA button area
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 14,
              ),
              decoration: BoxDecoration(
                color: widget.domain.surface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(
                  color: widget.domain.primary.withValues(alpha: 0.2),
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
              child: Row(
                children: [
                  // Check icon
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: widget.domain.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check,
                      size: 16,
                      color: widget.domain.primary,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Message
                  Expanded(
                    child: Text(
                      widget.message,
                      style: AppTypography.metadataText(
                        color: widget.domain.primary,
                      ).copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Undo button
                  GestureDetector(
                    onTap: widget.onUndo,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: widget.domain.primary,
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusPill),
                      ),
                      child: Text(
                        'Undo',
                        style: AppTypography.metadataText(
                          color: widget.domain.textOnPrimary,
                        ).copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
