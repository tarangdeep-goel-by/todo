import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/widgets/domain_card.dart';
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
    'work': DomainColors.workDark,
  };

  Widget buildCard({
    required DomainPalette domain,
    required List<Task> tasks,
    double focusProgress = 1.0,
    double height = 400,
  }) {
    return ProviderScope(
      overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
        domainPalettesProvider.overrideWithValue(testPaletteMap),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (_) => DomainCard(
                  domain: domain,
                  tasks: tasks,
                  isDark: true,
                  focusProgress: focusProgress,
                  height: height,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  group('DomainCard', () {
    testWidgets('shows domain name in focused mode', (tester) async {
      await tester.pumpWidget(buildCard(
        domain: DomainColors.workDark,
        tasks: [createTestTask(title: 'task 1', category: 'work')],
        height: 400,
      ));

      expect(find.text('Work'), findsOneWidget);
    });

    testWidgets('shows "N tasks" formatting for multiple active tasks',
        (tester) async {
      final tasks = [
        createTestTask(id: 'id-1', title: 't1', category: 'work'),
        createTestTask(id: 'id-2', title: 't2', category: 'work'),
        createTestTask(id: 'id-3', title: 't3', category: 'work'),
      ];
      await tester.pumpWidget(buildCard(
        domain: DomainColors.workDark,
        tasks: tasks,
        height: 400,
      ));

      expect(find.text('3 tasks'), findsOneWidget);
    });

    testWidgets('shows "1 task" singular', (tester) async {
      final tasks = [
        createTestTask(id: 'id-1', title: 't1', category: 'work'),
      ];
      await tester.pumpWidget(buildCard(
        domain: DomainColors.workDark,
        tasks: tasks,
        height: 400,
      ));

      expect(find.text('1 task'), findsOneWidget);
    });

    testWidgets('shows domain name in compressed mode', (tester) async {
      await tester.pumpWidget(buildCard(
        domain: DomainColors.workDark,
        tasks: [createTestTask(title: 'task 1', category: 'work')],
        height: 60, // small height triggers compressed
      ));

      expect(find.text('Work'), findsOneWidget);
    });

    testWidgets('shows capitalized priority in task rows', (tester) async {
      final tasks = [
        createTestTask(
          id: 'id-1',
          title: 'urgent task',
          category: 'work',
          priority: 'high',
        ),
      ];
      await tester.pumpWidget(buildCard(
        domain: DomainColors.workDark,
        tasks: tasks,
        height: 400,
      ));

      expect(find.text('High'), findsOneWidget);
    });
  });
}
