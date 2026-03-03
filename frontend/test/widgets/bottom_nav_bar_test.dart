import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/widgets/bottom_nav_bar.dart';
import 'package:frontend/providers/view_mode_provider.dart';
import 'package:frontend/providers/recording_provider.dart';
import 'package:frontend/providers/api_provider.dart';
import 'package:frontend/providers/task_store_provider.dart';

import '../helpers/test_helpers.dart';

void main() {
  late MockApiService mockApi;

  setUp(() {
    mockApi = MockApiService();
  });

  Widget buildNavBar({List<Override> extra = const []}) {
    return buildOverlayTestApp(
      const BottomNavBar(),
      overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
        domainPalettesProvider.overrideWithValue(createTestPaletteMap()),
        ...extra,
      ],
    );
  }

  group('BottomNavBar', () {
    testWidgets('renders Home, Flat, Cal, Profile labels', (tester) async {
      await tester.pumpWidget(buildNavBar());
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Flat'), findsOneWidget);
      expect(find.text('Cal'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
    });

    testWidgets('renders Type or talk text', (tester) async {
      await tester.pumpWidget(buildNavBar());
      expect(find.text('Type or talk'), findsOneWidget);
    });

    testWidgets('has mic_rounded icon', (tester) async {
      await tester.pumpWidget(buildNavBar());
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    });

    testWidgets('tapping Home sets viewMode to node', (tester) async {
      final container = ProviderContainer(overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
        domainPalettesProvider.overrideWithValue(createTestPaletteMap()),
        viewModeProvider.overrideWith((ref) => ViewMode.flat),
      ]);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Overlay(
                initialEntries: [
                  OverlayEntry(builder: (_) => const BottomNavBar()),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Home'));
      await tester.pump();

      expect(container.read(viewModeProvider), ViewMode.node);
    });

    testWidgets('tapping Flat sets viewMode to flat', (tester) async {
      final container = ProviderContainer(overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
        domainPalettesProvider.overrideWithValue(createTestPaletteMap()),
      ]);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Overlay(
                initialEntries: [
                  OverlayEntry(builder: (_) => const BottomNavBar()),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Flat'));
      await tester.pump();

      expect(container.read(viewModeProvider), ViewMode.flat);
    });

    testWidgets('tapping Cal sets viewMode to calendar', (tester) async {
      final container = ProviderContainer(overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
        domainPalettesProvider.overrideWithValue(createTestPaletteMap()),
      ]);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Overlay(
                initialEntries: [
                  OverlayEntry(builder: (_) => const BottomNavBar()),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Cal'));
      await tester.pump();

      expect(container.read(viewModeProvider), ViewMode.calendar);
    });

    testWidgets('tapping center PTT button sets recordingState to typing',
        (tester) async {
      final container = ProviderContainer(overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
        domainPalettesProvider.overrideWithValue(createTestPaletteMap()),
      ]);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Overlay(
                initialEntries: [
                  OverlayEntry(builder: (_) => const BottomNavBar()),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Type or talk'));
      await tester.pump();

      expect(container.read(recordingStateProvider), RecordingState.typing);
    });
  });
}
