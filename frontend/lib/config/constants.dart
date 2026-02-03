import 'package:flutter/animation.dart';

/// Animation curves and durations
class AppAnimations {
  // Custom easing curves (from design brief)
  static const easeOutQuint = Cubic(0.22, 1.0, 0.36, 1.0);
  static const easeOutCubic = Cubic(0.33, 1.0, 0.68, 1.0);
  static const easeInQuad = Cubic(0.55, 0.085, 0.68, 0.53);

  // Durations
  static const cardExpand = Duration(milliseconds: 350);
  static const cardCollapse = Duration(milliseconds: 350);
  static const waveformUpdate = Duration(milliseconds: 33); // ~30fps
  static const viewTransition = Duration(milliseconds: 400);
  static const staggerDelay = Duration(milliseconds: 50);
  static const ctaExpand = Duration(milliseconds: 200);
  static const ctaContract = Duration(milliseconds: 300);
}

/// App-wide constants
class AppConstants {
  // Default user ID (MVP)
  static const String defaultUserId = 'default-user';

  // API base URL
  // For Android device testing, use your machine's local IP
  // For Android emulator, use 10.0.2.2 instead of localhost
  static const String apiBaseUrl = 'http://192.168.0.102:8001/api';

  // Audio recording settings
  static const String audioFolderName = 'audio_recordings';
  static const String audioFileExtension = '.m4a';

  // Domain names (must match backend)
  static const List<String> domainNames = [
    'Work',
    'Personal',
    'Health',
    'Learning',
    'Projects',
  ];

  // Task status
  static const String statusActive = 'active';
  static const String statusCompleted = 'completed';
}
