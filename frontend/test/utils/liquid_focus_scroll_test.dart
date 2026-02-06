import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/utils/liquid_focus_scroll.dart';

void main() {
  const viewportHeight = 800.0;
  const topBar = 48.0;
  const ctaZone = 120.0;
  // availableHeight = 800 - 48 - 120 = 632

  group('Constructor height calculations', () {
    test('2 cards', () {
      final c = LiquidFocusScrollController(
        totalCards: 2, viewportHeight: viewportHeight,
        topBarHeight: topBar, ctaZoneHeight: ctaZone,
      );
      expect(c.focusedHeight, greaterThan(0));
      expect(c.compressedHeight, greaterThan(0));
      expect(c.focusedHeight, greaterThan(c.compressedHeight));
    });

    test('3 cards', () {
      final c = LiquidFocusScrollController(
        totalCards: 3, viewportHeight: viewportHeight,
        topBarHeight: topBar, ctaZoneHeight: ctaZone,
      );
      expect(c.focusedHeight, greaterThan(c.compressedHeight));
    });

    test('4 cards', () {
      final c = LiquidFocusScrollController(
        totalCards: 4, viewportHeight: viewportHeight,
        topBarHeight: topBar, ctaZoneHeight: ctaZone,
      );
      expect(c.focusedHeight, greaterThan(c.compressedHeight));
    });

    test('5 cards', () {
      final c = LiquidFocusScrollController(
        totalCards: 5, viewportHeight: viewportHeight,
        topBarHeight: topBar, ctaZoneHeight: ctaZone,
      );
      expect(c.compressedHeight, greaterThanOrEqualTo(56.0)); // min touch target
    });

    test('default (6+ cards)', () {
      final c = LiquidFocusScrollController(
        totalCards: 7, viewportHeight: viewportHeight,
        topBarHeight: topBar, ctaZoneHeight: ctaZone,
      );
      expect(c.focusedHeight, greaterThan(0));
      expect(c.compressedHeight, greaterThan(0));
    });
  });

  group('Height caps', () {
    test('min compressed height enforced', () {
      final c = LiquidFocusScrollController(
        totalCards: 10, viewportHeight: 400,
        topBarHeight: 0, ctaZoneHeight: 0,
      );
      expect(c.compressedHeight, greaterThanOrEqualTo(56.0));
    });

    test('max focused height capped', () {
      final c = LiquidFocusScrollController(
        totalCards: 2, viewportHeight: 2000,
        topBarHeight: 0, ctaZoneHeight: 0,
      );
      expect(c.focusedHeight, lessThanOrEqualTo(500.0));
    });
  });

  group('getFocusProgress', () {
    test('center card returns ~1.0', () {
      final c = LiquidFocusScrollController.fromAvailable(
        totalCards: 3, availableHeight: 600,
      );
      // Card at center of viewport
      final progress = c.getFocusProgress(0, 1); // middle card
      expect(progress, greaterThan(0.5));
    });

    test('edge card returns ~0.0', () {
      final c = LiquidFocusScrollController.fromAvailable(
        totalCards: 5, availableHeight: 600,
      );
      // First card when scrolled to bottom
      final progress = c.getFocusProgress(300, 0);
      expect(progress, lessThan(0.5));
    });
  });

  group('Interpolation', () {
    test('cardHeight interpolates between compressed and focused', () {
      final c = LiquidFocusScrollController.fromAvailable(
        totalCards: 3, availableHeight: 600,
      );
      final atZero = c.getCardHeight(0.0);
      final atOne = c.getCardHeight(1.0);
      final atHalf = c.getCardHeight(0.5);
      expect(atZero, c.compressedHeight);
      expect(atOne, c.focusedHeight);
      expect(atHalf, greaterThan(atZero));
      expect(atHalf, lessThan(atOne));
    });

    test('contentOpacity ranges from 0.6 to 1.0', () {
      final c = LiquidFocusScrollController.fromAvailable(
        totalCards: 3, availableHeight: 600,
      );
      expect(c.getContentOpacity(0.0), closeTo(0.6, 0.01));
      expect(c.getContentOpacity(1.0), closeTo(1.0, 0.01));
    });
  });
}
