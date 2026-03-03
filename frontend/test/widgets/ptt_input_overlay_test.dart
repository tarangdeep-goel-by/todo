import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/widgets/ptt_input_overlay.dart';
import 'package:frontend/providers/recording_provider.dart';
import 'package:frontend/providers/api_provider.dart';
import 'package:frontend/providers/task_store_provider.dart';

import '../helpers/test_helpers.dart';

void main() {
  late MockApiService mockApi;

  setUp(() {
    mockApi = MockApiService();
  });

  Widget buildOverlay({
    RecordingState initialState = RecordingState.idle,
    List<Override> extra = const [],
  }) {
    return ProviderScope(
      overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
        domainPalettesProvider.overrideWithValue(createTestPaletteMap()),
        recordingStateProvider.overrideWith((ref) => initialState),
        ...extra,
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: PttInputOverlay(),
        ),
      ),
    );
  }

  group('PttInputOverlay', () {
    testWidgets('idle state renders nothing visible', (tester) async {
      await tester.pumpWidget(buildOverlay(initialState: RecordingState.idle));
      expect(find.byType(SizedBox), findsWidgets);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('typing state shows TextField with hint', (tester) async {
      await tester
          .pumpWidget(buildOverlay(initialState: RecordingState.typing));
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('What do you want to do?'), findsOneWidget);
    });

    testWidgets('typing state shows close button', (tester) async {
      await tester
          .pumpWidget(buildOverlay(initialState: RecordingState.typing));
      await tester.pump();
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });

    testWidgets('typing state shows send button', (tester) async {
      await tester
          .pumpWidget(buildOverlay(initialState: RecordingState.typing));
      await tester.pump();
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    });

    testWidgets('processing state shows animated dots', (tester) async {
      await tester
          .pumpWidget(buildOverlay(initialState: RecordingState.processing));
      await tester.pump();

      // Processing content has 3 Containers with BoxShape.circle decoration
      final circleFinder = find.byWidgetPredicate((widget) {
        if (widget is Container && widget.decoration is BoxDecoration) {
          final dec = widget.decoration as BoxDecoration;
          return dec.shape == BoxShape.circle;
        }
        return false;
      });

      expect(circleFinder, findsNWidgets(3));
    });

    testWidgets('tapping close button resets to idle state', (tester) async {
      final container = ProviderContainer(overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
        domainPalettesProvider.overrideWithValue(createTestPaletteMap()),
        recordingStateProvider.overrideWith((ref) => RecordingState.typing),
      ]);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: PttInputOverlay(),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();

      expect(container.read(recordingStateProvider), RecordingState.idle);
    });
  });
}
