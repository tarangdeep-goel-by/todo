import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:frontend/screens/ramble_screen.dart';
import 'package:frontend/models/api_response.dart';
import 'package:frontend/providers/api_provider.dart';
import 'package:frontend/providers/task_store_provider.dart';
import 'package:frontend/services/tracker/tracker_keys.dart';

import '../helpers/test_helpers.dart';

void main() {
  late MockApiService mockApi;

  setUp(() {
    mockApi = MockApiService();

    // Stub fetchAll calls (getTasksAdvancedWithRetry + getCategories)
    when(() => mockApi.getTasksAdvancedWithRetry(
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        )).thenAnswer((_) async => TaskListResponse(
          tasks: [],
          totalCount: 0,
          limit: 100,
          offset: 0,
          hasMore: false,
        ));
    when(() => mockApi.getCategories()).thenAnswer((_) async => []);
  });

  /// Build RambleScreen in reviewing mode by passing initialProposals.
  Widget buildRambleScreen({
    List<BrainDumpTaskProposal>? proposals,
    String? transcript,
  }) {
    return buildTestApp(
      RambleScreen(
        initialProposals: proposals,
        initialTranscript: transcript,
      ),
      overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
        categoriesProvider.overrideWith((ref) => []),
      ],
    );
  }

  List<BrainDumpTaskProposal> createProposals(int count) {
    return List.generate(count, (i) => BrainDumpTaskProposal(
      id: 'proposal-$i',
      action: 'add',
      content: 'Task ${i + 1}',
      category: 'career',
      priority: 'medium',
      confidence: 0.95,
    ));
  }

  group('RambleScreen - reviewing mode', () {
    testWidgets('displays proposal cards with correct titles', (tester) async {
      final proposals = createProposals(3);

      await tester.pumpWidget(buildRambleScreen(proposals: proposals));
      await tester.pumpAndSettle();

      // Verify all 3 proposal titles render
      expect(find.text('Task 1'), findsOneWidget);
      expect(find.text('Task 2'), findsOneWidget);
      expect(find.text('Task 3'), findsOneWidget);
    });

    testWidgets('shows review header text in reviewing phase', (tester) async {
      final proposals = createProposals(2);

      await tester.pumpWidget(buildRambleScreen(proposals: proposals));
      await tester.pumpAndSettle();

      expect(find.text('Review tasks'), findsOneWidget);
      expect(find.text('Tap to edit, long-press to toggle.'), findsOneWidget);
    });

    testWidgets('shows "No tasks detected" when proposals are empty',
        (tester) async {
      await tester.pumpWidget(buildRambleScreen(proposals: []));
      await tester.pumpAndSettle();

      expect(find.text('No tasks detected'), findsOneWidget);
      expect(
          find.text('Try re-recording with more detail'), findsOneWidget);
    });

    testWidgets('shows confirm button with correct count', (tester) async {
      final proposals = createProposals(3);

      await tester.pumpWidget(buildRambleScreen(proposals: proposals));
      await tester.pumpAndSettle();

      // Submit button should show "Confirm 3 Actions"
      expect(find.text('Confirm 3 Actions'), findsOneWidget);
      expect(find.byKey(TK.submitButton), findsOneWidget);
    });

    testWidgets('confirm button shows singular for 1 proposal',
        (tester) async {
      final proposals = createProposals(1);

      await tester.pumpWidget(buildRambleScreen(proposals: proposals));
      await tester.pumpAndSettle();

      expect(find.text('Confirm 1 Action'), findsOneWidget);
    });

    testWidgets('shows action chip for each proposal', (tester) async {
      final proposals = [
        BrainDumpTaskProposal(
          id: 'p1',
          action: 'add',
          content: 'New task',
          category: 'career',
        ),
      ];

      await tester.pumpWidget(buildRambleScreen(proposals: proposals));
      await tester.pumpAndSettle();

      // The action label for 'add' should show 'Add'
      expect(find.text('Add'), findsOneWidget);
    });

    testWidgets('shows priority chip when priority is set', (tester) async {
      final proposals = [
        BrainDumpTaskProposal(
          id: 'p1',
          action: 'add',
          content: 'Important task',
          category: 'career',
          priority: 'high',
        ),
      ];

      await tester.pumpWidget(buildRambleScreen(proposals: proposals));
      await tester.pumpAndSettle();

      expect(find.text('High'), findsOneWidget);
    });

    testWidgets('shows Ramble text in top bar', (tester) async {
      await tester.pumpWidget(buildRambleScreen(proposals: createProposals(1)));
      await tester.pumpAndSettle();

      expect(find.text('Ramble'), findsOneWidget);
    });

    testWidgets('shows close button in top bar', (tester) async {
      await tester.pumpWidget(buildRambleScreen(proposals: createProposals(1)));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });

    testWidgets('confirm button not shown when no proposals', (tester) async {
      await tester.pumpWidget(buildRambleScreen(proposals: []));
      await tester.pumpAndSettle();

      // _buildReviewingBody returns early for empty proposals — no submit button
      expect(find.byKey(TK.submitButton), findsNothing);
      expect(find.text('Confirm 0 Actions'), findsNothing);
      expect(find.text('No tasks detected'), findsOneWidget);
    });
  });
}
