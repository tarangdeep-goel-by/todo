import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/config/typography.dart';

void main() {
  group('AppTypography constants', () {
    test('metadata size is 11', () {
      expect(AppTypography.metadata, 11.0);
    });

    test('ctaLabel size is 14', () {
      expect(AppTypography.ctaLabel, 14.0);
    });

    test('domainPill size is 11', () {
      expect(AppTypography.domainPill, 11.0);
    });
  });

  group('AppTypography fluid scale', () {
    testWidgets('domainFocus returns clamped value', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: SizedBox()),
      );
      final context = tester.element(find.byType(SizedBox));
      final size = AppTypography.domainFocus(context);
      expect(size, greaterThanOrEqualTo(36.0));
      expect(size, lessThanOrEqualTo(48.0));
    });

    testWidgets('taskFocus returns clamped value', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: SizedBox()),
      );
      final context = tester.element(find.byType(SizedBox));
      final size = AppTypography.taskFocus(context);
      expect(size, greaterThanOrEqualTo(28.0));
      expect(size, lessThanOrEqualTo(32.0));
    });
  });
}
