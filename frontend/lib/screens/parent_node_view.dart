import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/theme.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../config/constants.dart';
import '../models/task.dart';
import '../providers/api_provider.dart';
import '../providers/task_store_provider.dart';
import '../widgets/domain_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_state.dart';
import '../widgets/styled_snackbar.dart';
import '../utils/liquid_focus_scroll.dart';
import '../services/haptic_service.dart';

/// Parent node view with liquid focus domain cards
/// All cards visible at once, scrolling changes focus
class ParentNodeView extends ConsumerStatefulWidget {
  const ParentNodeView({super.key});

  @override
  ConsumerState<ParentNodeView> createState() => _ParentNodeViewState();
}

class _ParentNodeViewState extends ConsumerState<ParentNodeView>
    with SingleTickerProviderStateMixin {
  int _focusedIndex = 0;
  int _previousFocusedIndex = 0;

  // Smooth focus transition
  late AnimationController _focusAnimController;
  late Animation<double> _focusAnimation;

  // Pointer tracking for vertical drag (using Listener to avoid gesture arena
  // conflict with Dismissible's horizontal swipe)
  double _pointerStartY = 0.0;
  double _pointerStartX = 0.0;
  bool _isVerticalDrag = false;
  bool _directionDecided = false;

  @override
  void initState() {
    super.initState();
    _focusAnimController = AnimationController(
      duration: AppAnimations.cardExpand,
      vsync: this,
    );
    _focusAnimation = CurvedAnimation(
      parent: _focusAnimController,
      curve: AppAnimations.easeOutQuint,
    );
    _focusAnimController.value = 1.0; // Start settled
  }

  @override
  void dispose() {
    _focusAnimController.dispose();
    super.dispose();
  }

  /// Smoothly transition focus to a new index
  void _setFocusedIndex(int newIndex) {
    if (newIndex == _focusedIndex) return;
    _previousFocusedIndex = _focusedIndex;
    _focusedIndex = newIndex;
    _focusAnimController.forward(from: 0.0);
  }

  /// Get ordered domain palettes from the canonical provider.
  List<DomainPalette> _getDomains() {
    final paletteMap = ref.read(domainPalettesProvider);
    return paletteMap.values.toList();
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointerStartY = event.position.dy;
    _pointerStartX = event.position.dx;
    _isVerticalDrag = false;
    _directionDecided = false;
  }

  void _onPointerMove(PointerMoveEvent event, int domainCount) {
    final dx = (event.position.dx - _pointerStartX).abs();
    final dy = (event.position.dy - _pointerStartY).abs();

    // Decide direction once after enough movement
    if (!_directionDecided && (dx > 10 || dy > 10)) {
      _isVerticalDrag = dy > dx;
      _directionDecided = true;
    }

    // Only handle vertical drags — let Dismissible handle horizontal
    if (!_isVerticalDrag) return;

    final dragDistance = event.position.dy - _pointerStartY;
    final viewportHeight = MediaQuery.of(context).size.height;
    final threshold = viewportHeight * 0.05;

    if (dragDistance > threshold && _focusedIndex > 0) {
      HapticService.selection();
      _pointerStartY = event.position.dy;
      _setFocusedIndex(_focusedIndex - 1);
    } else if (dragDistance < -threshold &&
        _focusedIndex < domainCount - 1) {
      HapticService.selection();
      _pointerStartY = event.position.dy;
      _setFocusedIndex(_focusedIndex + 1);
    }
  }

  void _onPointerUp(PointerUpEvent event, int domainCount) {
    setState(() {
      _isVerticalDrag = false;
      _directionDecided = false;
    });
  }

  Future<void> _deleteDomain(
      DomainPalette domain, List<Task> domainTasks) async {
    final confirmed = await _confirmDeleteDomain(domain, domainTasks.length);
    if (!confirmed || !mounted) return;
    await _performDeleteDomain(domain, domainTasks);
  }

  /// Shows a confirmation dialog for domain deletion.
  /// Returns true if the user confirmed, false otherwise.
  Future<bool> _confirmDeleteDomain(
      DomainPalette domain, int taskCount) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkBg,
        title: Text(
          'Delete ${domain.name}?',
          style: AppTypography.ctaLabelText(color: AppColors.darkText)
              .copyWith(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This will permanently delete all $taskCount ${taskCount == 1 ? 'task' : 'tasks'} in this domain.',
          style: AppTypography.metadataText(
            color: AppColors.darkText.withValues(alpha: 0.8),
          ).copyWith(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: AppTypography.ctaLabelText(
                color: AppColors.darkText.withValues(alpha: 0.6),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.deleteAction,
            ),
            child: Text(
              'Delete',
              style: AppTypography.ctaLabelText(
                color: AppColors.deleteAction,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  /// Performs the domain deletion: optimistic removal, API calls, rollback on failure.
  Future<void> _performDeleteDomain(
      DomainPalette domain, List<Task> domainTasks) async {
    final store = ref.read(taskStoreProvider.notifier);
    final apiService = ref.read(apiServiceProvider);

    // Find ALL root tasks (parent_id == null) for this domain —
    // a domain can have multiple root trees (e.g. Health has Fitness,
    // Nutrition, Mental wellness as separate roots).
    final rootTasks =
        domainTasks.where((t) => t.parentId == null).toList();

    // Optimistic: remove all tasks in this category
    final backup = List<Task>.from(domainTasks);
    for (final t in domainTasks) {
      store.removeTask(t.id);
    }

    // Clamp focused index
    final newDomains = _getDomains();
    setState(() {
      if (_focusedIndex >= newDomains.length) {
        _focusedIndex = math.max(0, newDomains.length - 1);
      }
    });

    try {
      HapticService.medium();
      // Delete each root — backend cascades to children
      for (final root in rootTasks) {
        await apiService.deleteTask(root.id);
      }

      // Delete the category record
      final cats = ref.read(categoriesProvider);
      final catRecord = cats.where(
        (c) => c.name.toLowerCase() == domain.name.toLowerCase(),
      ).firstOrNull;
      if (catRecord != null) {
        await apiService.deleteCategory(catRecord.id);
        ref.read(categoriesProvider.notifier).update(
          (s) => s.where((c) => c.id != catRecord.id).toList(),
        );
      }

      if (mounted) {
        showStyledSnackbar(context,
          message: 'Deleted: ${domain.name}',
          style: SnackbarStyle.success,
        );
      }
    } catch (e) {
      // Rollback
      for (final t in backup) {
        store.upsertTask(t);
      }
      if (mounted) {
        showStyledSnackbar(context,
          message: 'Couldn\'t delete domain. Try again.',
          style: SnackbarStyle.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final storeState = ref.watch(taskStoreProvider);
    final tasks = ref.watch(allTasksProvider);

    // Derive domains from backend categories (watch to rebuild on fetch)
    final domains = ref.watch(domainPalettesProvider).values.toList();

    if (storeState.isLoading && domains.isEmpty) {
      return const LoadingState();
    }

    if (storeState.error != null && !storeState.hasLoadedOnce && domains.isEmpty) {
      return EmptyState(
        message: 'Something went wrong loading your tasks.',
        textColor: AppColors.darkText,
        icon: Icons.error_outline,
        onRetry: () => ref.read(taskStoreProvider.notifier).fetchAll(),
      );
    }

    if (domains.isEmpty) {
      return EmptyState(
        title: 'Your world, organized',
        message:
            'Say or type a task — Amble creates\ndomains for you automatically.',
        textColor: AppColors.darkText,
        icon: Icons.auto_awesome,
        examples: const [
          'Add buy groceries to home',
          'Schedule standup for career',
        ],
      );
    }

    // Clamp focused index if domains changed externally
    if (_focusedIndex >= domains.length) {
      _focusedIndex = math.max(0, domains.length - 1);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final liquidFocus = LiquidFocusScrollController.fromAvailable(
          totalCards: domains.length,
          availableHeight: constraints.maxHeight,
        );

        return SizedBox(
          width: double.infinity,
          height: double.infinity,
          // Listener doesn't participate in the gesture arena, so
          // Dismissible's horizontal swipe is never blocked.
          child: Listener(
            onPointerDown: _onPointerDown,
            onPointerMove: (e) =>
                _onPointerMove(e, domains.length),
            onPointerUp: (e) =>
                _onPointerUp(e, domains.length),
            child: ClipRect(
              child: Stack(
                children: [
                  // Animated card column — pre-compute per-domain tasks
                  // outside the builder to avoid filtering at 60fps.
                  Builder(builder: (context) {
                    final domainTaskMap = <int, List<Task>>{};
                    for (int i = 0; i < domains.length; i++) {
                      final domain = domains[i];
                      domainTaskMap[i] = tasks
                          .where((task) =>
                              task.category.toLowerCase() ==
                              domain.name.toLowerCase())
                          .toList();
                    }
                    return AnimatedBuilder(
                      animation: _focusAnimation,
                      builder: (context, _) {
                        final t = _focusAnimation.value;

                        final cards = List.generate(domains.length, (index) {
                          final domain = domains[index];
                          final domainTasks = domainTaskMap[index]!;

                        // Compute animated height: lerp between previous and target
                        final prevHeight = index == _previousFocusedIndex
                            ? liquidFocus.focusedHeight
                            : liquidFocus.compressedHeight;
                        final targetHeight = index == _focusedIndex
                            ? liquidFocus.focusedHeight
                            : liquidFocus.compressedHeight;
                        final height = prevHeight + (targetHeight - prevHeight) * t;

                        // Focus progress for visual effects
                        final prevFocus = index == _previousFocusedIndex ? 1.0 : 0.0;
                        final targetFocus = index == _focusedIndex ? 1.0 : 0.0;
                        final focusProgress = prevFocus + (targetFocus - prevFocus) * t;

                        return SizedBox(
                          height: height,
                          child: GestureDetector(
                            onTap: () {
                              if (index != _focusedIndex) {
                                HapticService.selection();
                                _setFocusedIndex(index);
                              }
                            },
                            child: Dismissible(
                              key: Key('domain-${domain.name}'),
                              direction: DismissDirection.endToStart,
                              confirmDismiss: (_) async {
                                await _deleteDomain(domain, domainTasks);
                                return false;
                              },
                              background: Container(
                                color: AppColors.deleteAction,
                                alignment: Alignment.centerRight,
                                padding:
                                    const EdgeInsets.only(right: AppSpacing.lg),
                                child: const Icon(
                                  Icons.delete_forever,
                                  color: AppColors.darkBg,
                                  size: 32,
                                ),
                              ),
                              child: DomainCard(
                                domain: domain,
                                tasks: domainTasks,
                                isDark: true,
                                focusProgress: focusProgress,
                                height: height,
                              ),
                            ),
                          ),
                        );
                      });

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: cards,
                        );
                      },
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
