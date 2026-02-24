import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:frontend/widgets/subtask_selection_sheet.dart';
import 'package:frontend/providers/api_provider.dart';
import 'package:frontend/models/api_response.dart';
import '../helpers/test_helpers.dart';

void main() {
  late MockApiService mockApi;

  setUp(() {
    mockApi = MockApiService();
  });

  final parentTask = {
    'id': 'parent-123',
    'title': 'Quarterly Report',
    'category': 'work',
  };
  final suggestions = [
    'Gather data',
    'Create outline',
    'Draft report',
    'Review with team',
  ];

  Widget buildSheet({List<Override> overrides = const []}) {
    return buildTestApp(
      SubtaskSelectionSheet(
        parentTask: parentTask,
        suggestions: suggestions,
      ),
      overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
        ...overrides,
      ],
    );
  }

  group('SubtaskSelectionSheet', () {
    testWidgets('renders all suggestions unchecked', (tester) async {
      await tester.pumpWidget(buildSheet());
      await tester.pump();

      for (final s in suggestions) {
        expect(find.text(s), findsOneWidget);
      }

      // Button should say "Create 0 Subtasks"
      expect(find.text('Create 0 Subtasks'), findsOneWidget);
    });

    testWidgets('selecting checkboxes updates count on button', (tester) async {
      await tester.pumpWidget(buildSheet());
      await tester.pump();

      // Tap first suggestion
      await tester.tap(find.text('Gather data'));
      await tester.pump();
      expect(find.text('Create 1 Subtask'), findsOneWidget);

      // Tap second suggestion
      await tester.tap(find.text('Create outline'));
      await tester.pump();
      expect(find.text('Create 2 Subtasks'), findsOneWidget);

      // Deselect first
      await tester.tap(find.text('Gather data'));
      await tester.pump();
      expect(find.text('Create 1 Subtask'), findsOneWidget);
    });

    testWidgets('adding custom subtask works', (tester) async {
      await tester.pumpWidget(buildSheet());
      await tester.pump();

      // Enter custom text
      await tester.enterText(find.byType(TextField), 'My custom step');
      await tester.pump();

      // Tap add button
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();

      // Custom subtask appears and is pre-checked
      expect(find.text('My custom step'), findsOneWidget);
      expect(find.text('Create 1 Subtask'), findsOneWidget);
    });

    testWidgets('shows parent task title in header', (tester) async {
      await tester.pumpWidget(buildSheet());
      await tester.pump();

      expect(find.text('Break down'), findsOneWidget);
      expect(find.text('Quarterly Report'), findsOneWidget);
    });

    testWidgets('create button calls resolve API with correct payload',
        (tester) async {
      when(() => mockApi.resolveQuestion(
            userId: any(named: 'userId'),
            action: any(named: 'action'),
            data: any(named: 'data'),
          )).thenAnswer((_) async => createTestAgentResponse(
            message: "Created 2 subtasks under 'Quarterly Report'",
          ));
      when(() => mockApi.getTasksAdvanced(
            userId: any(named: 'userId'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).thenAnswer((_) async => TaskListResponse(
            tasks: [], totalCount: 0, limit: 100, offset: 0, hasMore: false,
          ));

      await tester.pumpWidget(buildSheet());
      await tester.pump();

      // Select two suggestions
      await tester.tap(find.text('Gather data'));
      await tester.pump();
      await tester.tap(find.text('Draft report'));
      await tester.pump();

      // Tap create button
      await tester.tap(find.text('Create 2 Subtasks'));
      await tester.pump();

      verify(() => mockApi.resolveQuestion(
            userId: 'default-user',
            action: 'create_subtasks',
            data: {
              'parent_task_id': 'parent-123',
              'selected_titles': ['Gather data', 'Draft report'],
            },
          )).called(1);
    });
  });
}
