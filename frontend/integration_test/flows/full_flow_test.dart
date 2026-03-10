import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:frontend/screens/parent_node_view.dart';
import 'package:frontend/screens/flat_task_view.dart';
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

  testWidgets('Full flow: navigate, create, complete, delete', (tester) async {
    await pumpApp(tester);

    // --- Navigation ---

    expect(find.byType(ParentNodeView), findsOneWidget);

    await tester.tap(find.byKey(TK.flatTab));
    await settle(tester);
    expectTap('flat_tab');
    expect(find.byType(FlatTaskView), findsOneWidget);

    await tester.tap(find.byKey(TK.calTab));
    await settle(tester);
    expectTap('cal_tab');
    expect(find.byType(CalendarTaskView), findsOneWidget);

    await tester.tap(find.byKey(TK.homeTab));
    await settle(tester);
    expectTap('home_tab');
    expect(find.byType(ParentNodeView), findsOneWidget);

    final addOrTalk = find.text('Add or talk');
    final holdToTalk = find.text('Hold to talk');
    expect(
      addOrTalk.evaluate().isNotEmpty || holdToTalk.evaluate().isNotEmpty,
      isTrue,
    );

    // --- Create first task ---

    await tester.tap(find.byKey(TK.pttButton));
    await settle(tester);
    expect(find.text('What needs to be done?'), findsOneWidget);

    await tester.enterText(
      find.byKey(TK.addTaskTextField),
      'Buy groceries for the week',
    );
    await settle(tester, const Duration(seconds: 1));

    await tester.tap(find.byKey(TK.sendButton));
    await settle(tester, const Duration(seconds: 5));

    expect(find.text('What needs to be done?'), findsNothing);
    expectOutcome('task_created');

    // --- Create second task ---

    await tester.tap(find.byKey(TK.pttButton));
    await settle(tester);

    await tester.enterText(
      find.byKey(TK.addTaskTextField),
      'Finish the project report',
    );
    await settle(tester, const Duration(seconds: 1));

    await tester.tap(find.byKey(TK.sendButton));
    await settle(tester, const Duration(seconds: 5));

    // Switch to Flat view — both tasks visible
    await tester.tap(find.byKey(TK.flatTab));
    await settle(tester);
    expect(find.textContaining('Buy groceries'), findsWidgets);
    expect(find.textContaining('project report'), findsWidgets);

    // --- Long press → task detail overlay ---

    // Find a TaskItem containing "Buy groceries"
    final groceryItem = find.ancestor(
      of: find.textContaining('Buy groceries'),
      matching: find.byType(FlatTaskRow),
    ).first;
    await tester.longPress(groceryItem);
    await settle(tester);

    expect(find.byType(TaskDetailOverlay), findsOneWidget);

    // --- Edit task: set high priority ---

    // Tap the priority chip to expand options
    await tester.tap(find.text('No priority'));
    await settle(tester);

    // Select "High" within the overlay
    await tester.tap(find.descendant(
      of: find.byType(TaskDetailOverlay),
      matching: find.text('High'),
    ));
    await settle(tester, const Duration(seconds: 3));

    // --- Edit task: set due date to tomorrow ---

    await tester.tap(find.text('No due date'));
    await settle(tester);

    // Date picker is open — select tomorrow
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    await tester.tap(find.text('${tomorrow.day}'));
    await settle(tester);

    // Confirm the date picker
    await tester.tap(find.text('OK'));
    await settle(tester, const Duration(seconds: 3));

    // Close overlay via the close button
    await tester.tap(find.byIcon(Icons.close));
    await settle(tester);

    // --- Verify on Flat view ---

    // Should show "Due Soon" badge (tomorrow is within 48h)
    expect(find.text('Due Soon'), findsWidgets);
    // Should show "High" priority badge
    expect(find.text('High'), findsWidgets);

    // --- Verify on Node view ---

    await tester.tap(find.byKey(TK.homeTab));
    await settle(tester);
    expect(find.byType(ParentNodeView), findsOneWidget);

    // Domain card shows priority and due date metadata
    expect(find.textContaining('High'), findsWidgets);

    // --- Verify on Calendar view ---

    await tester.tap(find.byKey(TK.calTab));
    await settle(tester);
    expect(find.byType(CalendarTaskView), findsOneWidget);

    // Task should appear under "Tomorrow" section
    expect(find.text('Tomorrow'), findsWidgets);
    expect(find.textContaining('Buy groceries'), findsWidgets);
  });
}
