import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/task.dart';
import '../models/api_response.dart';
import '../providers/api_provider.dart';
import '../providers/task_filter_provider.dart';
import '../services/haptic_service.dart';

/// Shared toggle function used by both TaskItem and DomainCard.
///
/// 1. Computes newStatus from current effective status
/// 2. Immediately writes override (instant UI)
/// 3. Fires API call
/// 4. On success: updates accumulated tasks in-place, override persists until next refresh
/// 5. On failure: removes override / rollback (staleness guard)
Future<void> toggleTaskStatus(
  BuildContext context,
  WidgetRef ref,
  Task task,
) async {
  final overrides = ref.read(taskStatusOverrideProvider);
  final currentStatus = overrides[task.id] ?? task.status;
  final newStatus = currentStatus == 'completed' ? 'active' : 'completed';

  HapticService.light();

  // 1. Immediately write override — UI rebuilds instantly
  ref.read(taskStatusOverrideProvider.notifier).state = {
    ...ref.read(taskStatusOverrideProvider),
    task.id: newStatus,
  };

  try {
    // 2. Fire API call
    final apiService = ref.read(apiServiceProvider);
    await apiService.updateTask(
      task.id,
      UpdateTaskRequest(
        status: newStatus,
        completedAt: newStatus == 'completed' ? DateTime.now() : null,
      ),
    );

    // 3. On success: update accumulated tasks for future loadMore consistency.
    // Override stays — task props won't update until next full refresh,
    // which clears overrides anyway.
    ref.read(updateAccumulatedTaskStatusProvider)(task.id, newStatus);

    // 4. Show snackbar
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newStatus == 'completed'
              ? 'Completed: ${task.title}'
              : 'Restored: ${task.title}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  } catch (e) {
    // Rollback: remove override (staleness guard)
    final current = ref.read(taskStatusOverrideProvider);
    if (current[task.id] == newStatus) {
      final updated = Map<String, String>.from(current)..remove(task.id);
      ref.read(taskStatusOverrideProvider.notifier).state = updated;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update task: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}
