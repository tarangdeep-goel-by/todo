import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/screens/login_screen.dart';
import 'package:frontend/widgets/grain_texture_painter.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('LoginScreen', () {
    testWidgets('shows Amble brand text', (tester) async {
      await tester.pumpWidget(buildTestApp(const LoginScreen()));
      await tester.pump(const Duration(milliseconds: 1300));
      expect(find.text('Amble'), findsOneWidget);
    });

    testWidgets('shows tagline', (tester) async {
      await tester.pumpWidget(buildTestApp(const LoginScreen()));
      await tester.pump(const Duration(milliseconds: 1300));
      expect(find.text('Your voice, organized.'), findsOneWidget);
    });

    testWidgets('shows teaching points', (tester) async {
      await tester.pumpWidget(buildTestApp(const LoginScreen()));
      await tester.pump(const Duration(milliseconds: 1300));
      expect(find.text('Say it, done.'), findsOneWidget);
      expect(find.text('AI handles the rest'), findsOneWidget);
    });

    testWidgets('shows domain color dots', (tester) async {
      await tester.pumpWidget(buildTestApp(const LoginScreen()));
      await tester.pump(const Duration(milliseconds: 1300));
      // 8 domain dots — Container with width 8, height 8
      final circleDots = find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final dec = w.decoration;
        if (dec is! BoxDecoration) return false;
        if (dec.shape != BoxShape.circle) return false;
        final c = w.constraints;
        return c != null && c.maxWidth == 8 && c.maxHeight == 8;
      });
      expect(circleDots, findsNWidgets(8));
    });

    testWidgets('shows Continue with Google button', (tester) async {
      await tester.pumpWidget(buildTestApp(const LoginScreen()));
      await tester.pump(const Duration(milliseconds: 1300));
      expect(find.text('Continue with Google'), findsOneWidget);
    });

    testWidgets('shows footer text', (tester) async {
      await tester.pumpWidget(buildTestApp(const LoginScreen()));
      await tester.pump(const Duration(milliseconds: 1300));
      expect(find.text('Sign in to get started'), findsOneWidget);
    });

    testWidgets('does not have email or password fields', (tester) async {
      await tester.pumpWidget(buildTestApp(const LoginScreen()));
      await tester.pump(const Duration(milliseconds: 1300));
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('renders GrainTexturePainter', (tester) async {
      await tester.pumpWidget(buildTestApp(const LoginScreen()));
      await tester.pump(const Duration(milliseconds: 1300));
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is GrainTexturePainter,
        ),
        findsOneWidget,
      );
    });
  });
}
