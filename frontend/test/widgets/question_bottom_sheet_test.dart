import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:frontend/widgets/question_bottom_sheet.dart';
import 'package:frontend/models/api_response.dart';
import 'package:frontend/providers/api_provider.dart';
import '../helpers/test_helpers.dart';

void main() {
  late MockApiService mockApi;

  setUp(() {
    mockApi = MockApiService();
  });

  Widget buildSheet(AgentResponse response) {
    return ProviderScope(
      overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            return ElevatedButton(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => QuestionBottomSheet(response: response),
                );
              },
              child: const Text('Show'),
            );
          }),
        ),
      ),
    );
  }

  group('Match list rendering', () {
    testWidgets('shows match titles', (tester) async {
      final response = AgentResponse(
        success: false,
        message: 'Which task?',
        type: 'question',
        data: {
          'matches': [
            {'id': '1', 'title': 'Task A', 'category': 'work'},
            {'id': '2', 'title': 'Task B', 'category': 'personal'},
          ],
          'action': 'complete',
        },
      );
      await tester.pumpWidget(buildSheet(response));
      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      expect(find.text('Task A'), findsOneWidget);
      expect(find.text('Task B'), findsOneWidget);
    });

    testWidgets('shows header message', (tester) async {
      final response = AgentResponse(
        success: false,
        message: 'Found 2 tasks. Which one?',
        type: 'question',
        data: {
          'matches': [
            {'id': '1', 'title': 'X', 'category': 'work'},
          ],
          'action': 'complete',
        },
      );
      await tester.pumpWidget(buildSheet(response));
      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      expect(find.text('Found 2 tasks. Which one?'), findsOneWidget);
    });

    testWidgets('tap calls resolveQuestion', (tester) async {
      when(() => mockApi.resolveQuestion(
            userId: any(named: 'userId'),
            action: any(named: 'action'),
            selectedTaskId: any(named: 'selectedTaskId'),
            data: any(named: 'data'),
          )).thenAnswer((_) async => AgentResponse(
            success: true,
            message: 'Done',
            type: 'confirmation',
          ));

      final response = AgentResponse(
        success: false,
        message: 'Which one?',
        type: 'question',
        data: {
          'matches': [
            {'id': 't1', 'title': 'Task A', 'category': 'work'},
          ],
          'action': 'complete',
        },
      );
      await tester.pumpWidget(buildSheet(response));
      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Task A'));
      await tester.pumpAndSettle();

      verify(() => mockApi.resolveQuestion(
            userId: any(named: 'userId'),
            action: 'complete',
            selectedTaskId: 't1',
            data: any(named: 'data'),
          )).called(1);
    });

    testWidgets('shows loading indicator on tap', (tester) async {
      // Use a Completer to keep the future pending without timers
      final completer = Completer<AgentResponse>();
      when(() => mockApi.resolveQuestion(
            userId: any(named: 'userId'),
            action: any(named: 'action'),
            selectedTaskId: any(named: 'selectedTaskId'),
            data: any(named: 'data'),
          )).thenAnswer((_) => completer.future);

      final response = AgentResponse(
        success: false,
        message: 'Pick',
        type: 'question',
        data: {
          'matches': [
            {'id': 't1', 'title': 'Task A', 'category': 'work'},
          ],
          'action': 'delete',
        },
      );
      await tester.pumpWidget(buildSheet(response));
      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Task A'));
      await tester.pump(); // Don't settle — let loading show

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Complete the future to clean up
      completer.complete(AgentResponse(
          success: true, message: 'Done', type: 'confirmation'));
      await tester.pumpAndSettle();
    });
  });

  group('Create category', () {
    testWidgets('shows confirm and cancel buttons', (tester) async {
      final response = AgentResponse(
        success: false,
        message: 'Create Hobbies category?',
        type: 'question',
        data: {
          'action': 'create_category',
          'suggested_title': 'Practice violin',
          'suggested_category': 'hobbies',
        },
      );
      await tester.pumpWidget(buildSheet(response));
      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      expect(find.text('Cancel'), findsOneWidget);
      expect(find.textContaining('Create'), findsWidgets);
    });

    testWidgets('confirm tap calls resolveQuestion', (tester) async {
      when(() => mockApi.resolveQuestion(
            userId: any(named: 'userId'),
            action: any(named: 'action'),
            data: any(named: 'data'),
            selectedTaskId: any(named: 'selectedTaskId'),
          )).thenAnswer((_) async => AgentResponse(
            success: true,
            message: 'Created',
            type: 'confirmation',
          ));

      final response = AgentResponse(
        success: false,
        message: 'Create Hobbies?',
        type: 'question',
        data: {
          'action': 'create_category',
          'suggested_title': 'Violin',
          'suggested_category': 'hobbies',
        },
      );
      await tester.pumpWidget(buildSheet(response));
      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      // Tap the Create button (contains "Create Hobbies")
      final createButtons = find.textContaining('Create');
      await tester.tap(createButtons.last);
      await tester.pumpAndSettle();

      verify(() => mockApi.resolveQuestion(
            userId: any(named: 'userId'),
            action: 'create_category',
            data: any(named: 'data'),
            selectedTaskId: any(named: 'selectedTaskId'),
          )).called(1);
    });

    testWidgets('cancel closes sheet', (tester) async {
      final response = AgentResponse(
        success: false,
        message: 'Create category?',
        type: 'question',
        data: {
          'action': 'create_category',
          'suggested_title': 'X',
          'suggested_category': 'hobbies',
        },
      );
      await tester.pumpWidget(buildSheet(response));
      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Create category?'), findsNothing);
    });
  });

  group('Chained question', () {
    testWidgets('resolve returns question → new sheet appears', (tester) async {
      when(() => mockApi.resolveQuestion(
            userId: any(named: 'userId'),
            action: any(named: 'action'),
            selectedTaskId: any(named: 'selectedTaskId'),
            data: any(named: 'data'),
          )).thenAnswer((_) async => AgentResponse(
            success: false,
            message: 'Which parent?',
            type: 'question',
            data: {
              'matches': [
                {'id': 'p1', 'title': 'Parent A', 'category': 'work'},
              ],
              'action': 'select_parent',
            },
          ));

      final response = AgentResponse(
        success: false,
        message: 'Which task?',
        type: 'question',
        data: {
          'matches': [
            {'id': 't1', 'title': 'Task A', 'category': 'work'},
          ],
          'action': 'move',
        },
      );
      await tester.pumpWidget(buildSheet(response));
      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Task A'));
      await tester.pumpAndSettle();

      // New sheet should appear with "Which parent?"
      expect(find.text('Which parent?'), findsOneWidget);
      expect(find.text('Parent A'), findsOneWidget);
    });
  });
}
