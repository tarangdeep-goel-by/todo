import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/widgets/top_bar.dart';
import 'package:frontend/config/spacing.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('TopBar', () {
    testWidgets('finds text Amble', (tester) async {
      await tester.pumpWidget(buildTestApp(const TopBar()));
      expect(find.text('Amble'), findsOneWidget);
    });

    testWidgets('has correct height container', (tester) async {
      await tester.pumpWidget(buildTestApp(const TopBar()));

      final box = tester.renderObject<RenderBox>(find.byType(Container).first);
      expect(box.size.height, AppSpacing.topBarHeight);
    });

    testWidgets('shows logout icon', (tester) async {
      await tester.pumpWidget(buildTestApp(const TopBar()));
      expect(find.byIcon(Icons.logout_rounded), findsOneWidget);
    });

    testWidgets('tapping logout shows confirmation dialog', (tester) async {
      await tester.pumpWidget(buildTestApp(const TopBar()));
      await tester.tap(find.byIcon(Icons.logout_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Sign out?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
    });

    testWidgets('cancel dismisses dialog', (tester) async {
      await tester.pumpWidget(buildTestApp(const TopBar()));
      await tester.tap(find.byIcon(Icons.logout_rounded));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Sign out?'), findsNothing);
    });
  });
}
