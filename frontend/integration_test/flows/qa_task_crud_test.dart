import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:frontend/screens/flat_task_view.dart';
import 'package:frontend/widgets/task_item.dart';
import 'package:frontend/services/tracker/tracker_keys.dart';
import '../helpers/test_app.dart';
import '../helpers/api_cleanup.dart';
import '../helpers/tracker_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await cleanupTestUser();
  });

  testWidgets('QA Task CRUD: create, flat view, complete, search', (tester) async {
    await pumpApp(tester);

    // --- Create 3 tasks across different categories ---

    // Task 1: Career category
    await tester.tap(find.byKey(TK.pttButton));
    await settle(tester);
    await tester.enterText(
      find.byKey(TK.addTaskTextField),
      'Prepare quarterly presentation for career',
    );
    await settle(tester, const Duration(seconds: 1));
    await tester.tap(find.byKey(TK.sendButton));
    await settle(tester, const Duration(seconds: 5));
    expectOutcome('task_created');

    // Task 2: Health category
    await tester.tap(find.byKey(TK.pttButton));
    await settle(tester);
    await tester.enterText(
      find.byKey(TK.addTaskTextField),
      'Schedule dentist appointment for health',
    );
    await settle(tester, const Duration(seconds: 1));
    await tester.tap(find.byKey(TK.sendButton));
    await settle(tester, const Duration(seconds: 5));

    // Task 3: Finance category
    await tester.tap(find.byKey(TK.pttButton));
    await settle(tester);
    await tester.enterText(
      find.byKey(TK.addTaskTextField),
      'Review monthly budget for finance',
    );
    await settle(tester, const Duration(seconds: 1));
    await tester.tap(find.byKey(TK.sendButton));
    await settle(tester, const Duration(seconds: 5));

    // --- Switch to flat view, verify all tasks visible ---

    await tester.tap(find.byKey(TK.flatTab));
    await settle(tester);
    expect(find.byType(FlatTaskView), findsOneWidget);

    expect(find.textContaining('quarterly presentation'), findsWidgets);
    expect(find.textContaining('dentist appointment'), findsWidgets);
    expect(find.textContaining('monthly budget'), findsWidgets);

    // --- Complete a task via tap (toggle) ---

    final dentistItem = find.ancestor(
      of: find.textContaining('dentist appointment'),
      matching: find.byType(TaskItem),
    ).first;
    await tester.tap(dentistItem);
    await settle(tester, const Duration(seconds: 3));

    // Verify completed task has strikethrough styling (TextDecoration.lineThrough)
    final completedText = tester.widget<Text>(
      find.descendant(
        of: find.ancestor(
          of: find.textContaining('dentist appointment'),
          matching: find.byType(TaskItem),
        ).first,
        matching: find.textContaining('dentist appointment'),
      ),
    );
    expect(completedText.style?.decoration, TextDecoration.lineThrough);

    // --- Search for a task by name ---

    final searchField = find.widgetWithText(TextField, 'Search tasks...');
    expect(searchField, findsOneWidget);

    await tester.enterText(searchField, 'quarterly');
    await settle(tester, const Duration(seconds: 3));
    expectOutcome('search_performed');

    // Should find the matching task
    expect(find.textContaining('quarterly presentation'), findsWidgets);

    // --- Search with no results ---

    // Clear previous search
    await tester.enterText(searchField, 'xyznonexistenttask');
    await settle(tester, const Duration(seconds: 3));

    // Verify empty state message
    expect(find.text('No matching tasks found.'), findsOneWidget);
  });
}
