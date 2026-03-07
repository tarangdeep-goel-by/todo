import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:frontend/screens/flat_task_view.dart';
import 'package:frontend/screens/archive_screen.dart';
import 'package:frontend/screens/profile_screen.dart';
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

  testWidgets('QA Archive: delete, view archive, restore, permanent delete', (tester) async {
    await pumpApp(tester);

    // --- Create a task ---

    await tester.tap(find.byKey(TK.pttButton));
    await settle(tester);
    await tester.enterText(
      find.byKey(TK.addTaskTextField),
      'Clean the garage this weekend',
    );
    await settle(tester, const Duration(seconds: 1));
    await tester.tap(find.byKey(TK.sendButton));
    await settle(tester, const Duration(seconds: 5));
    expectOutcome('task_created');

    // --- Switch to flat view ---

    await tester.tap(find.byKey(TK.flatTab));
    await settle(tester);
    expect(find.byType(FlatTaskView), findsOneWidget);
    expect(find.textContaining('garage'), findsWidgets);

    // --- Delete (archive) task via left swipe ---

    final garageItem = find.ancestor(
      of: find.textContaining('garage'),
      matching: find.byType(TaskItem),
    ).first;

    // Swipe left (endToStart) to archive
    await tester.drag(garageItem, const Offset(-300, 0));
    await settle(tester, const Duration(seconds: 3));

    // Task should be removed from flat view
    expect(find.textContaining('garage'), findsNothing);

    // --- Navigate to profile -> archive ---

    await tester.tap(find.byKey(TK.profileTab));
    await settle(tester);
    expect(find.byType(ProfileScreen), findsOneWidget);

    // Tap archive link
    await tester.tap(find.byKey(TK.archiveLink));
    await settle(tester, const Duration(seconds: 3));
    expect(find.byType(ArchiveScreen), findsOneWidget);

    // Verify archived task is listed
    expect(find.textContaining('garage'), findsWidgets);

    // --- Restore the task via right swipe ---

    final archivedItem = find.textContaining('garage').first;
    await tester.drag(archivedItem, const Offset(300, 0));
    await settle(tester, const Duration(seconds: 3));

    // Task should be removed from archive
    // (may show empty state or just not find the task)
    expect(find.textContaining('garage'), findsNothing);

    // Go back to flat view to verify task is restored
    // First back from archive
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await settle(tester);
    // Then back from profile
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await settle(tester);

    // Switch to flat view
    await tester.tap(find.byKey(TK.flatTab));
    await settle(tester);
    expect(find.textContaining('garage'), findsWidgets);

    // --- Delete again for permanent delete test ---

    final restoredItem = find.ancestor(
      of: find.textContaining('garage'),
      matching: find.byType(TaskItem),
    ).first;
    await tester.drag(restoredItem, const Offset(-300, 0));
    await settle(tester, const Duration(seconds: 3));

    // Navigate to archive again
    await tester.tap(find.byKey(TK.profileTab));
    await settle(tester);
    await tester.tap(find.byKey(TK.archiveLink));
    await settle(tester, const Duration(seconds: 3));
    expect(find.byType(ArchiveScreen), findsOneWidget);
    expect(find.textContaining('garage'), findsWidgets);

    // --- Permanent delete via left swipe ---

    final archiveItemAgain = find.textContaining('garage').first;
    await tester.drag(archiveItemAgain, const Offset(-300, 0));
    await settle(tester, const Duration(seconds: 1));

    // Confirmation dialog should appear
    expect(find.text('Delete permanently?'), findsOneWidget);

    // Confirm deletion
    await tester.tap(find.text('Delete'));
    await settle(tester, const Duration(seconds: 3));

    // Task should be gone permanently
    expect(find.textContaining('garage'), findsNothing);
  });
}
