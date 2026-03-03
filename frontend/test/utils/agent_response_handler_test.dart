import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/utils/agent_response_handler.dart';
import 'package:frontend/models/api_response.dart';
import 'package:frontend/providers/api_provider.dart';
import 'package:frontend/providers/task_store_provider.dart';
import 'package:frontend/widgets/question_bottom_sheet.dart';

import '../helpers/test_helpers.dart';

void main() {
  late MockApiService mockApi;

  setUp(() {
    mockApi = MockApiService();
  });

  Widget buildApp({required Widget child}) {
    return ProviderScope(
      overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
        domainPalettesProvider.overrideWithValue(createTestPaletteMap()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Overlay(
            initialEntries: [
              OverlayEntry(builder: (_) => child),
            ],
          ),
        ),
      ),
    );
  }

  group('handleAgentResponse', () {
    testWidgets('success confirmation shows snackbar with message',
        (tester) async {
      final response = createTestAgentResponse(
        success: true,
        message: 'Task added successfully',
        type: 'confirmation',
      );

      await tester.pumpWidget(buildApp(
        child: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () {
              handleAgentResponse(context: context, response: response);
            },
            child: const Text('Trigger'),
          );
        }),
      ));

      await tester.tap(find.text('Trigger'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Task added successfully'), findsOneWidget);
    });

    testWidgets('error response shows error snackbar', (tester) async {
      final response = createTestAgentResponse(
        success: false,
        message: 'Something went wrong',
        type: 'error',
      );

      await tester.pumpWidget(buildApp(
        child: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () {
              handleAgentResponse(context: context, response: response);
            },
            child: const Text('Trigger'),
          );
        }),
      ));

      await tester.tap(find.text('Trigger'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('question type opens bottom sheet', (tester) async {
      final response = AgentResponse(
        success: true,
        message: 'Which task did you mean?',
        type: 'question',
        data: {
          'action': 'disambiguate',
          'options': [
            {'id': '1', 'title': 'Task A'},
            {'id': '2', 'title': 'Task B'},
          ],
        },
      );

      await tester.pumpWidget(buildApp(
        child: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () {
              handleAgentResponse(context: context, response: response);
            },
            child: const Text('Trigger'),
          );
        }),
      ));

      await tester.tap(find.text('Trigger'));
      await tester.pumpAndSettle();

      expect(find.byType(QuestionBottomSheet), findsOneWidget);
    });
  });
}
