import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/widgets/view_toggle.dart';
import 'package:frontend/providers/view_mode_provider.dart';

void main() {
  Widget buildToggle({ViewMode? initialMode}) {
    return ProviderScope(
      overrides: [
        if (initialMode != null)
          viewModeProvider.overrideWith((ref) => initialMode),
      ],
      child: const MaterialApp(
        home: Scaffold(body: ViewToggle()),
      ),
    );
  }

  group('ViewToggle', () {
    testWidgets('renders Node and Flat text', (tester) async {
      await tester.pumpWidget(buildToggle());

      expect(find.text('Node'), findsOneWidget);
      expect(find.text('Flat'), findsOneWidget);
    });

    testWidgets('renders calendar_today icon', (tester) async {
      await tester.pumpWidget(buildToggle());

      expect(find.byIcon(Icons.calendar_today), findsOneWidget);
    });

    testWidgets('tapping Flat sets viewMode to flat', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: ViewToggle()),
          ),
        ),
      );

      await tester.tap(find.text('Flat'));
      await tester.pump();

      expect(container.read(viewModeProvider), ViewMode.flat);
    });

    testWidgets('tapping calendar icon sets viewMode to calendar',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: ViewToggle()),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.calendar_today));
      await tester.pump();

      expect(container.read(viewModeProvider), ViewMode.calendar);
    });

    testWidgets('defaults to node mode', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: ViewToggle()),
          ),
        ),
      );

      expect(container.read(viewModeProvider), ViewMode.node);
    });

    testWidgets('has AnimatedPositioned for sliding indicator', (tester) async {
      await tester.pumpWidget(buildToggle());

      expect(find.byType(AnimatedPositioned), findsOneWidget);
    });
  });
}
