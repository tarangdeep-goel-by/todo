import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/widgets/flat_task_row.dart';
import 'package:frontend/providers/api_provider.dart';
import 'package:frontend/providers/mutation_provider.dart';
import 'package:frontend/providers/task_store_provider.dart';
import 'package:frontend/config/theme.dart';
import 'package:frontend/models/task.dart';
import 'package:frontend/services/task_mutation_service.dart';
import '../helpers/test_helpers.dart';

/// In-memory mutation service that logs and upserts to store.
class InMemoryMutationService implements TaskMutationService {
  final TaskStoreNotifier store;
  final List<Map<String, dynamic>> mutations = [];

  InMemoryMutationService(this.store);

  @override
  Future<void> updateTask(Task optimistic, Map<String, dynamic> payload) async {
    debugPrint('[Mutation] updateTask: optimistic.status=${optimistic.status}, payload=$payload');
    mutations.add({'action': 'update', 'task': optimistic, 'payload': payload});
    store.upsertTask(optimistic);
  }

  @override
  Future<void> createTask(Task optimistic, Map<String, dynamic> payload) async {
    store.upsertTask(optimistic);
  }

  @override
  Future<void> completeTask(Task task) async {
    store.completeWithDescendants(task.id);
  }

  @override
  Future<void> deleteTask(Task task) async {
    store.removeTask(task.id);
  }

  @override
  Future<void> archiveTask(Task task) async {
    store.archiveWithDescendants(task.id);
  }

  @override
  Future<void> restoreTask(Task task) async {
    store.restoreWithDescendants(task.id);
  }
}

void main() {
  late MockApiService mockApi;

  setUp(() {
    mockApi = MockApiService();
  });

  final testPaletteMap = <String, DomainPalette>{
    'career': DomainColors.careerDark,
    'home': DomainColors.homeDark,
  };

  group('Undo toggle flow', () {
    testWidgets('swipe complete then undo restores active state', (tester) async {
      final task = createTestTask(
        id: 'undo-test-1',
        title: 'undo me',
        category: 'career',
        status: 'active',
      );

      late InMemoryMutationService mutationSvc;

      final container = ProviderContainer(overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
        domainPalettesProvider.overrideWithValue(testPaletteMap),
        taskStoreProvider.overrideWith((ref) {
          final notifier = TaskStoreNotifier(ref);
          notifier.upsertTask(task);
          mutationSvc = InMemoryMutationService(notifier);
          return notifier;
        }),
        taskMutationServiceProvider.overrideWith((ref) {
          return mutationSvc;
        }),
      ]);

      // Force initialization
      container.read(taskStoreProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Overlay(
                initialEntries: [
                  OverlayEntry(
                    builder: (_) => SizedBox(
                      width: 400,
                      height: 80,
                      child: FlatTaskRow(
                        task: task,
                        domain: DomainColors.careerDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Verify task starts as active
      var storeTask = container.read(taskStoreProvider).tasks['undo-test-1'];
      debugPrint('\n=== BEFORE SWIPE ===');
      debugPrint('status: ${storeTask?.status}');
      expect(storeTask?.status, 'active');

      // Swipe right to complete
      debugPrint('\n=== SWIPING RIGHT ===');
      final dismissible = find.byType(Dismissible);
      debugPrint('Found ${dismissible.evaluate().length} Dismissible widgets');
      await tester.drag(dismissible, const Offset(400, 0));
      await tester.pumpAndSettle();

      storeTask = container.read(taskStoreProvider).tasks['undo-test-1'];
      debugPrint('\n=== AFTER SWIPE ===');
      debugPrint('status: ${storeTask?.status}');
      debugPrint('completedAt: ${storeTask?.completedAt}');
      debugPrint('mutations: ${mutationSvc.mutations.length}');

      expect(storeTask?.status, 'completed',
          reason: 'Task should be completed after swipe');

      // Find and tap Undo
      final undoFinder = find.text('Undo');
      debugPrint('\n=== UNDO ===');
      debugPrint('Undo found: ${undoFinder.evaluate().length}');
      expect(undoFinder, findsOneWidget);

      await tester.tap(undoFinder);
      await tester.pumpAndSettle();

      storeTask = container.read(taskStoreProvider).tasks['undo-test-1'];
      debugPrint('\n=== AFTER UNDO ===');
      debugPrint('status: ${storeTask?.status}');
      debugPrint('completedAt: ${storeTask?.completedAt}');
      debugPrint('total mutations: ${mutationSvc.mutations.length}');
      for (var i = 0; i < mutationSvc.mutations.length; i++) {
        final m = mutationSvc.mutations[i];
        final t = m['task'] as Task;
        debugPrint('  [$i] task.status=${t.status}, task.completedAt=${t.completedAt}, payload=${m['payload']}');
      }

      expect(storeTask?.status, 'active',
          reason: 'Task should be active after undo');
      expect(storeTask?.completedAt, isNull,
          reason: 'completedAt should be null after undo');
    });
  });
}
