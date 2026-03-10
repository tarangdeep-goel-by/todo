import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:frontend/services/tracker/tracker_keys.dart';
import '../helpers/test_app.dart';
import '../helpers/api_cleanup.dart';
import '../helpers/tracker_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await cleanupTestUser();
  });

  testWidgets('Flow 1: Create task via keyboard input', (tester) async {
    // Step 1: Launch app → HomeScreen visible
    await pumpApp(tester);

    // Step 2: Tap the center input pill
    final inputPill = find.byKey(TK.pttButton);
    expect(inputPill, findsOneWidget);
    await tester.tap(inputPill);
    await settle(tester);

    // Step 3: AddTaskSheet appeared — verify text field with hint
    expect(find.text('What needs to be done?'), findsOneWidget);

    // Step 4: Type task title
    final textField = find.byKey(TK.addTaskTextField);
    expect(textField, findsOneWidget);
    await tester.enterText(textField, 'Buy groceries for the week');
    await settle(tester, const Duration(seconds: 1));

    // Step 5: Tap send button
    final sendButton = find.byKey(TK.sendButton);
    expect(sendButton, findsOneWidget);
    await tester.tap(sendButton);

    // Step 6-7: Wait for API response + sheet dismissal
    await settle(tester, const Duration(seconds: 5));

    // Step 8: Sheet should be dismissed — verify hint text is gone
    expect(find.text('What needs to be done?'), findsNothing);
    expectOutcome('task_created');

    // Step 9: Switch to Flat view to see the task in a list
    final flatTab = find.byKey(TK.flatTab);
    expect(flatTab, findsOneWidget);
    await tester.tap(flatTab);
    await settle(tester);

    // Step 10: Verify task text appears somewhere in the widget tree
    expect(find.textContaining('Buy groceries'), findsWidgets);
  });
}
