import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/widgets/undo_snackbar.dart';
import 'package:frontend/config/theme.dart';

void main() {
  const domain = DomainColors.workDark;

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

  group('showUndoSnackbar', () {
    testWidgets('shows message text and Undo button', (tester) async {
      await tester.pumpWidget(buildApp(
        child: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () {
              showUndoSnackbar(context,
                  message: 'Completed: Buy milk',
                  domain: domain,
                  onUndo: () {});
            },
            child: const Text('Show'),
          );
        }),
      ));

      await tester.tap(find.text('Show'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Completed: Buy milk'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
    });

    testWidgets('tapping Undo calls onUndo callback', (tester) async {
      bool undoCalled = false;

      await tester.pumpWidget(buildApp(
        child: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () {
              showUndoSnackbar(context,
                  message: 'Done',
                  domain: domain,
                  onUndo: () => undoCalled = true);
            },
            child: const Text('Show'),
          );
        }),
      ));

      await tester.tap(find.text('Show'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Undo'));
      await tester.pump();

      expect(undoCalled, isTrue);
    });

    testWidgets('auto-dismisses after duration', (tester) async {
      await tester.pumpWidget(buildApp(
        child: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () {
              showUndoSnackbar(context,
                  message: 'Auto bye',
                  domain: domain,
                  onUndo: () {},
                  duration: const Duration(milliseconds: 500));
            },
            child: const Text('Show'),
          );
        }),
      ));

      await tester.tap(find.text('Show'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Auto bye'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('Auto bye'), findsNothing);
    });

    testWidgets('returns dismiss callback', (tester) async {
      VoidCallback? dismiss;

      await tester.pumpWidget(buildApp(
        child: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () {
              dismiss = showUndoSnackbar(context,
                  message: 'Manual dismiss',
                  domain: domain,
                  onUndo: () {},
                  duration: const Duration(seconds: 30));
            },
            child: const Text('Show'),
          );
        }),
      ));

      await tester.tap(find.text('Show'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Manual dismiss'), findsOneWidget);

      dismiss!();
      await tester.pump();
      expect(find.text('Manual dismiss'), findsNothing);
    });
  });
}
