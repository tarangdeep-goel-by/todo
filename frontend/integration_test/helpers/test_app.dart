import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/main.dart';

/// Pumps the real AmbleApp with ProviderScope for integration tests.
/// Auth is bypassed via --dart-define=TEST_MODE=true at build time.
Future<void> pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(
    const ProviderScope(
      child: AmbleApp(),
    ),
  );
  // Use pump() with duration instead of pumpAndSettle() because the app has
  // infinite animations (CoachingHint, VoiceHintPulse, FlatViewNudge) that
  // cause pumpAndSettle to time out.
  await tester.pump(const Duration(seconds: 3));
}

/// Settle with a timeout — pumps frames for [duration] then returns.
/// Use this instead of pumpAndSettle() when infinite animations are present.
Future<void> settle(WidgetTester tester, [Duration duration = const Duration(seconds: 2)]) async {
  // Pump multiple frames over the duration to let async work complete
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
