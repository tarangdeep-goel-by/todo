import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:frontend/widgets/push_to_talk_button.dart';
import 'package:frontend/providers/api_provider.dart';
import 'package:frontend/providers/recording_provider.dart';
import 'package:frontend/services/speech_service.dart';
import '../helpers/test_helpers.dart';

class MockSpeechService extends Mock implements SpeechService {}

void main() {
  late MockApiService mockApi;
  late MockSpeechService mockSpeech;

  setUp(() {
    mockApi = MockApiService();
    mockSpeech = MockSpeechService();
    when(() => mockSpeech.dispose()).thenReturn(null);
  });

  Widget buildButton({List<Override> extraOverrides = const []}) {
    return ProviderScope(
      overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
        speechServiceProvider.overrideWithValue(mockSpeech),
        ...extraOverrides,
      ],
      child: MaterialApp(
        home: Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) => const PushToTalkButton(),
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

  group('Idle state (split pill)', () {
    testWidgets('shows "Type" and "Speak" labels', (tester) async {
      await pumpIgnoringOverflow(tester, buildButton());
      expect(find.text('Type'), findsOneWidget);
      expect(find.text('Speak'), findsOneWidget);
    });

    testWidgets('shows keyboard and mic icons', (tester) async {
      await pumpIgnoringOverflow(tester, buildButton());
      expect(find.byIcon(Icons.keyboard_alt_outlined), findsOneWidget);
      expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
    });

    testWidgets('contains AnimatedContainer', (tester) async {
      await pumpIgnoringOverflow(tester, buildButton());
      expect(find.byType(AnimatedContainer), findsOneWidget);
    });
  });

  group('Widget structure', () {
    testWidgets('renders GestureDetectors for both halves', (tester) async {
      await pumpIgnoringOverflow(tester, buildButton());
      expect(find.byType(GestureDetector), findsWidgets);
    });

    testWidgets('renders PushToTalkButton', (tester) async {
      await pumpIgnoringOverflow(tester, buildButton());
      expect(find.byType(PushToTalkButton), findsOneWidget);
    });

    testWidgets('has Row in idle state', (tester) async {
      await pumpIgnoringOverflow(tester, buildButton());
      expect(find.byType(Row), findsWidgets);
    });

    testWidgets('has Center widget', (tester) async {
      await pumpIgnoringOverflow(tester, buildButton());
      expect(find.byType(Center), findsWidgets);
    });
  });

  group('Typing state', () {
    testWidgets('shows TextField when typing', (tester) async {
      await pumpIgnoringOverflow(
        tester,
        buildButton(extraOverrides: [
          recordingStateProvider.overrideWith((ref) => RecordingState.typing),
        ]),
      );
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('shows close and send buttons in typing mode', (tester) async {
      await pumpIgnoringOverflow(
        tester,
        buildButton(extraOverrides: [
          recordingStateProvider.overrideWith((ref) => RecordingState.typing),
        ]),
      );
      await tester.pump();
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    });
  });

  group('Listening state', () {
    testWidgets('shows stop icon when listening', (tester) async {
      await pumpIgnoringOverflow(
        tester,
        buildButton(extraOverrides: [
          recordingStateProvider.overrideWith((ref) => RecordingState.listening),
        ]),
      );
      await tester.pump();
      expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
    });

    testWidgets('shows "Listening..." text when no transcription', (tester) async {
      await pumpIgnoringOverflow(
        tester,
        buildButton(extraOverrides: [
          recordingStateProvider.overrideWith((ref) => RecordingState.listening),
          transcriptionTextProvider.overrideWith((ref) => ''),
        ]),
      );
      await tester.pump();
      expect(find.text('Listening...'), findsOneWidget);
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
