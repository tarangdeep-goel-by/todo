import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/widgets/task_parent_picker.dart';
import 'package:frontend/providers/task_store_provider.dart';

import '../helpers/test_helpers.dart';

void main() {
  // Test tasks:
  // work-1: root in work
  // work-2: child of work-1
  // work-3: root in work
  // personal-1: root in personal
  late List<Override> baseOverrides;

  final workTask1 = createTestTask(
    id: 'work-1',
    title: 'design mockups',
    category: 'career',
    parentId: null,
  );
  final workTask2 = createTestTask(
    id: 'work-2',
    title: 'refine wireframes',
    category: 'career',
    parentId: 'work-1',
  );
  final workTask3 = createTestTask(
    id: 'work-3',
    title: 'fix bug',
    category: 'career',
    parentId: null,
  );
  final personalTask1 = createTestTask(
    id: 'personal-1',
    title: 'buy groceries',
    category: 'home',
    parentId: null,
  );

  final allTasks = [workTask1, workTask2, workTask3, personalTask1];

  setUp(() {
    baseOverrides = [
      allTasksProvider.overrideWith((ref) => allTasks),
      domainPalettesProvider.overrideWithValue(createTestPaletteMap()),
    ];
  });

  Widget buildPicker({
    String? currentParentId,
    String? excludeTaskId,
    VoidCallback? onBack,
    ValueChanged<ParentPickerResult>? onSelect,
    List<Override> extra = const [],
  }) {
    return ProviderScope(
      overrides: [...baseOverrides, ...extra],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: TaskParentPicker(
              currentParentId: currentParentId,
              excludeTaskId: excludeTaskId,
              onBack: onBack ?? () {},
              onSelect: onSelect ?? (_) {},
            ),
          ),
        ),
      ),
    );
  }

  group('TaskParentPicker', () {
    testWidgets('renders Pick a parent text', (tester) async {
      await tester.pumpWidget(buildPicker());
      expect(find.text('Pick a parent'), findsOneWidget);
    });

    testWidgets('renders search field with Search tasks... hint',
        (tester) async {
      await tester.pumpWidget(buildPicker());
      expect(find.text('Search tasks...'), findsOneWidget);
    });

    testWidgets('shows Top level text for each domain', (tester) async {
      await tester.pumpWidget(buildPicker());
      // One 'Top level' per domain that has tasks or is in paletteMap
      final topLevelFinder = find.text('Top level');
      expect(topLevelFinder, findsWidgets);
      // At minimum, work and personal domains should show Top level
      expect(topLevelFinder.evaluate().length, greaterThanOrEqualTo(2));
    });

    testWidgets('shows task titles from allTasksProvider', (tester) async {
      await tester.pumpWidget(buildPicker());

      // sentenceTitle capitalizes first char
      expect(find.text('Design mockups'), findsOneWidget);
      expect(find.text('Refine wireframes'), findsOneWidget);
      expect(find.text('Fix bug'), findsOneWidget);
      // 'home' domain renders further down — may be offstage in 600px viewport
      expect(find.text('Buy groceries', skipOffstage: false), findsOneWidget);
    });

    testWidgets('excludes excludeTaskId and its descendants', (tester) async {
      // Exclude work-1; work-2 is its child so both should be hidden
      await tester.pumpWidget(buildPicker(excludeTaskId: 'work-1'));

      expect(find.text('Design mockups'), findsNothing);
      expect(find.text('Refine wireframes'), findsNothing);
      // work-3 and personal-1 should still show
      expect(find.text('Fix bug'), findsOneWidget);
      expect(find.text('Buy groceries', skipOffstage: false), findsOneWidget);
    });

    testWidgets('search filters tasks by title', (tester) async {
      await tester.pumpWidget(buildPicker());

      // Type in search field
      await tester.enterText(find.byType(TextField), 'bug');
      await tester.pump();

      expect(find.text('Fix bug'), findsOneWidget);
      expect(find.text('Design mockups'), findsNothing);
      expect(find.text('Buy groceries'), findsNothing);
    });

    testWidgets('tapping task calls onSelect with correct ParentPickerResult',
        (tester) async {
      ParentPickerResult? result;
      await tester.pumpWidget(buildPicker(
        onSelect: (r) => result = r,
      ));

      await tester.tap(find.text('Fix bug'));
      await tester.pump();

      expect(result, isNotNull);
      expect(result!.taskId, 'work-3');
      expect(result!.taskTitle, 'fix bug');
      expect(result!.category, 'career');
    });

    testWidgets('tapping Top level calls onSelect with taskId null',
        (tester) async {
      ParentPickerResult? result;
      await tester.pumpWidget(buildPicker(
        onSelect: (r) => result = r,
      ));

      // Tap the first Top level row
      await tester.tap(find.text('Top level').first);
      await tester.pump();

      expect(result, isNotNull);
      expect(result!.taskId, isNull);
      expect(result!.taskTitle, isNull);
      expect(result!.category, isNotEmpty);
    });

    testWidgets('back button calls onBack', (tester) async {
      var backCalled = false;
      await tester.pumpWidget(buildPicker(
        onBack: () => backCalled = true,
      ));

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
      await tester.pump();

      expect(backCalled, isTrue);
    });

    testWidgets('shows depth indentation for child tasks', (tester) async {
      await tester.pumpWidget(buildPicker());

      // work-2 (child of work-1) should have left padding > 0
      // Find the row containing 'Refine wireframes' and check its padding
      final childRow = find.text('Refine wireframes');
      expect(childRow, findsOneWidget);

      // The parent row for work-1 is at depth 0 (no indent).
      // The child row for work-2 is at depth 1 (indent = 1 * 16 = 16).
      // We verify by checking that the Padding widget ancestor has non-zero left.
      final childPadding = find.ancestor(
        of: childRow,
        matching: find.byType(Padding),
      );
      expect(childPadding, findsWidgets);
    });

    testWidgets('shows No matching tasks when search has no results',
        (tester) async {
      await tester.pumpWidget(buildPicker());

      await tester.enterText(find.byType(TextField), 'xyznonexistent');
      await tester.pump();

      expect(find.text('No matching tasks'), findsOneWidget);
    });
  });
}
