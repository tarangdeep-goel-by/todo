import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/screens/flat_task_view.dart';
import 'package:frontend/providers/api_provider.dart';
import 'package:frontend/providers/task_store_provider.dart';
import 'package:frontend/widgets/empty_state.dart';
import 'package:frontend/widgets/flat_task_row.dart';

import '../helpers/test_helpers.dart';

void main() {
  late MockApiService mockApi;

  setUp(() {
    mockApi = MockApiService();
  });

  Widget buildView({List<Override> extra = const []}) {
    return ProviderScope(
      overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
        domainPalettesProvider.overrideWithValue(createTestPaletteMap()),
        ...extra,
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: FlatTaskView(),
        ),
      ),
    );
  }

  group('FlatTaskView', () {
    testWidgets('shows All clear when store has no tasks', (tester) async {
      await tester.pumpWidget(buildView());
      await tester.pump();

      expect(find.text('All clear'), findsOneWidget);
    });

    testWidgets('shows All clear subtitle text', (tester) async {
      await tester.pumpWidget(buildView());
      await tester.pump();

      expect(
        find.text(
            'Your tasks will appear here.\nSpeak or type below to add your first task.'),
        findsOneWidget,
      );
    });

    testWidgets('renders TaskItem widgets when tasks exist', (tester) async {
      final task1 = createTestTask(
        id: 'flat-1',
        title: 'review PR',
        category: 'career',
      );
      final task2 = createTestTask(
        id: 'flat-2',
        title: 'morning run',
        category: 'health',
      );

      // Pre-populate the store by overriding the notifier
      await tester.pumpWidget(buildView());
      await tester.pump();

      // Grab the notifier and upsert tasks
      final container = ProviderScope.containerOf(
        tester.element(find.byType(FlatTaskView)),
      );
      container.read(taskStoreProvider.notifier).upsertTask(task1);
      container.read(taskStoreProvider.notifier).upsertTask(task2);
      await tester.pump();

      expect(find.byType(FlatTaskRow), findsWidgets);
      // sentenceTitle capitalizes first char
      expect(find.text('Review PR'), findsOneWidget);
      expect(find.text('Morning run'), findsOneWidget);
    });

    testWidgets('has RefreshIndicator', (tester) async {
      final task = createTestTask(id: 'r-1', title: 'task for refresh');
      await tester.pumpWidget(buildView());
      await tester.pump();

      // Add a task so we get the list view (which contains RefreshIndicator)
      final container = ProviderScope.containerOf(
        tester.element(find.byType(FlatTaskView)),
      );
      container.read(taskStoreProvider.notifier).upsertTask(task);
      await tester.pump();

      expect(find.byType(RefreshIndicator), findsOneWidget);
    });

    testWidgets('shows EmptyState widget when no tasks', (tester) async {
      await tester.pumpWidget(buildView());
      await tester.pump();

      expect(find.byType(EmptyState), findsOneWidget);
    });
  });
}
