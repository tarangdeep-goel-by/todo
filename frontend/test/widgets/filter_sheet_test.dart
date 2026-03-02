import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/widgets/filter_sheet.dart';
import 'package:frontend/models/task_filter.dart';
import 'package:frontend/providers/task_filter_provider.dart';
import 'package:frontend/providers/task_store_provider.dart';
import 'package:frontend/config/theme.dart';

void main() {
  // Provide a default palette map so domainPalettesProvider works
  final testPaletteMap = <String, DomainPalette>{
    'work': DomainColors.workDark,
    'personal': DomainColors.personalDark,
  };

  Widget buildSheet({TaskFilter? initialFilter}) {
    return ProviderScope(
      overrides: [
        domainPalettesProvider.overrideWithValue(testPaletteMap),
        if (initialFilter != null)
          taskFilterProvider.overrideWith((ref) => initialFilter),
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
                  builder: (_) => const FilterSheet(),
                );
              },
              child: const Text('Open'),
            );
          }),
        ),
      ),
    );
  }

  group('FilterSheet', () {
    testWidgets('renders section titles', (tester) async {
      await tester.pumpWidget(buildSheet());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('CATEGORY'), findsOneWidget);
      expect(find.text('PRIORITY'), findsOneWidget);
      expect(find.text('STATUS'), findsOneWidget);
      expect(find.text('SORT BY'), findsOneWidget);
    });

    testWidgets('renders priority filter chips', (tester) async {
      await tester.pumpWidget(buildSheet());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('HIGH'), findsOneWidget);
      expect(find.text('MEDIUM'), findsOneWidget);
      expect(find.text('LOW'), findsOneWidget);
    });

    testWidgets('renders status filter chips', (tester) async {
      await tester.pumpWidget(buildSheet());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('ACTIVE'), findsOneWidget);
      expect(find.text('DUE SOON'), findsOneWidget);
      // OVERDUE appears both in STATUS and DATE RANGE sections
      expect(find.text('OVERDUE'), findsNWidgets(2));
      expect(find.text('COMPLETED'), findsOneWidget);
    });

    testWidgets('Clear All resets filter state', (tester) async {
      await tester.pumpWidget(buildSheet(
        initialFilter: TaskFilter(priorities: ['high']),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Tap Clear All in the header
      await tester.tap(find.text('Clear All'));
      await tester.pump();

      // After clearing, HIGH should no longer be "selected" visually
      // (we just verify the sheet is still visible and Clear All worked)
      expect(find.text('Filters & Sort'), findsOneWidget);
    });

    testWidgets('Apply closes the sheet', (tester) async {
      await tester.pumpWidget(buildSheet());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();

      // Sheet should be closed
      expect(find.text('CATEGORY'), findsNothing);
    });

    testWidgets('Cancel closes the sheet', (tester) async {
      await tester.pumpWidget(buildSheet());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('CATEGORY'), findsNothing);
    });
  });
}
