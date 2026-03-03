import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/widgets/active_filter_chips.dart';
import 'package:frontend/models/task_filter.dart';
import 'package:frontend/providers/task_filter_provider.dart';
import 'package:frontend/providers/task_store_provider.dart';
import 'package:frontend/config/theme.dart';

void main() {
  final testPaletteMap = <String, DomainPalette>{
    'career': DomainColors.careerDark,
    'home': DomainColors.homeDark,
  };

  Widget buildChips({TaskFilter? filter}) {
    return ProviderScope(
      overrides: [
        domainPalettesProvider.overrideWithValue(testPaletteMap),
        if (filter != null)
          taskFilterProvider.overrideWith((ref) => filter),
      ],
      child: const MaterialApp(
        home: Scaffold(body: ActiveFilterChips()),
      ),
    );
  }

  group('ActiveFilterChips', () {
    testWidgets('hidden when filter empty', (tester) async {
      await tester.pumpWidget(buildChips());

      // SizedBox.shrink should be rendered
      expect(find.byType(ActiveFilterChips), findsOneWidget);
      expect(find.text('Clear All'), findsNothing);
    });

    testWidgets('shows category chips', (tester) async {
      await tester.pumpWidget(buildChips(
        filter: TaskFilter(categories: ['career']),
      ));

      expect(find.text('CAREER'), findsOneWidget);
      expect(find.text('Clear All'), findsOneWidget);
    });

    testWidgets('shows priority chips', (tester) async {
      await tester.pumpWidget(buildChips(
        filter: TaskFilter(priorities: ['high']),
      ));

      expect(find.text('PRI: HIGH'), findsOneWidget);
    });

    testWidgets('shows status chips', (tester) async {
      await tester.pumpWidget(buildChips(
        filter: TaskFilter(statuses: ['overdue']),
      ));

      expect(find.text('OVERDUE'), findsOneWidget);
    });
  });
}
