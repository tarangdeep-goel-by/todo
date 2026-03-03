import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/widgets/filter_button.dart';
import 'package:frontend/models/task_filter.dart';
import 'package:frontend/providers/task_filter_provider.dart';
import 'package:frontend/providers/task_store_provider.dart';
import 'package:frontend/providers/api_provider.dart';
import '../helpers/test_helpers.dart';

void main() {
  late MockApiService mockApi;

  setUp(() {
    mockApi = MockApiService();
  });

  Widget buildFilterButton({TaskFilter? filter}) {
    return ProviderScope(
      overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
        domainPalettesProvider.overrideWithValue(createTestPaletteMap()),
        if (filter != null)
          taskFilterProvider.overrideWith((ref) => filter),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Stack(
            children: const [FilterButton()],
          ),
        ),
      ),
    );
  }

  group('FilterButton', () {
    testWidgets('renders tune_rounded icon', (tester) async {
      await tester.pumpWidget(buildFilterButton());
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
    });

    testWidgets('no badge when filter is default', (tester) async {
      await tester.pumpWidget(buildFilterButton());

      // The badge text should not exist when activeFilterCount == 0
      // Badge shows a number text inside a circle
      expect(find.text('0'), findsNothing);
      expect(find.text('1'), findsNothing);
    });

    testWidgets('badge shows count when filter has categories set',
        (tester) async {
      await tester.pumpWidget(buildFilterButton(
        filter: const TaskFilter(categories: ['career']),
      ));

      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('tap opens bottom sheet', (tester) async {
      await tester.pumpWidget(buildFilterButton());

      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();

      // FilterSheet renders section titles like 'CATEGORY'
      expect(find.text('CATEGORY'), findsOneWidget);
    });
  });
}
