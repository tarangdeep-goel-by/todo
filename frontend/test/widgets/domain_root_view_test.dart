import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/widgets/domain_root_view.dart';
import 'package:frontend/providers/api_provider.dart';
import 'package:frontend/providers/task_store_provider.dart';

import '../helpers/test_helpers.dart';

void main() {
  late MockApiService mockApi;

  setUp(() {
    mockApi = MockApiService();
  });

  Widget buildView({
    String category = 'career',
    List<Override> extra = const [],
    VoidCallback? onClose,
    void Function(String)? onTaskTap,
  }) {
    return ProviderScope(
      overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
        domainPalettesProvider.overrideWithValue(createTestPaletteMap()),
        ...extra,
      ],
      child: MaterialApp(
        home: DomainRootView(
          category: category,
          canPop: false,
          onNavigateBack: () {},
          onTaskTap: onTaskTap ?? (_) {},
          onClose: onClose ?? () {},
        ),
      ),
    );
  }

  group('DomainRootView', () {
    testWidgets('shows category name capitalized', (tester) async {
      await tester.pumpWidget(buildView(category: 'career'));
      expect(find.text('Career'), findsOneWidget);
    });

    testWidgets('shows No tasks in this domain when no matching tasks',
        (tester) async {
      await tester.pumpWidget(buildView(category: 'career'));
      expect(find.text('No tasks in this domain'), findsOneWidget);
    });

    testWidgets('lists L1 tasks for the category', (tester) async {
      final task1 = createTestTask(
        id: 'id-1',
        title: 'Design mockups',
        category: 'career',
      );
      final task2 = createTestTask(
        id: 'id-2',
        title: 'Fix bug',
        category: 'career',
      );
      // Task in different category should not appear
      final task3 = createTestTask(
        id: 'id-3',
        title: 'Go jogging',
        category: 'health',
      );

      await tester.pumpWidget(buildView(
        category: 'career',
        extra: [
          allTasksProvider.overrideWith((ref) => [task1, task2, task3]),
        ],
      ));

      expect(find.text('Design mockups'), findsOneWidget);
      expect(find.text('Fix bug'), findsOneWidget);
      expect(find.text('Go jogging'), findsNothing);
    });

    testWidgets('shows task count text', (tester) async {
      final task1 = createTestTask(id: 'id-1', title: 'T1', category: 'career');
      final task2 = createTestTask(id: 'id-2', title: 'T2', category: 'career');

      await tester.pumpWidget(buildView(
        category: 'career',
        extra: [
          allTasksProvider.overrideWith((ref) => [task1, task2]),
        ],
      ));

      expect(find.text('2 top-level tasks'), findsOneWidget);
    });

    testWidgets('close button calls onClose callback', (tester) async {
      var closeCalled = false;

      await tester.pumpWidget(buildView(
        category: 'career',
        onClose: () => closeCalled = true,
      ));

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(closeCalled, isTrue);
    });

    testWidgets('task tap calls onTaskTap with task id', (tester) async {
      String? tappedId;
      final task = createTestTask(
        id: 'tap-id-1',
        title: 'Tappable task',
        category: 'career',
      );

      await tester.pumpWidget(buildView(
        category: 'career',
        onTaskTap: (id) => tappedId = id,
        extra: [
          allTasksProvider.overrideWith((ref) => [task]),
        ],
      ));

      await tester.tap(find.text('Tappable task'));
      await tester.pump();

      expect(tappedId, 'tap-id-1');
    });
  });
}
