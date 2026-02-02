import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/task.dart';
import '../config/constants.dart';
import 'api_provider.dart';

/// Provider for all tasks for the default user
final tasksProvider = FutureProvider<List<Task>>((ref) async {
  final apiService = ref.watch(apiServiceProvider);
  return await apiService.getTasks(AppConstants.defaultUserId);
});

/// Provider for tasks by category (family provider)
final tasksByCategoryProvider = FutureProvider.family<List<Task>, String>((ref, category) async {
  final apiService = ref.watch(apiServiceProvider);
  return await apiService.getTasksByCategory(AppConstants.defaultUserId, category);
});

/// Provider for filtering tasks by parent ID
final tasksByParentProvider = Provider.family<List<Task>, String?>((ref, parentId) {
  final tasksAsync = ref.watch(tasksProvider);

  return tasksAsync.when(
    data: (tasks) => tasks.where((task) => task.parentId == parentId).toList(),
    loading: () => [],
    error: (error, stack) => [],
  );
});
