import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/widgets/ptt_input_overlay.dart';
import 'package:frontend/providers/api_provider.dart';
import 'package:frontend/providers/recording_provider.dart';
import '../helpers/test_helpers.dart';

void main() {
  late MockApiService mockApi;

  setUp(() {
    mockApi = MockApiService();
  });

  Widget buildOverlay({List<Override> extraOverrides = const []}) {
    return ProviderScope(
      overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
        ...extraOverrides,
      ],
      child: MaterialApp(
        home: Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) => const PttInputOverlay(),
          ),
        ),
      ),
    );
  }

  /// Suppress overflow errors from fallback font width differences in test.
  Future<void> pumpIgnoringOverflow(WidgetTester tester, Widget widget) async {
    final oldHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exception.toString().contains('overflowed')) return;
      oldHandler?.call(details);
    };
    await tester.pumpWidget(widget);
    addTearDown(() => FlutterError.onError = oldHandler);
  }

  group('Idle state', () {
    testWidgets('renders nothing when idle', (tester) async {
      await pumpIgnoringOverflow(tester, buildOverlay());
      expect(find.byType(PttInputOverlay), findsOneWidget);
      // Should render SizedBox.shrink — no text field, no dots
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(AnimatedContainer), findsNothing);
    });
  });

  group('Typing state', () {
    testWidgets('shows TextField when typing', (tester) async {
      await pumpIgnoringOverflow(
        tester,
        buildOverlay(extraOverrides: [
          recordingStateProvider.overrideWith((ref) => RecordingState.typing),
        ]),
      );
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('shows close and send buttons in typing mode', (tester) async {
      await pumpIgnoringOverflow(
        tester,
        buildOverlay(extraOverrides: [
          recordingStateProvider.overrideWith((ref) => RecordingState.typing),
        ]),
      );
      await tester.pump();
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    });
  });

  group('RecordingState enum', () {
    test('has typing state', () {
      expect(RecordingState.values, contains(RecordingState.typing));
    });

    test('has all expected states', () {
      expect(RecordingState.values, [
        RecordingState.idle,
        RecordingState.listening,
        RecordingState.processing,
        RecordingState.typing,
      ]);
    });
  });
}
