import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../config/typography.dart';
import 'base_snackbar_overlay.dart';

/// Snackbar style variants.
enum SnackbarStyle { success, error, info }

/// Error palette (crimson rose).
const _errorPalette = DomainPalette(
  name: 'Error',
  primary: Color(0xFFE84878),
  darkShade: Color(0xFF8A1A45),
  surface: Color(0xFF1F0D14),
  textOnPrimary: AppColors.darkBg,
);

/// Info palette (neutral warm).
const _infoPalette = DomainPalette(
  name: 'Info',
  primary: Color(0xFFB0A99E),
  darkShade: Color(0xFF3A3530),
  surface: Color(0xFF1A1815),
  textOnPrimary: AppColors.darkBg,
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
      snackbarPalette: palette,
      icon: icon,
      snackbarDuration: duration,
      onDismissCallback: dismiss,
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
  final DomainPalette snackbarPalette;
  final IconData icon;
  final Duration snackbarDuration;
  final VoidCallback onDismissCallback;

  const _StyledSnackbarOverlay({
    required this.message,
    required this.snackbarPalette,
    required this.icon,
    required this.snackbarDuration,
    required this.onDismissCallback,
  });

  @override
  State<_StyledSnackbarOverlay> createState() => _StyledSnackbarOverlayState();
}

class _StyledSnackbarOverlayState
    extends BaseSnackbarOverlayState<_StyledSnackbarOverlay> {
  @override
  DomainPalette get palette => widget.snackbarPalette;

  @override
  Duration get duration => widget.snackbarDuration;

  @override
  VoidCallback get onDismiss => widget.onDismissCallback;

  @override
  Widget build(BuildContext context) {
    return buildSnackbarShell(
      child: Row(
        children: [
          // Icon
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: palette.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              widget.icon,
              size: 16,
              color: palette.primary,
            ),
          ),
          const SizedBox(width: 12),

          // Message
          Expanded(
            child: Text(
              widget.message,
              style: AppTypography.metadataText(
                color: palette.primary,
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
    );
  }
}
