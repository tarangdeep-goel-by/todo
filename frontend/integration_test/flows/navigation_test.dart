import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:frontend/screens/parent_node_view.dart';
import 'package:frontend/screens/flat_task_view.dart';
import 'package:frontend/widgets/calendar_task_view.dart';
import 'package:frontend/services/tracker/tracker_keys.dart';
import '../helpers/test_app.dart';
import '../helpers/api_cleanup.dart';
import '../helpers/tracker_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await cleanupTestUser();
  });

  testWidgets('Flow 3: Navigation between views', (tester) async {
    // Step 1: Launch app — starts in Home (node) view
    await pumpApp(tester);

    // Step 2: Verify Home view is active — ParentNodeView should be present
    expect(find.byType(ParentNodeView), findsOneWidget);

    // Step 3: Tap Flat tab → FlatTaskView appears
    final flatTab = find.byKey(TK.flatTab);
    expect(flatTab, findsOneWidget);
    await tester.tap(flatTab);
    await settle(tester);
    expectTap('flat_tab');
    expect(find.byType(FlatTaskView), findsOneWidget);

    // Step 4: Tap Cal tab → CalendarTaskView appears
    final calTab = find.byKey(TK.calTab);
    expect(calTab, findsOneWidget);
    await tester.tap(calTab);
    await settle(tester);
    expectTap('cal_tab');
    expect(find.byType(CalendarTaskView), findsOneWidget);

    // Step 5: Tap Home tab → back to ParentNodeView
    final homeTab = find.byKey(TK.homeTab);
    expect(homeTab, findsOneWidget);
    await tester.tap(homeTab);
    await settle(tester);
    expectTap('home_tab');
    expect(find.byType(ParentNodeView), findsOneWidget);

    // Step 6: Verify the center input pill is always visible
    // Text is either 'Add or talk' or 'Hold to talk' depending on onboarding state
    final addOrTalk = find.text('Add or talk');
    final holdToTalk = find.text('Hold to talk');
    expect(addOrTalk.evaluate().isNotEmpty || holdToTalk.evaluate().isNotEmpty, isTrue);
  });
}
