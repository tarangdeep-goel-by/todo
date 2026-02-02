import 'package:flutter/services.dart';

/// Service for haptic feedback
class HapticService {
  /// Light impact (for button taps, selections)
  static void light() {
    HapticFeedback.lightImpact();
  }

  /// Medium impact (for confirmations)
  static void medium() {
    HapticFeedback.mediumImpact();
  }

  /// Heavy impact (for important actions)
  static void heavy() {
    HapticFeedback.heavyImpact();
  }

  /// Selection click (for toggles, switches)
  static void selection() {
    HapticFeedback.selectionClick();
  }

  /// Vibrate (for errors, warnings)
  static void vibrate() {
    HapticFeedback.vibrate();
  }
}
