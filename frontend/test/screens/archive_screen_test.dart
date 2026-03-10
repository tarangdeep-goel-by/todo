import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:frontend/screens/archive_screen.dart';
import 'package:frontend/providers/api_provider.dart';
import '../helpers/test_helpers.dart';

void main() {
  late MockApiService mockApi;

  setUp(() {
    mockApi = MockApiService();
  });

  Widget buildWidget({List<Override> overrides = const []}) {
    return ProviderScope(
      overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
        ...overrides,
      ],
      child: const MaterialApp(
        home: ArchiveScreen(),
      ),
    );
  }

  group('ArchiveScreen', () {
    testWidgets('shows empty state when no archived tasks', (tester) async {
      when(() => mockApi.getArchivedTasks(
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).thenAnswer((_) async => []);

      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      expect(find.text('No archived tasks'), findsOneWidget);
      expect(find.text('Archive'), findsOneWidget);
    });

    testWidgets('loads and displays archived tasks', (tester) async {
      final archivedTask = createTestTask(
        id: 'archived-1',
        title: 'old task',
        archivedAt: DateTime.now().subtract(const Duration(days: 3)),
      );
      when(() => mockApi.getArchivedTasks(
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).thenAnswer((_) async => [archivedTask]);

      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      expect(find.text('Old task'), findsOneWidget);
    });

    testWidgets('shows footer text about auto-deletion', (tester) async {
      when(() => mockApi.getArchivedTasks(
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).thenAnswer((_) async => [
                createTestTask(
                  id: 'a1',
                  title: 'task',
                  archivedAt: DateTime.now(),
                ),
              ]);

      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      expect(find.text('Tasks are auto-deleted after 30 days'), findsOneWidget);
    });

    testWidgets('shows error state on API failure', (tester) async {
      when(() => mockApi.getArchivedTasks(
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).thenThrow(Exception('network error'));

      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      expect(find.text('Could not load archived tasks.'), findsOneWidget);
    });
  });
}
