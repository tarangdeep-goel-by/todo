import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/widgets/task_row_tile.dart';
import 'package:frontend/config/theme.dart';
import '../helpers/test_helpers.dart';

void main() {
  late DomainPalette domain;

  setUp(() {
    domain = DomainColors.workDark;
  });

  group('TaskRowTile', () {
    testWidgets('renders task title text', (tester) async {
      final task = createTestTask(title: 'Buy groceries');
      await tester.pumpWidget(buildTestApp(
        TaskRowTile(domain: domain, task: task, onTap: () {}),
      ));

      expect(find.text('Buy groceries'), findsOneWidget);
    });

    testWidgets('completed task has Opacity 0.5', (tester) async {
      final task = createTestTask(status: 'completed');

      await tester.pumpWidget(buildTestApp(
        TaskRowTile(domain: domain, task: task, onTap: () {}),
      ));

      final opacity = tester.widget<Opacity>(find.byType(Opacity));
      expect(opacity.opacity, 0.5);
    });

    testWidgets('active task has Opacity 1.0', (tester) async {
      final task = createTestTask(status: 'active');

      await tester.pumpWidget(buildTestApp(
        TaskRowTile(domain: domain, task: task, onTap: () {}),
      ));

      final opacity = tester.widget<Opacity>(find.byType(Opacity));
      expect(opacity.opacity, 1.0);
    });

    testWidgets('shows priority first letter', (tester) async {
      final task = createTestTask(priority: 'high');

      await tester.pumpWidget(buildTestApp(
        TaskRowTile(domain: domain, task: task, onTap: () {}),
      ));

      expect(find.text('H'), findsOneWidget);
    });

    testWidgets('shows due date formatted as MMM d, yyyy', (tester) async {
      final task = createTestTask(dueDate: DateTime(2025, 3, 15));

      await tester.pumpWidget(buildTestApp(
        TaskRowTile(domain: domain, task: task, onTap: () {}),
      ));

      expect(find.text('Mar 15, 2025'), findsOneWidget);
    });

    testWidgets('onTap callback fires on GestureDetector tap', (tester) async {
      bool tapped = false;
      final task = createTestTask();

      await tester.pumpWidget(buildTestApp(
        TaskRowTile(domain: domain, task: task, onTap: () => tapped = true),
      ));

      await tester.tap(find.byType(GestureDetector).first);
      expect(tapped, isTrue);
    });

    testWidgets('shows chevron_right icon', (tester) async {
      final task = createTestTask();

      await tester.pumpWidget(buildTestApp(
        TaskRowTile(domain: domain, task: task, onTap: () {}),
      ));

      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });
  });
}
