import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/widgets/calendar_task_view.dart';
import 'package:frontend/providers/task_store_provider.dart';
import 'package:frontend/providers/api_provider.dart';
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
    testWidgets('shows empty state when no active tasks', (tester) async {
      await tester.pumpWidget(buildCalendarView());
      await tester.pump();

      expect(find.text('Timeline is clear'), findsOneWidget);
    });

    testWidgets('groups overdue tasks in Overdue section', (tester) async {
      final container = ProviderContainer(overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
      ]);

      container.read(taskStoreProvider.notifier).upsertTask(
        createTestTask(
          id: 'overdue-1',
          title: 'Past Due Task',
          status: 'active',
          dueDate: DateTime.now().subtract(const Duration(days: 2)),
        ),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: CalendarTaskView())),
        ),
      );
      await tester.pump();

      expect(find.text('Overdue'), findsOneWidget);
      expect(find.text('Past Due Task'), findsOneWidget);
    });

    testWidgets('groups tasks due today in Today section', (tester) async {
      final container = ProviderContainer(overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
      ]);

      // Create a task due later today
      final todayEnd = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
        23, 59, 59,
      );

      container.read(taskStoreProvider.notifier).upsertTask(
        createTestTask(
          id: 'today-1',
          title: 'Today Task',
          status: 'active',
          dueDate: todayEnd,
        ),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: CalendarTaskView())),
        ),
      );
      await tester.pump();

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Today Task'), findsOneWidget);
    });

    testWidgets('shows No Date section collapsed by default', (tester) async {
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

      expect(find.text('No Date'), findsOneWidget);
      // Task not visible until expanded
      expect(find.text('Undated Task'), findsNothing);

      // Tap to expand
      await tester.tap(find.text('No Date'));
      await tester.pump();
      expect(find.text('Undated Task'), findsOneWidget);
    });

    testWidgets('overdue section appears before today section', (tester) async {
      final container = ProviderContainer(overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
      ]);

      final todayEnd = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
        23, 59, 59,
      );

      container.read(taskStoreProvider.notifier).upsertTask(
        createTestTask(
          id: 'today-1',
          title: 'Today Task',
          status: 'active',
          dueDate: todayEnd,
        ),
      );
      container.read(taskStoreProvider.notifier).upsertTask(
        createTestTask(
          id: 'overdue-1',
          title: 'Overdue Task',
          status: 'active',
          dueDate: DateTime.now().subtract(const Duration(days: 1)),
        ),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: CalendarTaskView())),
        ),
      );
      await tester.pump();

      final overduePos = tester.getTopLeft(find.text('Overdue'));
      final todayPos = tester.getTopLeft(find.text('Today'));
      expect(overduePos.dy, lessThan(todayPos.dy));
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
  });
}
