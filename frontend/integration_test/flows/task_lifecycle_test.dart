import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../helpers/test_app.dart';
import '../helpers/api_cleanup.dart';

/// Finds the AddTaskSheet's text field by its hint text.
Finder addTaskTextField() => find.widgetWithText(TextField, 'What needs to be done?');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await cleanupTestUser();
  });

  testWidgets('Flow 2: Create and verify multiple tasks', (tester) async {
    // Step 1: Launch app
    await pumpApp(tester);

    // Step 2: Create first task via keyboard
    await tester.tap(find.byIcon(Icons.mic_rounded));
    await settle(tester);

    await tester.enterText(addTaskTextField(), 'Complete this task');
    await settle(tester, const Duration(seconds: 1));

    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await settle(tester, const Duration(seconds: 5));

    // Step 3: Switch to Flat view
    await tester.tap(find.text('Flat'));
    await settle(tester);

    // Step 4: Verify task appears
    expect(find.textContaining('Complete this task'), findsWidgets);

    // Step 5: Create a second task
    await tester.tap(find.byIcon(Icons.mic_rounded));
    await settle(tester);

    await tester.enterText(addTaskTextField(), 'Another task');
    await settle(tester, const Duration(seconds: 1));

    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await settle(tester, const Duration(seconds: 5));

    // Step 6: Verify both tasks appear in flat view
    expect(find.textContaining('Complete this task'), findsWidgets);
    expect(find.textContaining('Another task'), findsWidgets);
  });
}
