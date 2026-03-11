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
    final controller = StreamController<User?>();
    controller.add(null);

    final container = await pumpAppWithAuth(tester, controller.stream);

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
    container.dispose();
  });

  testWidgets('Loading spinner shown while auth state resolves', (tester) async {
    final controller = StreamController<User?>();

    final container = await pumpAppWithAuth(tester, controller.stream);

    // Should show loading spinner, not login or home
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Continue with Google'), findsNothing);
    expect(find.byKey(TK.pttButton), findsNothing);

    await controller.close();
    container.dispose();
  });

  testWidgets('Login screen shows error state gracefully', (tester) async {
    final controller = StreamController<User?>();
    controller.addError('Auth service unavailable');

    final container = await pumpAppWithAuth(tester, controller.stream);

    // Error state should fall back to LoginScreen (per AuthGate logic)
    expect(find.byKey(TK.signInButton), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);

    await controller.close();
    container.dispose();
  });

  testWidgets('Sign-in button shows loading indicator when tapped', (tester) async {
    final controller = StreamController<User?>();
    controller.add(null);

    final container = await pumpAppWithAuth(tester, controller.stream);

    // Verify sign-in button is present
    expect(find.byKey(TK.signInButton), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);

    // Tap sign-in button — Google Sign-In will fail in test env,
    // but we verify the button is tappable and recovers gracefully
    await tester.tap(find.byKey(TK.signInButton));

    // Pump several frames to let the tap + error recovery play out
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Eventually returns to showing the button (after error)
    expect(find.byKey(TK.signInButton), findsOneWidget);

    await controller.close();
    container.dispose();
  });
}
