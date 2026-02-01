import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo/data/models/task.dart';
import 'package:todo/widgets/task_tree.dart';
import 'package:todo/providers/task_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:todo/config/router.dart';

/// Work category screen
class WorkScreen extends ConsumerWidget {
  const WorkScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Ensure root categories are seeded
    ref.watch(seedRootCategoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Work'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(childTasksProvider);
        },
        child: TaskTreeList(
          category: TaskCategory.work,
          onTaskTap: (task) {
            context.push(
              AppRouter.taskDetail.replaceAll(':id', task.id),
            );
          },
          onTaskComplete: (task, completed) async {
            final repository = ref.read(taskRepositoryProvider);
            if (completed) {
              await repository.markTaskDone(task.id);
            } else {
              await repository.updateTask(
                task.id,
                status: TaskStatus.active,
              );
            }
            // Refresh the list
            ref.invalidate(childTasksProvider);
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          context.push(AppRouter.addTask);
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
