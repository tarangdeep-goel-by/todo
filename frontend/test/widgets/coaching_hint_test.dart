import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/widgets/coaching_hint.dart';
import '../helpers/test_helpers.dart';

void main() {
  group('CoachingHint', () {
    testWidgets('shows initial hint text', (tester) async {
      await tester.pumpWidget(buildTestApp(const CoachingHint()));

      expect(find.textContaining('Add buy groceries to home'), findsOneWidget);
    });

    testWidgets('hint text changes after 4 seconds', (tester) async {
      await tester.pumpWidget(buildTestApp(const CoachingHint()));

      // Timer fires at 4s, then AnimatedSwitcher needs time to complete transition
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      // Second hint should now be visible
      expect(find.textContaining('Schedule standup for tomorrow'), findsOneWidget);
    });

    testWidgets('widget uses AnimatedSwitcher', (tester) async {
      await tester.pumpWidget(buildTestApp(const CoachingHint()));

      expect(find.byType(AnimatedSwitcher), findsOneWidget);
    });
  });
}
