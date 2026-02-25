import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/task_store_provider.dart';
import '../providers/task_filter_provider.dart';
import '../config/theme.dart';
import '../widgets/task_item.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_state.dart';

/// Flat all-tasks view with virtual pagination and client-side filtering
class FlatTaskView extends ConsumerStatefulWidget {
  const FlatTaskView({super.key});

  @override
  ConsumerState<FlatTaskView> createState() => _FlatTaskViewState();
}

class _FlatTaskViewState extends ConsumerState<FlatTaskView> {
  final ScrollController _scrollController = ScrollController();
  int _displayCount = 50;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final allFiltered = ref.read(flatViewTasksProvider);
      if (_displayCount < allFiltered.length) {
        setState(() {
          _displayCount = (_displayCount + 50).clamp(0, allFiltered.length);
        });
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final storeState = ref.watch(taskStoreProvider);
    final allFiltered = ref.watch(flatViewTasksProvider);
    final parentNames = ref.watch(l1ParentNamesProvider);

    // Reset display count when filter changes
    ref.listen(taskFilterProvider, (prev, next) {
      if (prev != next) {
        setState(() => _displayCount = 50);
      }
    });

    // Full spinner only on initial load
    if (storeState.isLoading && allFiltered.isEmpty) {
      return const LoadingState();
    }

    if (storeState.error != null && allFiltered.isEmpty) {
      return EmptyState(
        message: 'Unable to load tasks\n${storeState.error}',
        textColor: AppColors.darkText,
        icon: Icons.error_outline,
        onRetry: () => ref.read(taskStoreProvider.notifier).fetchAll(),
      );
    }

    if (allFiltered.isEmpty) {
      return const EmptyState(
        title: 'All clear',
        message: 'Your tasks will appear here.\nSpeak or type a command below to get started.',
        textColor: AppColors.darkText,
        icon: Icons.task_alt,
        examples: [
          'Add meeting prep to work',
          'Buy milk, high priority, due tomorrow',
        ],
      );
    }

    final displayTasks = allFiltered.take(_displayCount).toList();
    final hasMore = _displayCount < allFiltered.length;

    return RefreshIndicator(
      color: AppColors.darkText,
      backgroundColor: AppColors.darkBg,
      onRefresh: () => ref.read(taskStoreProvider.notifier).fetchAll(),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.only(bottom: 120),
        itemCount: displayTasks.length + (hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == displayTasks.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(
                  color: AppColors.darkText,
                ),
              ),
            );
          }
          return TaskItem(
            task: displayTasks[index],
            isDark: true,
            parentName: parentNames[displayTasks[index].id],
          );
        },
      ),
    );
  }
}
