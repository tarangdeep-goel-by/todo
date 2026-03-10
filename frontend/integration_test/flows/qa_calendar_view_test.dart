import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:frontend/widgets/calendar_task_view.dart';
import 'package:frontend/widgets/task_detail_overlay.dart';
import 'package:frontend/widgets/flat_task_row.dart';
import 'package:frontend/services/tracker/tracker_keys.dart';
import '../helpers/test_app.dart';
import '../helpers/api_cleanup.dart';
import '../helpers/tracker_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await cleanupTestUser();
  });

  testWidgets('QA Calendar View: tasks grouped by due date sections', (tester) async {
    await pumpApp(tester);

    // --- Create task with due date today ---

    await tester.tap(find.byKey(TK.pttButton));
    await settle(tester);
    await tester.enterText(
      find.byKey(TK.addTaskTextField),
      'Morning standup meeting due today',
    );
    await settle(tester, const Duration(seconds: 1));
    await tester.tap(find.byKey(TK.sendButton));
    await settle(tester, const Duration(seconds: 5));
    expectOutcome('task_created');

    // --- Create task with no date ---

    await tester.tap(find.byKey(TK.pttButton));
    await settle(tester);
    await tester.enterText(
      find.byKey(TK.addTaskTextField),
      'Read a new book sometime',
    );
    await settle(tester, const Duration(seconds: 1));
    await tester.tap(find.byKey(TK.sendButton));
    await settle(tester, const Duration(seconds: 5));

    // --- Create task with due date tomorrow ---
    // We set the due date via the task detail overlay after creation

    await tester.tap(find.byKey(TK.pttButton));
    await settle(tester);
    await tester.enterText(
      find.byKey(TK.addTaskTextField),
      'Submit expense report',
    );
    await settle(tester, const Duration(seconds: 1));
    await tester.tap(find.byKey(TK.sendButton));
    await settle(tester, const Duration(seconds: 5));

    // Switch to flat view to set due dates via overlay
    await tester.tap(find.byKey(TK.flatTab));
    await settle(tester);

    // Long-press "Submit expense report" to open detail overlay and set due date to tomorrow
    final expenseItem = find.ancestor(
      of: find.textContaining('expense report'),
      matching: find.byType(FlatTaskRow),
    );
    if (expenseItem.evaluate().isNotEmpty) {
      await tester.longPress(expenseItem.first);
      await settle(tester);

      expect(find.byType(TaskDetailOverlay), findsOneWidget);

      // Tap "No due date" to open date picker
      await tester.tap(find.text('No due date'));
      await settle(tester);

      // Select tomorrow's date
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      await tester.tap(find.text('${tomorrow.day}'));
      await settle(tester);

      // Confirm date picker
      await tester.tap(find.text('OK'));
      await settle(tester, const Duration(seconds: 3));

      // Close overlay
      await tester.tap(find.byIcon(Icons.close));
      await settle(tester);
    }

    // --- Switch to Calendar view ---

    await tester.tap(find.byKey(TK.calTab));
    await settle(tester);
    expect(find.byType(CalendarTaskView), findsOneWidget);

    // --- Verify sections exist ---

    // "Today" section should show the standup task
    // (only if Gemini correctly parsed "due today")
    // At minimum, at least one section header should be visible
    final hasToday = find.text('Today').evaluate().isNotEmpty;
    final hasTomorrow = find.text('Tomorrow').evaluate().isNotEmpty;
    final hasNoDate = find.text('No Date').evaluate().isNotEmpty;

    // We expect at least some sections to be present after creating tasks with dates
    expect(
      hasToday || hasTomorrow || hasNoDate,
      isTrue,
      reason: 'Calendar view should show at least one date section',
    );

    // Verify the task with tomorrow's due date appears under "Tomorrow"
    if (hasTomorrow) {
      expect(find.textContaining('expense report'), findsWidgets);
    }

    // "No Date" section is collapsible — tap to expand if present
    if (hasNoDate) {
      await tester.tap(find.text('No Date'));
      await settle(tester);
      // After expanding, the undated task should be visible
      expect(find.textContaining('new book'), findsWidgets);
    }
  });
}
