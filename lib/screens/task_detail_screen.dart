import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:todo/providers/task_provider.dart';

/// Task detail screen
class TaskDetailScreen extends ConsumerWidget {
  final String taskId;

  const TaskDetailScreen({
    super.key,
    required this.taskId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskAsync = ref.watch(taskProvider(taskId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Task Details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: taskAsync.when(
        data: (task) {
          if (task == null) {
            return const Center(
              child: Text('Task not found'),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(
                  task.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),

                // Category
                Chip(
                  label: Text(task.category.name.toUpperCase()),
                ),
                const SizedBox(height: 16),

                // Description
                if (task.description != null) ...[
                  Text(
                    'Description',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(task.description!),
                  const SizedBox(height: 16),
                ],

                // Transcription
                Text(
                  'Transcription',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(task.transcription),
                const SizedBox(height: 16),

                // AI Placement
                Text(
                  'AI Suggestion',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text('Confidence: ${(task.aiPlacement.confidence * 100).toStringAsFixed(0)}%'),
                const SizedBox(height: 4),
                Text('Reasoning: ${task.aiPlacement.reasoning}'),
                const SizedBox(height: 16),

                // Timestamps
                Text(
                  'Created',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(task.createdAt.toString()),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text('Error: $error'),
        ),
      ),
    );
  }
}
