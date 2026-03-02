import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/widgets/styled_snackbar.dart';
import 'package:frontend/config/theme.dart';

void main() {
  Widget buildApp({required Widget child}) {
    return ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Overlay(
            initialEntries: [
              OverlayEntry(builder: (_) => child),
            ],
          ),
        ),
      ),
    );
  }

  group('showStyledSnackbar', () {
    testWidgets('shows message text', (tester) async {
      await tester.pumpWidget(buildApp(
        child: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () {
              showStyledSnackbar(context,
                  message: 'Task created', style: SnackbarStyle.success);
            },
            child: const Text('Show'),
          );
        }),
      ));

      await tester.tap(find.text('Show'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Task created'), findsOneWidget);
    });

    testWidgets('shows check icon for success style', (tester) async {
      await tester.pumpWidget(buildApp(
        child: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () {
              showStyledSnackbar(context,
                  message: 'Done', style: SnackbarStyle.success);
            },
            child: const Text('Show'),
          );
        }),
      ));

      await tester.tap(find.text('Show'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('shows error_outline icon for error style', (tester) async {
      await tester.pumpWidget(buildApp(
        child: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () {
              showStyledSnackbar(context,
                  message: 'Failed', style: SnackbarStyle.error);
            },
            child: const Text('Show'),
          );
        }),
      ));

      await tester.tap(find.text('Show'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows info_outline icon for info style', (tester) async {
      await tester.pumpWidget(buildApp(
        child: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () {
              showStyledSnackbar(context,
                  message: 'Info', style: SnackbarStyle.info);
            },
            child: const Text('Show'),
          );
        }),
      ));

      await tester.tap(find.text('Show'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets('auto-dismisses after duration', (tester) async {
      await tester.pumpWidget(buildApp(
        child: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () {
              showStyledSnackbar(context,
                  message: 'Bye',
                  style: SnackbarStyle.info,
                  duration: const Duration(milliseconds: 500));
            },
            child: const Text('Show'),
          );
        }),
      ));

      await tester.tap(find.text('Show'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Bye'), findsOneWidget);

      // Wait for auto-dismiss
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('Bye'), findsNothing);
    });

    testWidgets('returns dismiss callback that removes overlay',
        (tester) async {
      VoidCallback? dismiss;

      await tester.pumpWidget(buildApp(
        child: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () {
              dismiss = showStyledSnackbar(context,
                  message: 'Dismissible',
                  style: SnackbarStyle.info,
                  duration: const Duration(seconds: 30));
            },
            child: const Text('Show'),
          );
        }),
      ));

      await tester.tap(find.text('Show'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Dismissible'), findsOneWidget);

      // Manually dismiss
      dismiss!();
      await tester.pump();
      expect(find.text('Dismissible'), findsNothing);
    });

    testWidgets('accepts domain palette override', (tester) async {
      await tester.pumpWidget(buildApp(
        child: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () {
              showStyledSnackbar(context,
                  message: 'Custom',
                  style: SnackbarStyle.success,
                  domain: DomainColors.personalDark);
            },
            child: const Text('Show'),
          );
        }),
      ));

      await tester.tap(find.text('Show'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Should show the message (palette is used for colors, not testable by text)
      expect(find.text('Custom'), findsOneWidget);
    });
  });
}
