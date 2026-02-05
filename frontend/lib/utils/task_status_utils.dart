import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/task.dart';
import '../providers/task_filter_provider.dart';

/// Get the effective status of a task, accounting for optimistic overrides.
String effectiveStatus(WidgetRef ref, Task task) {
  final overrides = ref.watch(taskStatusOverrideProvider);
  return overrides[task.id] ?? task.status;
}

extension TaskStatusExtension on Task {
  String effectiveStatusFrom(Map<String, String> overrides) =>
      overrides[id] ?? status;

  bool isEffectivelyCompletedFrom(Map<String, String> overrides) =>
      effectiveStatusFrom(overrides) == 'completed';
}
