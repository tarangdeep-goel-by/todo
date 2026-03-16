import 'package:flutter/animation.dart';
/// Animation curves and durations
class AppAnimations {
  // Custom easing curves (from design brief)
  static const easeOutQuint = Cubic(0.22, 1.0, 0.36, 1.0);
  static const easeOutCubic = Cubic(0.33, 1.0, 0.68, 1.0);
  // Durations
  static const cardExpand = Duration(milliseconds: 450);
  static const cardCollapse = Duration(milliseconds: 400);
  static const waveformUpdate = Duration(milliseconds: 33); // ~30fps
  static const viewTransition = Duration(milliseconds: 400);
  static const staggerDelay = Duration(milliseconds: 50);
  static const ctaExpand = Duration(milliseconds: 200);
  static const ctaContract = Duration(milliseconds: 300);
  static const snackbarIn = Duration(milliseconds: 250);
  static const snackbarOut = Duration(milliseconds: 200);
  static const shimmerSweep = Duration(milliseconds: 750);
  static const glowSettle = Duration(milliseconds: 600);
  static const overlayFade = Duration(milliseconds: 500);
  static const coachingCycle = Duration(seconds: 4);
  static const coachingSwitch = Duration(milliseconds: 600);
  static const tutorialBounce = Duration(milliseconds: 1200);
  static const hintBounce = Duration(milliseconds: 900);
  static const voicePulse = Duration(milliseconds: 1800);
}

/// App-wide constants
class AppConstants {
  // API base URL — hardcoded default for Android emulator.
  // For physical device testing, change this to your machine's network IP.
  static const String apiBaseUrl = 'http://10.0.2.2:8001/api';

  // Audio recording settings
  static const String audioFolderName = 'audio_recordings';
  static const String audioFileExtension = '.m4a';

  // Task status
  static const String statusActive = 'active';
  static const String statusCompleted = 'completed';
}
