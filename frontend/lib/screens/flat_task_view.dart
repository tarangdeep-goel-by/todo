import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/theme.dart';
import '../models/task.dart';
import '../providers/api_provider.dart';
import '../providers/task_filter_provider.dart';
import '../providers/sync_provider.dart';
import '../providers/task_store_provider.dart';
import '../providers/tutorial_provider.dart';
import '../services/app_logger.dart';
import '../services/onboarding_service.dart';
import '../widgets/empty_state.dart';
import '../widgets/flat_task_row.dart';

import '../widgets/skeleton_loaders.dart';
import '../widgets/swipe_tutorial_overlay.dart';
import '../models/api_error.dart';
import '../services/haptic_service.dart';
import '../services/tracker/tracker.dart';
import '../widgets/filter_sheet.dart';

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
  final _log = AppLogger.instance;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  int _displayCount = 50;
  String _statusFilter = 'all'; // 'all', 'active', 'overdue', 'done'

  Timer? _debounce;
  List<Task>? _searchResults;
  bool _searchLoading = false;
  String? _searchError;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onTutorialStepComplete(int nextStep) {
    _log.debug('flat.tutorialStepComplete', logger: 'FlatTaskView', data: {
      'nextStep': nextStep,
    });
    final currentStep = ref.read(tutorialStepProvider);
    // Only advance sequentially
    if (nextStep != currentStep + 1) return;
    // Brief delay so the user sees the result of their swipe
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (!mounted) return;
      ref.read(tutorialStepProvider.notifier).state = nextStep;
      OnboardingService.setSwipeTutorialStep(nextStep);
      if (nextStep >= 3) {
        // Steps 3+ happen on other screens
        widget.onTutorialComplete?.call();
      }
    });
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
        Tracker.instance.outcome(type: 'search_performed', detail: query, count: response.results.length);
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

  List<Task> _applyStatusFilter(List<Task> tasks) {
    switch (_statusFilter) {
      case 'active':
        return tasks.where((t) => t.isActive && !t.isOverdue).toList();
      case 'overdue':
        return tasks.where((t) => t.isOverdue).toList();
      case 'done':
        return tasks.where((t) => t.isCompleted).toList();
      default:
        return tasks;
    }
  }

  Widget _buildQuickFilterChips() {
    const filters = [
      ('All', 'all'),
      ('Active', 'active'),
      ('Overdue', 'overdue'),
      ('Done', 'done'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: filters.map((f) {
          final isActive = _statusFilter == f.$2;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() {
                _statusFilter = f.$2;
                _displayCount = 50;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0x20FF9A50)
                      : const Color(0x0AF0EBE5),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  f.$1,
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isActive
                        ? const Color(0xFFFF9A50)
                        : const Color(0x66F0EBE5),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
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
    final statusFiltered = _applyStatusFilter(allFiltered);
    final parentNames = ref.watch(l1ParentNamesProvider);
    final paletteMap = ref.watch(domainPalettesProvider);

    // Reset display count when filter changes
    ref.listen(taskFilterProvider, (prev, next) {
      if (prev != next) {
        setState(() => _displayCount = 50);
      }
    });

    // Skeleton on initial load
    if (storeState.isLoading && allFiltered.isEmpty) {
      return const SkeletonTaskList(count: 8);
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
    final filteredTasks = isSearching ? _searchResults! : _applyStatusFilter(allFiltered);
    final displayTasks = isSearching
        ? filteredTasks
        : filteredTasks.take(_displayCount).toList();
    final hasMore = !isSearching && _displayCount < filteredTasks.length;
    final tutorialStep = ref.watch(tutorialStepProvider);
    final isTutorial = widget.tutorialActive && tutorialStep >= 0 && tutorialStep < 3;

    _log.debug('flat.build', logger: 'FlatTaskView', data: {
      'taskCount': allFiltered.length, 'displayCount': displayTasks.length,
      'tutorialActive': widget.tutorialActive, 'swipeStep': tutorialStep,
      'isTutorial': isTutorial,
    });

    return Column(
      children: [
        // Search bar + filter button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
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
              const SizedBox(width: 8),
              _InlineFilterButton(),
            ],
          ),
        ),
        // Stale-data error banner (loaded before, but refresh failed)
        if (storeState.error != null && storeState.hasLoadedOnce)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.navBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Couldn\'t refresh — showing cached data',
                    style: TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 13,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => ref.read(taskStoreProvider.notifier).fetchAll(),
                  child: Icon(Icons.refresh, color: AppColors.darkText, size: 18),
                ),
              ],
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
        // Quick filter chips (hide during search)
        if (!isSearching)
          _buildQuickFilterChips(),
        // Search loading skeleton
        if (_searchLoading)
          const Expanded(
            child: SkeletonTaskList(
              count: 6,
              padding: EdgeInsets.only(top: 8),
            ),
          )
        // Search empty state
        else if (isSearching && _searchResults!.isEmpty)
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
        // Status filter empty state
        else if (statusFiltered.isEmpty && allFiltered.isNotEmpty && _searchResults == null)
          Expanded(
            child: Center(
              child: Text(
                'No $_statusFilter tasks',
                style: const TextStyle(color: AppColors.secondaryText, fontSize: 15),
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
                    return const ShimmerEffect(
                      child: Column(
                        children: [
                          SkeletonTaskRow(),
                          SkeletonTaskRow(),
                        ],
                      ),
                    );
                  }

                  final task = displayTasks[index];
                  // Step 0: first active task (swipe right to complete)
                  // Step 1: first completed task (swipe left to mark active)
                  // Step 2: first active task (swipe left to archive)
                  final bool isTutorialTarget;
                  if (!isTutorial) {
                    isTutorialTarget = false;
                  } else if (tutorialStep == 1) {
                    isTutorialTarget = task.isCompleted &&
                        displayTasks.indexWhere((t) => t.isCompleted) == index;
                  } else {
                    isTutorialTarget = !task.isCompleted &&
                        displayTasks.indexWhere((t) => !t.isCompleted) == index;
                  }

                  final domain = DomainColors.getDomain(task.category, true, paletteMap);
                  final taskItem = FlatTaskRow(
                    key: ValueKey(task.id),
                    task: task,
                    domain: domain,
                    parentName: parentNames[task.id],
                    onTutorialStepComplete:
                        isTutorialTarget ? (step) => _onTutorialStepComplete(step) : null,
                  );

                  if (isTutorialTarget) {
                    return SwipeTutorialOverlay(
                      step: tutorialStep,
                      domainColor: domain.primary,
                      child: taskItem,
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

class _InlineFilterButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(taskFilterProvider);
    final activeCount = filter.activeFilterCount;

    return GestureDetector(
      onTap: () {
        HapticService.medium();
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const FilterSheet(),
        );
      },
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.navBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            Center(
              child: Icon(
                Icons.tune_rounded,
                color: activeCount > 0
                    ? AppColors.darkText
                    : AppColors.secondaryText,
                size: 20,
              ),
            ),
            if (activeCount > 0)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                    color: AppColors.darkText,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$activeCount',
                      style: const TextStyle(
                        color: AppColors.darkBg,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
