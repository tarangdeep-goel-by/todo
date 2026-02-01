import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo/data/database/database.dart';
import 'package:todo/data/repositories/task_repository.dart';
import 'package:todo/data/models/task.dart';

/// Database provider (singleton)
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

/// Task repository provider
final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return TaskRepository(db);
});

/// Provider to seed root categories on app start
final seedRootCategoriesProvider = FutureProvider<void>((ref) async {
  final repository = ref.watch(taskRepositoryProvider);
  await repository.seedRootCategories();
});

/// Provider for tasks by category
final tasksByCategoryProvider =
    FutureProvider.family<List<Task>, TaskCategory>((ref, category) async {
  final repository = ref.watch(taskRepositoryProvider);
  return repository.getTasksByCategory(category);
});

/// Provider for child tasks of a parent
final childTasksProvider =
    FutureProvider.family<List<Task>, String?>((ref, parentId) async {
  final repository = ref.watch(taskRepositoryProvider);
  return repository.getChildTasks(parentId);
});

/// Provider for a single task
final taskProvider = FutureProvider.family<Task?, String>((ref, taskId) async {
  final repository = ref.watch(taskRepositoryProvider);
  return repository.getTask(taskId);
});
