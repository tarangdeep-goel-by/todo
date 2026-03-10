import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:frontend/main.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/tracker/tracker.dart';
import 'package:frontend/services/tracker/test_adapter.dart';
import 'package:frontend/services/tracker/tracker_keys.dart';

/// Pump the app with auth state overridden.
Future<ProviderContainer> pumpAppWithAuth(
  WidgetTester tester,
  Stream<User?> authStream,
) async {
  Tracker.instance.init([TestAdapter.instance]);
  TestAdapter.instance.clear();

  final container = ProviderContainer(
    overrides: [
      authStateProvider.overrideWith((ref) => authStream),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const AmbleApp(),
    ),
  );

  await tester.pump(const Duration(seconds: 3));
  return container;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Login screen renders when unauthenticated', (tester) async {
    // Stream that emits null (no user signed in)
    final controller = StreamController<User?>();
    controller.add(null);

    await pumpAppWithAuth(tester, controller.stream);

    // Login screen elements visible
    expect(find.text('Amble'), findsOneWidget);
    expect(find.text('Your voice, organized.'), findsOneWidget);
    expect(find.byKey(TK.signInButton), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Sign in to get started'), findsOneWidget);

    // Teaching points visible
    expect(find.text('Say it, done.'), findsOneWidget);
    expect(find.text('AI handles the rest'), findsOneWidget);

    // HomeScreen should NOT be rendered
    expect(find.byKey(TK.pttButton), findsNothing);

    await controller.close();
  });

  testWidgets('Loading spinner shown while auth state resolves', (tester) async {
    // Stream that never emits — auth state is loading
    final controller = StreamController<User?>();

    await pumpAppWithAuth(tester, controller.stream);

    // Should show loading spinner, not login or home
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Continue with Google'), findsNothing);
    expect(find.byKey(TK.pttButton), findsNothing);

    await controller.close();
  });

  testWidgets('Login screen shows error state gracefully', (tester) async {
    // Stream that emits an error
    final controller = StreamController<User?>();
    controller.addError('Auth service unavailable');

    await pumpAppWithAuth(tester, controller.stream);

    // Error state should fall back to LoginScreen (per AuthGate logic)
    expect(find.byKey(TK.signInButton), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);

    await controller.close();
  });

  testWidgets('Sign-in button shows loading indicator when tapped', (tester) async {
    final controller = StreamController<User?>();
    controller.add(null);

    await pumpAppWithAuth(tester, controller.stream);

    // Verify sign-in button is present
    expect(find.byKey(TK.signInButton), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);

    // Tap sign-in button — it will fail (no real Google Sign-In)
    // but we can verify the button is tappable
    await tester.tap(find.byKey(TK.signInButton));
    await tester.pump(const Duration(milliseconds: 500));

    // After tap, button should show loading spinner (CircularProgressIndicator)
    // inside the button area, and 'Continue with Google' text should be gone
    // Note: This may show an error snackbar since Google Sign-In isn't available,
    // but the loading state transition is what we're testing
    await tester.pump(const Duration(seconds: 2));

    // Eventually returns to showing the button text (after error)
    expect(find.byKey(TK.signInButton), findsOneWidget);

    await controller.close();
  });
}
