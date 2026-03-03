import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/config/spacing.dart';

void main() {
  group('AppSpacing base values', () {
    test('unit equals 8.0', () {
      expect(AppSpacing.unit, 8.0);
    });

    test('all base values are positive', () {
      expect(AppSpacing.xs, greaterThan(0));
      expect(AppSpacing.sm, greaterThan(0));
      expect(AppSpacing.md, greaterThan(0));
      expect(AppSpacing.lg, greaterThan(0));
      expect(AppSpacing.xl, greaterThan(0));
      expect(AppSpacing.xxl, greaterThan(0));
    });

    test('logical ordering xs < sm < md < lg < xl < xxl', () {
      expect(AppSpacing.xs, lessThan(AppSpacing.sm));
      expect(AppSpacing.sm, lessThan(AppSpacing.md));
      expect(AppSpacing.md, lessThan(AppSpacing.lg));
      expect(AppSpacing.lg, lessThan(AppSpacing.xl));
      expect(AppSpacing.xl, lessThan(AppSpacing.xxl));
    });
  });

  group('AppSpacing component values', () {
    test('cardMargin is positive', () {
      expect(AppSpacing.cardMargin, greaterThan(0));
    });

    test('topBarHeight is positive', () {
      expect(AppSpacing.topBarHeight, greaterThan(0));
    });

    test('bottomNavHeight is positive', () {
      expect(AppSpacing.bottomNavHeight, greaterThan(0));
    });
  });

  group('AppSpacing radius ordering', () {
    test('radiusNone < radiusSm < radiusMd < radiusLg < radiusPill', () {
      expect(AppSpacing.radiusNone, lessThan(AppSpacing.radiusSm));
      expect(AppSpacing.radiusSm, lessThan(AppSpacing.radiusMd));
      expect(AppSpacing.radiusMd, lessThan(AppSpacing.radiusLg));
      expect(AppSpacing.radiusLg, lessThan(AppSpacing.radiusPill));
    });
  });
}
