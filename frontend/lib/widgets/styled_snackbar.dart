import 'dart:async';
import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../config/spacing.dart';
import '../config/typography.dart';

/// Snackbar style variants.
enum SnackbarStyle { success, error, info }

/// Error palette (crimson rose).
const _errorPalette = DomainPalette(
  name: 'Error',
  primary: Color(0xFFE84878),
  darkShade: Color(0xFF8A1A45),
  surface: Color(0xFF1F0D14),
  textOnPrimary: Color(0xFF0D0B09),
);

/// Info palette (neutral warm).
const _infoPalette = DomainPalette(
  name: 'Info',
  primary: Color(0xFFB0A99E),
  darkShade: Color(0xFF3A3530),
  surface: Color(0xFF1A1815),
  textOnPrimary: Color(0xFF0D0B09),
);

/// Shows a styled snackbar matching the app's design language.
/// For success, pass a [domain] palette. For errors/info, palette is resolved
/// from [style] automatically.
VoidCallback showStyledSnackbar(
  BuildContext context, {
  required String message,
  SnackbarStyle style = SnackbarStyle.info,
  DomainPalette? domain,
  Duration duration = const Duration(seconds: 3),
}) {
  // Clear any lingering material snackbars
  ScaffoldMessenger.of(context).clearSnackBars();

  late OverlayEntry entry;
  bool dismissed = false;

  void dismiss() {
    if (dismissed) return;
    dismissed = true;
    entry.remove();
  }

  final palette = domain ?? _paletteForStyle(style);
  final icon = switch (style) {
    SnackbarStyle.success => Icons.check,
    SnackbarStyle.error => Icons.error_outline,
    SnackbarStyle.info => Icons.info_outline,
  };

  entry = OverlayEntry(
    builder: (context) => _StyledSnackbarOverlay(
      message: message,
      palette: palette,
      icon: icon,
      duration: duration,
      onDismiss: dismiss,
    ),
  );

  Overlay.of(context).insert(entry);
  return dismiss;
}

DomainPalette _paletteForStyle(SnackbarStyle style) {
  return switch (style) {
    SnackbarStyle.success => DomainColors.defaultPalette,
    SnackbarStyle.error => _errorPalette,
    SnackbarStyle.info => _infoPalette,
  };
}

class _StyledSnackbarOverlay extends StatefulWidget {
  final String message;
  final DomainPalette palette;
  final IconData icon;
  final Duration duration;
  final VoidCallback onDismiss;

  const _StyledSnackbarOverlay({
    required this.message,
    required this.palette,
    required this.icon,
    required this.duration,
    required this.onDismiss,
  });

  @override
  State<_StyledSnackbarOverlay> createState() => _StyledSnackbarOverlayState();
}

class _StyledSnackbarOverlayState extends State<_StyledSnackbarOverlay>
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
      duration: const Duration(milliseconds: 250),
      reverseDuration: const Duration(milliseconds: 200),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
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
      bottom: bottomPadding + 96,
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
                color: widget.palette.surface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(
                  color: widget.palette.primary.withValues(alpha: 0.2),
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
                  // Icon
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: widget.palette.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.icon,
                      size: 16,
                      color: widget.palette.primary,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Message
                  Expanded(
                    child: Text(
                      widget.message,
                      style: AppTypography.metadataText(
                        color: widget.palette.primary,
                      ).copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
