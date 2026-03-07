import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:frontend/screens/flat_task_view.dart';
import 'package:frontend/widgets/filter_sheet.dart';
import 'package:frontend/services/tracker/tracker_keys.dart';
import '../helpers/test_app.dart';
import '../helpers/api_cleanup.dart';
import '../helpers/tracker_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await cleanupTestUser();
  });

  testWidgets('QA Filters: category and priority filtering', (tester) async {
    await pumpApp(tester);

    // --- Create tasks with different categories and priorities ---

    // Task 1: Career, high priority
    await tester.tap(find.byKey(TK.pttButton));
    await settle(tester);
    await tester.enterText(
      find.byKey(TK.addTaskTextField),
      'Finish project proposal for career, high priority',
    );
    await settle(tester, const Duration(seconds: 1));
    await tester.tap(find.byKey(TK.sendButton));
    await settle(tester, const Duration(seconds: 5));
    expectOutcome('task_created');

    // Task 2: Health, low priority
    await tester.tap(find.byKey(TK.pttButton));
    await settle(tester);
    await tester.enterText(
      find.byKey(TK.addTaskTextField),
      'Go for a morning jog for health, low priority',
    );
    await settle(tester, const Duration(seconds: 1));
    await tester.tap(find.byKey(TK.sendButton));
    await settle(tester, const Duration(seconds: 5));

    // Task 3: Finance, medium priority
    await tester.tap(find.byKey(TK.pttButton));
    await settle(tester);
    await tester.enterText(
      find.byKey(TK.addTaskTextField),
      'Pay electricity bill for finance, medium priority',
    );
    await settle(tester, const Duration(seconds: 1));
    await tester.tap(find.byKey(TK.sendButton));
    await settle(tester, const Duration(seconds: 5));

    // --- Switch to flat view ---

    await tester.tap(find.byKey(TK.flatTab));
    await settle(tester);
    expect(find.byType(FlatTaskView), findsOneWidget);

    // Verify all 3 tasks visible initially
    expect(find.textContaining('project proposal'), findsWidgets);
    expect(find.textContaining('morning jog'), findsWidgets);
    expect(find.textContaining('electricity bill'), findsWidgets);

    // --- Open filter sheet via the tune icon ---

    final filterButton = find.byIcon(Icons.tune_rounded);
    expect(filterButton, findsOneWidget);
    await tester.tap(filterButton);
    await settle(tester);

    // Filter sheet should be open
    expect(find.byType(FilterSheet), findsOneWidget);
    expect(find.text('Filters & Sort'), findsOneWidget);

    // --- Apply category filter (CAREER only) ---

    // Category chips are uppercase
    await tester.tap(find.text('CAREER'));
    await settle(tester);

    // Tap "Apply Filters"
    await tester.tap(find.byKey(TK.applyFiltersButton));
    await settle(tester, const Duration(seconds: 2));

    // Verify only career task is visible
    expect(find.textContaining('project proposal'), findsWidgets);
    expect(find.textContaining('morning jog'), findsNothing);
    expect(find.textContaining('electricity bill'), findsNothing);
    expectOutcome('filter_applied');

    // --- Clear filters ---

    // Re-open filter sheet
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await settle(tester);
    expect(find.byType(FilterSheet), findsOneWidget);

    // Tap "Clear All"
    await tester.tap(find.byKey(TK.clearAllButton));
    await settle(tester);

    // Apply (with no filters = show all)
    await tester.tap(find.byKey(TK.applyFiltersButton));
    await settle(tester, const Duration(seconds: 2));

    // All tasks visible again
    expect(find.textContaining('project proposal'), findsWidgets);
    expect(find.textContaining('morning jog'), findsWidgets);
    expect(find.textContaining('electricity bill'), findsWidgets);

    // --- Apply priority filter (HIGH only) ---

    await tester.tap(find.byIcon(Icons.tune_rounded));
    await settle(tester);
    expect(find.byType(FilterSheet), findsOneWidget);

    // Tap HIGH priority chip
    await tester.tap(find.text('HIGH'));
    await settle(tester);

    await tester.tap(find.byKey(TK.applyFiltersButton));
    await settle(tester, const Duration(seconds: 2));

    // Only high-priority task should be visible
    expect(find.textContaining('project proposal'), findsWidgets);
    expect(find.textContaining('morning jog'), findsNothing);
    expect(find.textContaining('electricity bill'), findsNothing);
  });
}
