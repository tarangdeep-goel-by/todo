import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/widgets/task_item.dart';
import 'package:frontend/providers/api_provider.dart';
import '../helpers/test_helpers.dart';

void main() {
  late MockApiService mockApi;

  setUp(() {
    mockApi = MockApiService();
  });

  Widget buildWidget(TaskItem item, {List<Override> overrides = const []}) {
    return ProviderScope(
      overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
        ...overrides,
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (_) => Material(child: ListView(children: [item])),
              ),
            ],
          ),
        ),
      ),
    );
  }

  group('TaskItem', () {
    testWidgets('renders task title', (tester) async {
      final task = createTestTask(title: 'buy groceries');
      await tester.pumpWidget(buildWidget(
        TaskItem(task: task, isDark: true),
      ));

      // sentenceTitle capitalizes first char
      expect(find.text('Buy groceries'), findsOneWidget);
    });

    testWidgets('shows Overdue badge when past dueDate + active',
        (tester) async {
      final task = createTestTask(
        title: 'old task',
        status: 'active',
        dueDate: DateTime.now().subtract(const Duration(days: 2)),
      );
      await tester.pumpWidget(buildWidget(
        TaskItem(task: task, isDark: true),
      ));

      expect(find.text('Overdue'), findsOneWidget);
    });

    testWidgets('shows priority badge with capitalized text', (tester) async {
      final task = createTestTask(
        title: 'important',
        priority: 'high',
      );
      await tester.pumpWidget(buildWidget(
        TaskItem(task: task, isDark: true),
      ));

      expect(find.text('High'), findsOneWidget);
    });

    testWidgets('shows strikethrough for completed tasks', (tester) async {
      final task = createTestTask(
        title: 'done task',
        status: 'completed',
        completedAt: DateTime.now(),
      );
      await tester.pumpWidget(buildWidget(
        TaskItem(task: task, isDark: true),
      ));

      final textWidget = tester.widget<Text>(find.text('Done task'));
      expect(textWidget.style?.decoration, TextDecoration.lineThrough);
    });

    testWidgets('does not show Overdue badge for completed tasks',
        (tester) async {
      final task = createTestTask(
        title: 'completed old task',
        status: 'completed',
        completedAt: DateTime.now(),
        dueDate: DateTime.now().subtract(const Duration(days: 5)),
      );
      await tester.pumpWidget(buildWidget(
        TaskItem(task: task, isDark: true),
      ));

      expect(find.text('Overdue'), findsNothing);
    });

    testWidgets('does not show Due Soon badge for completed tasks',
        (tester) async {
      final task = createTestTask(
        title: 'completed soon task',
        status: 'completed',
        completedAt: DateTime.now(),
        dueDate: DateTime.now().add(const Duration(hours: 12)),
      );
      await tester.pumpWidget(buildWidget(
        TaskItem(task: task, isDark: true),
      ));

      expect(find.text('Due Soon'), findsNothing);
    });

    testWidgets('shows parent name when provided', (tester) async {
      final task = createTestTask(title: 'sub task');
      await tester.pumpWidget(buildWidget(
        TaskItem(task: task, isDark: true, parentName: 'parent task'),
      ));

      expect(find.text('Parent task'), findsOneWidget);
    });
  });
}
