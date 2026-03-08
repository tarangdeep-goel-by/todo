import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/theme.dart';

import '../services/haptic_service.dart';
import 'base_snackbar_overlay.dart';

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
      snackbarDuration: duration,
      onUndo: () {
        HapticService.light();
        dismiss();
        onUndo();
      },
      onDismissCallback: dismiss,
    ),
  );

  Overlay.of(context).insert(entry);

  return dismiss;
}

class _UndoSnackbarOverlay extends StatefulWidget {
  final String message;
  final DomainPalette domain;
  final Duration snackbarDuration;
  final VoidCallback onUndo;
  final VoidCallback onDismissCallback;

  const _UndoSnackbarOverlay({
    required this.message,
    required this.domain,
    required this.snackbarDuration,
    required this.onUndo,
    required this.onDismissCallback,
  });

  @override
  State<_UndoSnackbarOverlay> createState() => _UndoSnackbarOverlayState();
}

class _UndoSnackbarOverlayState
    extends BaseSnackbarOverlayState<_UndoSnackbarOverlay> {
  @override
  DomainPalette get palette => widget.domain;

  @override
  Duration get duration => widget.snackbarDuration;

  @override
  VoidCallback get onDismiss => widget.onDismissCallback;

  @override
  Widget build(BuildContext context) {
    return buildSnackbarShell(
      child: Row(
        children: [
          // Check icon
          Icon(
            Icons.check,
            size: 16,
            color: palette.primary,
          ),
          const SizedBox(width: 12),

          // Message
          Expanded(
            child: Text(
              widget.message,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.darkText,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          const SizedBox(width: 12),

          // Undo button
          GestureDetector(
            onTap: widget.onUndo,
            child: Text(
              'Undo',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: palette.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
