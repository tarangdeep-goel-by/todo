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
    required double availableHeight,
  })  : viewportHeight = availableHeight,
        topBarHeight = 0,
        ctaZoneHeight = 0 {
    this.availableHeight = availableHeight;
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

  /// Calculate focused and compressed heights based on card count
  Map<String, double> _calculateHeights(int count, double availableHeight) {
    // Height allocations from design brief
    switch (count) {
      case 2:
        return {
          'focused': availableHeight * 0.72,
          'compressed': availableHeight * 0.28,
        };
      case 3:
        return {
          'focused': availableHeight * 0.60,
          'compressed': availableHeight * 0.20,
        };
      case 4:
        return {
          'focused': availableHeight * 0.55,
          'compressed': availableHeight * 0.15,
        };
      case 5:
        return {
          'focused': availableHeight * 0.70,
          'compressed': availableHeight * 0.075, // 30% / 4 cards = 7.5% each
        };
      default:
        // Fallback for other counts
        return {
          'focused': availableHeight * 0.50,
          'compressed': availableHeight * 0.15,
        };
    }
  }

  /// easeOutQuint: 1 - pow(1 - t, 5)
  double _easeOutQuint(double t) {
    return 1 - math.pow(1 - t, 5).toDouble();
  }
}
