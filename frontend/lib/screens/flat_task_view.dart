import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/theme.dart';
import '../models/task.dart';
import '../providers/api_provider.dart';
import '../providers/task_filter_provider.dart';
import '../providers/sync_provider.dart';
import '../providers/task_store_provider.dart';
import '../services/onboarding_service.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_state.dart';
import '../widgets/swipe_tutorial_overlay.dart';
import '../widgets/task_item.dart';
import '../models/api_error.dart';
import '../services/analytics_service.dart';

/// Flat all-tasks view with virtual pagination and client-side filtering
class FlatTaskView extends ConsumerStatefulWidget {
  final bool tutorialActive;
  final VoidCallback? onTutorialComplete;

  const FlatTaskView({
    super.key,
    this.tutorialActive = false,
    this.onTutorialComplete,
  });

  @override
  ConsumerState<FlatTaskView> createState() => _FlatTaskViewState();
}

class _FlatTaskViewState extends ConsumerState<FlatTaskView> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  int _displayCount = 50;
  int _swipeTutorialStep = 0;

  Timer? _debounce;
  List<Task>? _searchResults;
  bool _searchLoading = false;
  String? _searchError;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    if (widget.tutorialActive) {
      _loadTutorialStep();
    }
  }

  Future<void> _loadTutorialStep() async {
    final step = await OnboardingService.getSwipeTutorialStep();
    if (mounted) {
      setState(() => _swipeTutorialStep = step);
    }
  }

  void _onTutorialStepComplete(int nextStep) async {
    // Only advance sequentially — prevents regression from wrong swipe direction
    if (nextStep != _swipeTutorialStep + 1) return;
    await OnboardingService.setSwipeTutorialStep(nextStep);
    if (mounted) {
      setState(() => _swipeTutorialStep = nextStep);
    }
    if (nextStep >= 3) {
      widget.onTutorialComplete?.call();
    }
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

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = null;
        _searchLoading = false;
        _searchError = null;
      });
      return;
    }
    setState(() => _searchLoading = true);
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query.trim());
    });
  }

  Future<void> _performSearch(String query) async {
    try {
      final apiService = ref.read(apiServiceProvider);
      final response = await apiService.searchTasks(
        query,
      );
      if (mounted && _searchController.text.trim() == query) {
        AnalyticsService.instance.trackSearchPerformed(
          queryLength: query.length,
          resultCount: response.results.length,
        );
        setState(() {
          _searchResults = response.results.map((r) => r.task).toList();
          _searchLoading = false;
          _searchError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        String message;
        if (e is ApiError) {
          switch (e.type) {
            case ApiErrorType.network:
              message = 'Network error — check your connection';
            case ApiErrorType.timeout:
              message = 'Search timed out — try again';
            case ApiErrorType.server:
              message = 'Server error — try again later';
            default:
              message = 'Search failed';
          }
        } else {
          message = 'Search failed';
        }
        setState(() {
          _searchError = message;
          _searchLoading = false;
        });
      }
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchResults = null;
      _searchLoading = false;
      _searchError = null;
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final storeState = ref.watch(taskStoreProvider);
    final allFiltered = ref.watch(flatViewTasksProvider);
    final parentNames = ref.watch(l1ParentNamesProvider);
    final paletteMap = ref.watch(domainPalettesProvider);

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

    if (storeState.error != null && !storeState.hasLoadedOnce && allFiltered.isEmpty) {
      return EmptyState(
        message: 'Something went wrong loading your tasks.',
        textColor: AppColors.darkText,
        icon: Icons.error_outline,
        onRetry: () => ref.read(taskStoreProvider.notifier).fetchAll(),
      );
    }

    if (allFiltered.isEmpty && _searchResults == null) {
      return const EmptyState(
        title: 'All clear',
        message:
            'Your tasks will appear here.\nSpeak or type below to add your first task.',
        textColor: AppColors.darkText,
        icon: Icons.task_alt,
        examples: [
          'Add meeting prep to career',
          'Buy milk, high priority, due tomorrow',
        ],
      );
    }

    final isSearching = _searchResults != null;
    final displaySource = isSearching ? _searchResults! : allFiltered;
    final displayTasks = isSearching
        ? displaySource
        : displaySource.take(_displayCount).toList();
    final hasMore = !isSearching && _displayCount < allFiltered.length;
    final isTutorial = widget.tutorialActive && _swipeTutorialStep < 3;

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            style: const TextStyle(color: AppColors.darkText, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Search tasks...',
              hintStyle: const TextStyle(
                color: AppColors.secondaryText,
                fontSize: 15,
              ),
              prefixIcon: const Icon(
                Icons.search,
                color: AppColors.secondaryText,
                size: 20,
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: AppColors.secondaryText,
                        size: 20,
                      ),
                      onPressed: _clearSearch,
                    )
                  : null,
              filled: true,
              fillColor: AppColors.navBg,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        // Search loading indicator
        if (_searchLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              height: 2,
              child: LinearProgressIndicator(
                color: AppColors.darkText,
                backgroundColor: AppColors.navBg,
              ),
            ),
          ),
        // Search error indicator
        if (_searchError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: AppColors.overdue, size: 16),
                const SizedBox(width: 8),
                Text(
                  _searchError!,
                  style: const TextStyle(color: AppColors.overdue, fontSize: 13),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => _performSearch(_searchController.text.trim()),
                  child: const Icon(Icons.refresh, color: AppColors.darkText, size: 18),
                ),
              ],
            ),
          ),
        // Search empty state
        if (isSearching && _searchResults!.isEmpty && !_searchLoading)
          const Expanded(
            child: Center(
              child: Text(
                'No matching tasks found.',
                style: TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 15,
                ),
              ),
            ),
          )
        // Task list
        else
          Expanded(
            child: RefreshIndicator(
              color: AppColors.darkText,
              backgroundColor: AppColors.darkBg,
              onRefresh: () => ref.read(syncServiceProvider).sync(),
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

                  final task = displayTasks[index];
                  final isDemoTask =
                      task.id == OnboardingService.demoTaskId;

                  final taskItem = TaskItem(
                    key: ValueKey(task.id),
                    task: task,
                    isDark: true,
                    parentName: parentNames[task.id],
                    onTutorialStepComplete:
                        isDemoTask ? _onTutorialStepComplete : null,
                  );

                  // Wrap demo task with tutorial overlay
                  if (isDemoTask && isTutorial) {
                    final domain = DomainColors.getDomain(
                        task.category, true, paletteMap);
                    return Stack(
                      children: [
                        taskItem,
                        Positioned.fill(
                          child: SwipeTutorialOverlay(
                            step: _swipeTutorialStep,
                            domainColor: domain.primary,
                          ),
                        ),
                      ],
                    );
                  }

                  return taskItem;
                },
              ),
            ),
          ),
      ],
    );
  }
}
