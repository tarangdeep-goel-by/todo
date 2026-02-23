import 'dart:math' as math;

/// Controller for liquid focus scroll behavior
/// Cards expand/contract based on their distance from viewport center
class LiquidFocusScrollController {
  final int totalCards;
  final double viewportHeight;
  final double topBarHeight;
  final double ctaZoneHeight;

  late final double availableHeight;
  late final double focusedHeight;
  late final double compressedHeight;

  LiquidFocusScrollController({
    required this.totalCards,
    required this.viewportHeight,
    this.topBarHeight = 48.0,
    this.ctaZoneHeight = 120.0, // CTA button + padding
  }) {
    // Calculate available viewport height
    availableHeight = viewportHeight - topBarHeight - ctaZoneHeight;

    // Calculate heights based on number of cards (from design brief)
    final heights = _calculateHeights(totalCards, availableHeight);
    focusedHeight = heights['focused']!;
    compressedHeight = heights['compressed']!;
  }

  /// Create from actual available height (no subtractions needed)
  LiquidFocusScrollController.fromAvailable({
    required this.totalCards,
    required this.availableHeight,
  })  : viewportHeight = availableHeight,
        topBarHeight = 0,
        ctaZoneHeight = 0 {
    final heights = _calculateHeights(totalCards, availableHeight);
    focusedHeight = heights['focused']!;
    compressedHeight = heights['compressed']!;
  }

  /// Calculate focus progress for a card based on scroll position
  /// Returns 0.0 (fully compressed) to 1.0 (fully focused)
  double getFocusProgress(double scrollOffset, int cardIndex) {
    // Calculate card's center position
    final cardTop = cardIndex * compressedHeight;
    final cardCenter = cardTop + (compressedHeight / 2);

    // Calculate viewport center (relative to scroll)
    final viewportCenter = scrollOffset + (availableHeight / 2);

    // Calculate distance from center
    final distance = (cardCenter - viewportCenter).abs();
    final maxDistance = availableHeight / 2;

    // Normalize to 0-1 (closer to center = higher value)
    final normalizedDistance = (distance / maxDistance).clamp(0.0, 1.0);
    final focusProgress = 1.0 - normalizedDistance;

    // Apply easeOutQuint curve for smooth animation
    return _easeOutQuint(focusProgress);
  }

  /// Get interpolated card height based on focus progress
  double getCardHeight(double focusProgress) {
    return compressedHeight + (focusedHeight - compressedHeight) * focusProgress;
  }

  /// Get interpolated opacity for card content
  double getContentOpacity(double focusProgress) {
    // Content fades in when focused
    return 0.6 + (0.4 * focusProgress);
  }

  /// Get interpolated scale for card elements
  double getElementScale(double focusProgress) {
    return 0.85 + (0.15 * focusProgress);
  }

  // Responsive height caps
  static const double _maxFocusedHeight = 500.0;
  static const double _minCompressedHeight = 56.0;

  /// Calculate focused and compressed heights based on card count
  Map<String, double> _calculateHeights(int count, double availableHeight) {
    // Base ratios from design brief
    late double focusedPct;
    late double compressedPct;

    switch (count) {
      case 1:
        focusedPct = 1.0;
        compressedPct = 0.0;
        break;
      case 2:
        focusedPct = 0.72;
        compressedPct = 0.28;
        break;
      case 3:
        focusedPct = 0.60;
        compressedPct = 0.20;
        break;
      case 4:
        focusedPct = 0.55;
        compressedPct = 0.15;
        break;
      case 5:
        focusedPct = 0.70;
        compressedPct = 0.075;
        break;
      default:
        focusedPct = 0.50;
        compressedPct = 0.15;
    }

    var focused = availableHeight * focusedPct;
    var compressed = availableHeight * compressedPct;
    final otherCards = count - 1;

    // Enforce minimum compressed height for touch targets
    if (compressed < _minCompressedHeight && otherCards > 0) {
      compressed = _minCompressedHeight;
      focused = availableHeight - (compressed * otherCards);
    }

    // Cap focused height on tall viewports
    if (focused > _maxFocusedHeight && otherCards > 0) {
      focused = _maxFocusedHeight;
      compressed = (availableHeight - focused) / otherCards;
    }

    return {
      'focused': focused,
      'compressed': compressed,
    };
  }

  /// easeOutQuint: 1 - pow(1 - t, 5)
  double _easeOutQuint(double t) {
    return 1 - math.pow(1 - t, 5).toDouble();
  }
}
