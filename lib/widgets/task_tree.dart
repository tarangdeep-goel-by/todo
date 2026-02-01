import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo/data/models/task.dart';
import 'package:todo/widgets/task_card.dart';
import 'package:todo/widgets/empty_state.dart';
import 'package:todo/providers/task_provider.dart';

/// Recursive task tree widget
class TaskTree extends ConsumerStatefulWidget {
  final Task task;
  final int depth;
  final Function(Task)? onTaskTap;
  final Function(Task, bool)? onTaskComplete;

  const TaskTree({
    super.key,
    required this.task,
    this.depth = 0,
    this.onTaskTap,
    this.onTaskComplete,
  });

  @override
  ConsumerState<TaskTree> createState() => _TaskTreeState();
}

class _TaskTreeState extends ConsumerState<TaskTree> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    final childTasksAsync = ref.watch(childTasksProvider(widget.task.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Task card
        childTasksAsync.when(
          data: (children) {
            final activeChildren =
                children.where((t) => t.status != TaskStatus.archived).toList();

            return TaskCard(
              task: widget.task,
              depth: widget.depth,
              hasChildren: activeChildren.isNotEmpty,
              isExpanded: _isExpanded,
              onTap: () => widget.onTaskTap?.call(widget.task),
              onExpand: (expanded) {
                setState(() {
                  _isExpanded = expanded;
                });
              },
              onComplete: (completed) {
                widget.onTaskComplete?.call(widget.task, completed);
              },
            );
          },
          loading: () => TaskCard(
            task: widget.task,
            depth: widget.depth,
            hasChildren: false,
            isExpanded: false,
          ),
          error: (error, stack) => TaskCard(
            task: widget.task,
            depth: widget.depth,
            hasChildren: false,
            isExpanded: false,
          ),
        ),

        // Children (if expanded)
        if (_isExpanded)
          childTasksAsync.when(
            data: (children) {
              final activeChildren =
                  children.where((t) => t.status != TaskStatus.archived).toList();

              if (activeChildren.isEmpty) {
                return const SizedBox.shrink();
              }

              return Column(
                children: activeChildren.map((child) {
                  return TaskTree(
                    task: child,
                    depth: widget.depth + 1,
                    onTaskTap: widget.onTaskTap,
                    onTaskComplete: widget.onTaskComplete,
                  );
                }).toList(),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stack) => Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text('Error loading children: $error'),
            ),
          ),
      ],
    );
  }
}

/// Task tree list for a category
class TaskTreeList extends ConsumerWidget {
  final TaskCategory category;
  final Function(Task)? onTaskTap;
  final Function(Task, bool)? onTaskComplete;

  const TaskTreeList({
    super.key,
    required this.category,
    this.onTaskTap,
    this.onTaskComplete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rootId = category == TaskCategory.work
        ? 'root-work'
        : 'root-personal';

    final taskAsync = ref.watch(taskProvider(rootId));
    final childTasksAsync = ref.watch(childTasksProvider(rootId));

    return taskAsync.when(
      data: (rootTask) {
        if (rootTask == null) {
          return const EmptyState(
            message: 'Category not found',
            icon: Icons.error_outline,
          );
        }

        return childTasksAsync.when(
          data: (children) {
            final activeChildren =
                children.where((t) => t.status != TaskStatus.archived).toList();

            if (activeChildren.isEmpty) {
              return EmptyState(
                message: 'No tasks yet.\nTap + to add your first task!',
                icon: Icons.task_outlined,
              );
            }

            return ListView(
              padding: const EdgeInsets.all(16.0),
              children: activeChildren.map((child) {
                return TaskTree(
                  task: child,
                  depth: 0,
                  onTaskTap: onTaskTap,
                  onTaskComplete: onTaskComplete,
                );
              }).toList(),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => EmptyState(
            message: 'Error loading tasks: $error',
            icon: Icons.error_outline,
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => EmptyState(
        message: 'Error loading category: $error',
        icon: Icons.error_outline,
      ),
    );
  }
}
