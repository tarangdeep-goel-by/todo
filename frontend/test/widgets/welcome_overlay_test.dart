import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/widgets/welcome_overlay.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('WelcomeOverlay', () {
    testWidgets('shows Amble text', (tester) async {
      await tester.pumpWidget(
        buildTestApp(WelcomeOverlay(onDismiss: () {})),
      );
      await tester.pumpAndSettle();
      expect(find.text('Amble'), findsOneWidget);
    });

    testWidgets('shows Your voice, organized. text', (tester) async {
      await tester.pumpWidget(
        buildTestApp(WelcomeOverlay(onDismiss: () {})),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your voice, organized.'), findsOneWidget);
    });

    testWidgets('shows teaching point titles', (tester) async {
      await tester.pumpWidget(
        buildTestApp(WelcomeOverlay(onDismiss: () {})),
      );
      await tester.pumpAndSettle();
      expect(find.text('Say it, done.'), findsOneWidget);
      expect(find.text('AI handles the rest'), findsOneWidget);
    });

    testWidgets('shows Get Started button text', (tester) async {
      await tester.pumpWidget(
        buildTestApp(WelcomeOverlay(onDismiss: () {})),
      );
      await tester.pumpAndSettle();
      expect(find.text('Get Started'), findsOneWidget);
    });

    testWidgets('shows I\'ll explore on my own text', (tester) async {
      await tester.pumpWidget(
        buildTestApp(WelcomeOverlay(onDismiss: () {})),
      );
      await tester.pumpAndSettle();
      expect(find.text("I'll explore on my own"), findsOneWidget);
    });

    testWidgets('tapping Get Started triggers onDismiss after animation',
        (tester) async {
      var dismissed = false;

      await tester.pumpWidget(
        buildTestApp(WelcomeOverlay(onDismiss: () => dismissed = true)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Get Started'));
      await tester.pumpAndSettle();

      expect(dismissed, isTrue);
    });

    testWidgets('tapping skip text triggers onDismiss after animation',
        (tester) async {
      var dismissed = false;

      await tester.pumpWidget(
        buildTestApp(WelcomeOverlay(onDismiss: () => dismissed = true)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text("I'll explore on my own"));
      await tester.pumpAndSettle();

      expect(dismissed, isTrue);
    });
  });
}
