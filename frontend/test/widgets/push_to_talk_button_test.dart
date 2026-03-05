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
      child: const MaterialApp(
        home: Scaffold(
          body: PttInputOverlay(),
        ),
      ),
    );
  }

  group('Idle state', () {
    testWidgets('renders nothing when idle', (tester) async {
      await tester.pumpWidget(buildOverlay());
      expect(find.byType(PttInputOverlay), findsOneWidget);
      // Should render SizedBox.shrink
      expect(find.byType(TextField), findsNothing);
    });
  });

  group('Processing state', () {
    testWidgets('shows processing dots', (tester) async {
      await tester.pumpWidget(
        buildOverlay(extraOverrides: [
          recordingStateProvider.overrideWith((ref) => RecordingState.processing),
        ]),
      );
      await tester.pump();
      expect(find.byType(AnimatedContainer), findsOneWidget);
      expect(find.byType(AnimatedOpacity), findsNWidgets(3));
    });
  });

  group('RecordingState enum', () {
    test('has all expected states', () {
      expect(RecordingState.values, contains(RecordingState.idle));
      expect(RecordingState.values, contains(RecordingState.listening));
      expect(RecordingState.values, contains(RecordingState.processing));
      expect(RecordingState.values, contains(RecordingState.typing));
    });
  });
}
