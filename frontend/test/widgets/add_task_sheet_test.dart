import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/widgets/add_task_sheet.dart';
import 'package:frontend/providers/api_provider.dart';
import 'package:frontend/providers/task_store_provider.dart';
import 'package:frontend/services/tracker/tracker_keys.dart';
import '../helpers/test_helpers.dart';

void main() {
  late MockApiService mockApi;

  setUp(() {
    mockApi = MockApiService();
  });

  /// Render AddTaskSheet directly inside a Scaffold
  Widget buildDirect({List<Override> extra = const []}) {
    return ProviderScope(
      overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
        domainPalettesProvider.overrideWithValue(createTestPaletteMap()),
        ...extra,
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: AddTaskSheet(),
        ),
      ),
    );
  }

  group('AddTaskSheet', () {
    testWidgets('renders text field with hint', (tester) async {
      await tester.pumpWidget(buildDirect());
      await tester.pumpAndSettle();

      expect(find.byKey(TK.addTaskTextField), findsOneWidget);
      expect(find.text('What needs to be done?'), findsOneWidget);
    });

    testWidgets('renders domain chip defaulting to Home', (tester) async {
      await tester.pumpWidget(buildDirect());
      await tester.pumpAndSettle();

      expect(find.byKey(TK.domainChip), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('renders priority chip', (tester) async {
      await tester.pumpWidget(buildDirect());
      await tester.pumpAndSettle();

      expect(find.byKey(TK.priorityChip), findsOneWidget);
    });

    testWidgets('renders due date chip', (tester) async {
      await tester.pumpWidget(buildDirect());
      await tester.pumpAndSettle();

      expect(find.byKey(TK.dueDateChip), findsOneWidget);
    });

    testWidgets('renders parent chip', (tester) async {
      await tester.pumpWidget(buildDirect());
      await tester.pumpAndSettle();

      expect(find.byKey(TK.parentChip), findsOneWidget);
    });

    testWidgets('renders send button', (tester) async {
      await tester.pumpWidget(buildDirect());
      await tester.pumpAndSettle();

      expect(find.byKey(TK.sendButton), findsOneWidget);
    });

    testWidgets('tapping priority chip cycles through values', (tester) async {
      await tester.pumpWidget(buildDirect());
      await tester.pumpAndSettle();

      // Initially no priority label visible (just the flag icon)
      expect(find.text('Low'), findsNothing);

      // Tap once → low
      await tester.tap(find.byKey(TK.priorityChip));
      await tester.pumpAndSettle();
      expect(find.text('Low'), findsOneWidget);

      // Tap again → medium
      await tester.tap(find.byKey(TK.priorityChip));
      await tester.pumpAndSettle();
      expect(find.text('Medium'), findsOneWidget);

      // Tap again → high
      await tester.tap(find.byKey(TK.priorityChip));
      await tester.pumpAndSettle();
      expect(find.text('High'), findsOneWidget);

      // Tap again → back to none
      await tester.tap(find.byKey(TK.priorityChip));
      await tester.pumpAndSettle();
      expect(find.text('High'), findsNothing);
      expect(find.text('Medium'), findsNothing);
      expect(find.text('Low'), findsNothing);
    });
  });
}
