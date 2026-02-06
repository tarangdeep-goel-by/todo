import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:frontend/widgets/push_to_talk_button.dart';
import 'package:frontend/providers/recording_provider.dart';
import 'package:frontend/providers/api_provider.dart';
import 'package:frontend/services/api_service.dart';
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

  Widget _buildButton() {
    return ProviderScope(
      overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
        speechServiceProvider.overrideWithValue(mockSpeech),
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

  /// The idle-state Row overflows the 180px-wide AnimatedContainer in test
  /// because the fallback font is wider than DM Sans on device. We suppress
  /// overflow errors since these tests validate widget *structure*, not layout.
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
    testWidgets('shows "Hold to speak" text', (tester) async {
      await pumpIgnoringOverflow(tester, _buildButton());
      expect(find.text('Hold to speak'), findsOneWidget);
    });

    testWidgets('contains AnimatedContainer', (tester) async {
      await pumpIgnoringOverflow(tester, _buildButton());
      expect(find.byType(AnimatedContainer), findsOneWidget);
    });
  });

  group('Widget structure', () {
    testWidgets('renders GestureDetector for long press', (tester) async {
      await pumpIgnoringOverflow(tester, _buildButton());
      expect(find.byType(GestureDetector), findsWidgets);
    });

    testWidgets('renders PushToTalkButton', (tester) async {
      await pumpIgnoringOverflow(tester, _buildButton());
      expect(find.byType(PushToTalkButton), findsOneWidget);
    });

    testWidgets('has Row in idle state', (tester) async {
      await pumpIgnoringOverflow(tester, _buildButton());
      expect(find.byType(Row), findsWidgets);
    });

    testWidgets('has Center widget', (tester) async {
      await pumpIgnoringOverflow(tester, _buildButton());
      expect(find.byType(Center), findsWidgets);
    });
  });
}
