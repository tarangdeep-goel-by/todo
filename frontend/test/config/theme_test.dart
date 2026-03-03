import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/config/theme.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('DomainColors.palettes', () {
    test('has length 5', () {
      expect(DomainColors.palettes, hasLength(5));
    });
  });

  group('DomainColors.byIndex', () {
    test('returns palette with given name', () {
      final palette = DomainColors.byIndex(0, 'Work');
      expect(palette.name, 'Work');
    });

    test('wraps around with modulo (index 5 == index 0 primary)', () {
      final palette0 = DomainColors.byIndex(0, 'A');
      final palette5 = DomainColors.byIndex(5, 'B');
      expect(palette5.primary, palette0.primary);
    });
  });

  group('DomainColors.getDomain', () {
    test('finds by lowercase key in paletteMap', () {
      final paletteMap = createTestPaletteMap();
      final result = DomainColors.getDomain('Work', true, paletteMap);
      expect(result.name, 'Work');
    });

    test('falls back to hash-based index without paletteMap', () {
      final result = DomainColors.getDomain('SomeCategory', true);
      expect(result.name, 'SomeCategory');
      // Should be one of the 5 palettes (by primary color)
      final paletteColors =
          DomainColors.palettes.map((p) => p.primary).toList();
      expect(paletteColors, contains(result.primary));
    });
  });

  group('DomainPalette.withName', () {
    test('creates copy preserving primary color', () {
      final original = DomainColors.palettes[0];
      final copy = original.withName('NewName');
      expect(copy.name, 'NewName');
      expect(copy.primary, original.primary);
      expect(copy.darkShade, original.darkShade);
      expect(copy.surface, original.surface);
    });
  });

  group('AppColors', () {
    test('darkBg is not null', () {
      expect(AppColors.darkBg, isNotNull);
    });

    test('darkText is not null', () {
      expect(AppColors.darkText, isNotNull);
    });

    test('overdue is not null', () {
      expect(AppColors.overdue, isNotNull);
    });
  });
}
