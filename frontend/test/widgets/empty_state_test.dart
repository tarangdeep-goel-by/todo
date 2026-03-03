import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/widgets/empty_state.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('EmptyState', () {
    testWidgets('basic: renders message text', (tester) async {
      await tester.pumpWidget(
        buildTestApp(const EmptyState(message: 'No items found')),
      );
      expect(find.text('No items found'), findsOneWidget);
    });

    testWidgets('with icon: renders Icon widget', (tester) async {
      await tester.pumpWidget(
        buildTestApp(const EmptyState(message: 'Empty', icon: Icons.inbox)),
      );
      expect(find.byIcon(Icons.inbox), findsOneWidget);
    });

    testWidgets('rich mode: renders title text', (tester) async {
      await tester.pumpWidget(
        buildTestApp(const EmptyState(
          message: 'Speak a task',
          title: 'Your world, organized',
        )),
      );
      expect(find.text('Your world, organized'), findsOneWidget);
    });

    testWidgets('rich mode: renders example strings with quote marks',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(const EmptyState(
          message: 'Try saying:',
          title: 'Get started',
          examples: ['Buy groceries', 'Walk the dog'],
        )),
      );
      expect(find.text('Buy groceries'), findsOneWidget);
      expect(find.text('Walk the dog'), findsOneWidget);
      // Left double quotation mark used in example rows
      expect(find.text('\u201C'), findsNWidgets(2));
    });

    testWidgets('with onRetry: renders Retry button and calls callback on tap',
        (tester) async {
      var retryCalled = false;
      await tester.pumpWidget(
        buildTestApp(EmptyState(
          message: 'Error occurred',
          onRetry: () => retryCalled = true,
        )),
      );
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retryCalled, isTrue);
    });

    testWidgets(
        'with onAction: renders actionLabel button and calls callback on tap',
        (tester) async {
      var actionCalled = false;
      await tester.pumpWidget(
        buildTestApp(EmptyState(
          message: 'No domains',
          title: 'Setup',
          actionLabel: 'Add Domain',
          onAction: () => actionCalled = true,
        )),
      );
      expect(find.text('Add Domain'), findsOneWidget);
      await tester.tap(find.text('Add Domain'));
      expect(actionCalled, isTrue);
    });

    testWidgets('without optional fields: no title, no examples, no action button',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(const EmptyState(message: 'Just a message')),
      );
      expect(find.text('Just a message'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      // No action buttons rendered
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('message textColor is applied', (tester) async {
      await tester.pumpWidget(
        buildTestApp(const EmptyState(
          message: 'Colored text',
          textColor: Colors.red,
        )),
      );
      final textWidget = tester.widget<Text>(find.text('Colored text'));
      // The style uses color.withValues(alpha: 0.6) for non-rich mode
      expect((textWidget.style?.color?.r ?? 0) * 255.0, (Colors.red.withValues(alpha: 0.6).r) * 255.0);
    });
  });
}
