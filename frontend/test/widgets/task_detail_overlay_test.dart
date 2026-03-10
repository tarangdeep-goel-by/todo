import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/widgets/task_detail_overlay.dart';
import 'package:frontend/providers/api_provider.dart';
import 'package:frontend/providers/task_store_provider.dart';
import 'package:frontend/config/theme.dart';
import 'package:frontend/models/task.dart';
import '../helpers/test_helpers.dart';

void main() {
  late MockApiService mockApi;

  setUp(() {
    mockApi = MockApiService();
  });

  final testPaletteMap = <String, DomainPalette>{
    'career': DomainColors.careerDark,
    'home': DomainColors.homeDark,
  };

  Widget buildOverlay({required String taskId, required List<Task> tasks}) {
    return ProviderScope(
      overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
        domainPalettesProvider.overrideWithValue(testPaletteMap),
        taskStoreProvider.overrideWith((ref) {
          final notifier = TaskStoreNotifier(ref);
          for (final t in tasks) {
            notifier.upsertTask(t);
          }
          return notifier;
        }),
      ],
      child: MaterialApp(
        home: TaskDetailOverlay(taskId: taskId),
      ),
    );
  }

  group('TaskDetailOverlay', () {
    testWidgets('renders task title', (tester) async {
      final task = createTestTask(
        id: 'test-id-1',
        title: 'review pull request',
        category: 'career',
      );
      await tester.pumpWidget(buildOverlay(
        taskId: 'test-id-1',
        tasks: [task],
      ));
      await tester.pumpAndSettle();

      // sentenceTitle capitalizes first char
      expect(find.text('Review pull request'), findsOneWidget);
    });

    testWidgets('renders DESCRIPTION section header', (tester) async {
      final task = createTestTask(
        id: 'test-id-1',
        title: 'some task',
        category: 'career',
      );
      await tester.pumpWidget(buildOverlay(
        taskId: 'test-id-1',
        tasks: [task],
      ));
      await tester.pumpAndSettle();

      // Non-editing mode uses sentence case label
      expect(find.text('Description'), findsOneWidget);
    });

    testWidgets('renders SUBTASKS section header', (tester) async {
      final task = createTestTask(
        id: 'test-id-1',
        title: 'some task',
        category: 'career',
      );
      await tester.pumpWidget(buildOverlay(
        taskId: 'test-id-1',
        tasks: [task],
      ));
      await tester.pumpAndSettle();

      expect(find.text('SUBTASKS'), findsOneWidget);
    });

    testWidgets('shows domain label with category', (tester) async {
      final task = createTestTask(
        id: 'test-id-1',
        title: 'some task',
        category: 'career',
      );
      await tester.pumpWidget(buildOverlay(
        taskId: 'test-id-1',
        tasks: [task],
      ));
      await tester.pumpAndSettle();

      expect(find.text('CAREER'), findsOneWidget);
    });

    testWidgets('shows "Task not found" for missing task', (tester) async {
      await tester.pumpWidget(buildOverlay(
        taskId: 'nonexistent',
        tasks: [],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Task not found'), findsOneWidget);
    });

    testWidgets('shows priority chip', (tester) async {
      final task = createTestTask(
        id: 'test-id-1',
        title: 'important task',
        category: 'career',
        priority: 'high',
      );
      await tester.pumpWidget(buildOverlay(
        taskId: 'test-id-1',
        tasks: [task],
      ));
      await tester.pumpAndSettle();

      expect(find.text('High'), findsAtLeastNWidgets(1));
    });
  });
}
