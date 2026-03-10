import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/widgets/calendar_task_view.dart';
import 'package:frontend/providers/task_store_provider.dart';
import 'package:frontend/providers/api_provider.dart';
import 'package:intl/intl.dart';
import '../helpers/test_helpers.dart';

void main() {
  late MockApiService mockApi;

  setUp(() {
    mockApi = MockApiService();
  });

  Widget buildCalendarView({List<Override> overrides = const []}) {
    return buildTestApp(
      const CalendarTaskView(),
      overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
        ...overrides,
      ],
    );
  }

  group('CalendarTaskView', () {
    testWidgets('shows month header with current month', (tester) async {
      await tester.pumpWidget(buildCalendarView());
      await tester.pump();

      expect(find.text('Calendar is clear'), findsOneWidget);
    });

    testWidgets('shows month header with navigation', (tester) async {
      final container = ProviderContainer(overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
      ]);

      container.read(taskStoreProvider.notifier).upsertTask(
        createTestTask(
          id: 'today-1',
          title: 'Today Task',
          status: 'active',
          dueDate: DateTime.now(),
        ),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: CalendarTaskView())),
        ),
      );
      await tester.pump();

      // Month navigation arrows should be present
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('shows day-of-week headers', (tester) async {
      final container = ProviderContainer(overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
      ]);

      container.read(taskStoreProvider.notifier).upsertTask(
        createTestTask(
          id: 'task-1',
          title: 'Some Task',
          status: 'active',
          dueDate: DateTime.now(),
        ),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: CalendarTaskView())),
        ),
      );
      await tester.pump();

      expect(find.text('MON'), findsOneWidget);
      expect(find.text('SUN'), findsOneWidget);
    });

    testWidgets('shows task for selected day', (tester) async {
      final container = ProviderContainer(overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
      ]);

      // Today's task should appear since today is selected by default
      container.read(taskStoreProvider.notifier).upsertTask(
        createTestTask(
          id: 'today-1',
          title: 'Today Task',
          status: 'active',
          dueDate: DateTime.now(),
        ),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: CalendarTaskView())),
        ),
      );
      await tester.pump();

      expect(find.text('Today Task'), findsOneWidget);
    });

    testWidgets('shows undated tasks section collapsed by default', (tester) async {
      final container = ProviderContainer(overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
      ]);

      container.read(taskStoreProvider.notifier).upsertTask(
            createTestTask(
              id: 'no-date',
              title: 'Undated Task',
              status: 'active',
            ),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: CalendarTaskView())),
        ),
      );
      await tester.pump();

      expect(find.text('No due date'), findsOneWidget);
      // Task not visible until expanded
      expect(find.text('Undated Task'), findsNothing);

      // Tap to expand
      await tester.tap(find.text('No due date'));
      await tester.pump();
      expect(find.text('Undated Task'), findsOneWidget);
    });

    testWidgets('shows empty state for selected day with no tasks', (tester) async {
      final container = ProviderContainer(overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
      ]);

      // Add a task on a different day so calendar is not empty
      container.read(taskStoreProvider.notifier).upsertTask(
        createTestTask(
          id: 'future-1',
          title: 'Future Task',
          status: 'active',
          dueDate: DateTime.now().add(const Duration(days: 5)),
        ),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: CalendarTaskView())),
        ),
      );
      await tester.pump();

      // Today is selected by default but has no tasks
      expect(find.text('No tasks on this day'), findsOneWidget);
    });

    testWidgets('completed tasks are excluded', (tester) async {
      final container = ProviderContainer(overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
      ]);

      container.read(taskStoreProvider.notifier).upsertTask(
            createTestTask(
              id: 'done',
              title: 'Completed Task',
              status: 'completed',
              dueDate: DateTime.now().add(const Duration(hours: 12)),
            ),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: CalendarTaskView())),
        ),
      );
      await tester.pump();

      expect(find.text('Completed Task'), findsNothing);
    });

    testWidgets('month navigation arrows work', (tester) async {
      await tester.pumpWidget(buildCalendarView());
      await tester.pump();

      final now = DateTime.now();
      final nextMonth = DateTime(now.year, now.month + 1);
      final nextMonthText = DateFormat('MMMM yyyy').format(nextMonth);

      // Tap right arrow to go to next month
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pump();

      expect(find.text(nextMonthText), findsOneWidget);
    });
  });
}
