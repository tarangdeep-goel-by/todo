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

class _ParentNodeViewState extends ConsumerState<ParentNodeView> {
  int _focusedIndex = 0;

  // Pointer tracking for vertical drag (using Listener to avoid gesture arena
  // conflict with Dismissible's horizontal swipe)
  double _pointerStartY = 0.0;
  double _pointerStartX = 0.0;
  bool _isVerticalDrag = false;
  bool _directionDecided = false;

  // Overscroll state for add-domain gesture
  double _overscrollDistance = 0.0;
  bool _overscrollLocked = false;
  static const double _overscrollThreshold = 80.0;

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
      setState(() {
        _focusedIndex--;
        _pointerStartY = event.position.dy;
      });
    } else if (dragDistance < -threshold &&
        _focusedIndex < domainCount - 1) {
      HapticService.selection();
      setState(() {
        _focusedIndex++;
        _pointerStartY = event.position.dy;
      });
    } else if (dragDistance < -threshold &&
        _focusedIndex == domainCount - 1 &&
        domainCount < 5) {
      // Overscroll past last card — reveal add-domain zone
      final overscroll =
          (-dragDistance - threshold).clamp(0.0, _overscrollThreshold * 1.5);
      setState(() {
        _overscrollDistance = overscroll;
        if (!_overscrollLocked && overscroll >= _overscrollThreshold) {
          _overscrollLocked = true;
          HapticService.medium();
        }
      });
    }
  }

  void _onPointerUp(PointerUpEvent event, int domainCount) {
    if (_overscrollLocked && domainCount < 5) {
      _showAddDomainSheet(domainCount);
    }
    setState(() {
      _overscrollDistance = 0.0;
      _overscrollLocked = false;
      _isVerticalDrag = false;
      _directionDecided = false;
    });
  }

  /// Returns an error string if [name] is invalid for a domain, or null if valid.
  /// Checks: empty, too long (>30 chars), duplicate (case-insensitive).
  String? _validateDomainName(String name, Set<String> existing) {
    if (name.isEmpty) return 'Name cannot be empty';
    if (name.length > 30) return 'Name is too long (max 30 characters)';
    if (existing.contains(name.toLowerCase())) return 'Domain already exists';
    return null;
  }

  Future<void> _showAddDomainSheet(int currentCount) async {
    final controller = TextEditingController();
    final existingNames = _getDomains()
        .map((d) => d.name.toLowerCase())
        .toSet();

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkBg,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusMd)),
      ),
      builder: (ctx) {
        String? errorText;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: AppSpacing.lg,
                right: AppSpacing.lg,
                top: AppSpacing.lg,
                bottom:
                    MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'New Domain',
                    style: AppTypography.ctaLabelText(
                      color: AppColors.darkText,
                    ).copyWith(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    style: AppTypography.ctaLabelText(
                            color: AppColors.darkText)
                        .copyWith(fontSize: 16),
                    decoration: InputDecoration(
                      hintText: 'Domain name',
                      hintStyle: AppTypography.ctaLabelText(
                        color:
                            AppColors.darkText.withValues(alpha: 0.4),
                      ).copyWith(fontSize: 16),
                      errorText: errorText,
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: AppColors.darkText
                              .withValues(alpha: 0.3),
                        ),
                      ),
                      focusedBorder: const UnderlineInputBorder(
                        borderSide:
                            BorderSide(color: AppColors.darkText),
                      ),
                    ),
                    onSubmitted: (value) {
                      final name = value.trim();
                      final error = _validateDomainName(name, existingNames);
                      if (error != null) {
                        setSheetState(() => errorText = error);
                        return;
                      }
                      Navigator.pop(ctx, name);
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () {
                        final name = controller.text.trim();
                        final error = _validateDomainName(name, existingNames);
                        if (error != null) {
                          setSheetState(() => errorText = error);
                          return;
                        }
                        Navigator.pop(ctx, name);
                      },
                      style: TextButton.styleFrom(
                        backgroundColor:
                            DomainColors.defaultPalette.primary,
                        foregroundColor:
                            DomainColors.defaultPalette.textOnPrimary,
                        padding: const EdgeInsets.symmetric(
                            vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                              AppSpacing.radiusSm),
                        ),
                      ),
                      child: Text(
                        'Create',
                        style: AppTypography.ctaLabelText(
                          color: DomainColors
                              .defaultPalette.textOnPrimary,
                        ).copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result != null && mounted) {
      _createDomain(result);
    }
  }

  Future<void> _createDomain(String name) async {
    final cat = name.toLowerCase();
    final apiService = ref.read(apiServiceProvider);
    try {
      final category = await apiService.createCategory(
        AppConstants.defaultUserId, cat,
      );
      ref.read(categoriesProvider.notifier).update((s) => [...s, category]);
      HapticService.light();
    } catch (e) {
      if (mounted) {
        showStyledSnackbar(context,
          message: 'Failed to create domain: $e',
          style: SnackbarStyle.error,
        );
      }
    }
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
          message: 'Failed to delete domain: $e',
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

    if (storeState.error != null && domains.isEmpty) {
      return EmptyState(
        message: 'Unable to load tasks',
        textColor: AppColors.darkText,
        icon: Icons.error_outline,
        onRetry: () => ref.read(taskStoreProvider.notifier).fetchAll(),
      );
    }

    if (domains.isEmpty) {
      return EmptyState(
        title: 'Your world, organized',
        message:
            'Speak a task and VOKL creates domains automatically.\nOr add one manually below.',
        textColor: AppColors.darkText,
        icon: Icons.auto_awesome,
        examples: const [
          'Add buy groceries to personal',
          'Schedule standup for work',
        ],
        actionLabel: 'Add Domain',
        onAction: () => _showAddDomainSheet(0),
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

        // Overscroll progress (0.0 to 1.0) for the add-domain zone
        final overscrollProgress =
            (_overscrollDistance / _overscrollThreshold).clamp(0.0, 1.0);
        final showAddZone =
            domains.length < 5 && _overscrollDistance > 0;

        // Build domain cards
        final cards = List.generate(domains.length, (index) {
          final domain = domains[index];

          final domainTasks = tasks
              .where((task) =>
                  task.category.toLowerCase() ==
                  domain.name.toLowerCase())
              .toList();

          final distance = (index - _focusedIndex).abs();
          final focusProgress =
              distance == 0 ? 1.0 : (1.0 / (distance + 1));

          final height = index == _focusedIndex
              ? liquidFocus.focusedHeight
              : liquidFocus.compressedHeight;

          return SizedBox(
            height: height,
            child: GestureDetector(
              onTap: () {
                if (index != _focusedIndex) {
                  HapticService.selection();
                  setState(() {
                    _focusedIndex = index;
                  });
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: cards,
                  ),
                  // Add-domain zone — overlays at bottom, only during overscroll
                  if (showAddZone)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: -56 + (56 * overscrollProgress),
                      child: Opacity(
                        opacity: overscrollProgress,
                        child: Container(
                          height: 56,
                          margin: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.cardMargin,
                          ),
                          decoration: BoxDecoration(
                            color: _overscrollLocked
                                ? DomainColors.defaultPalette.primary
                                    .withValues(alpha: 0.3)
                                : DomainColors.defaultPalette.surface,
                            border: Border.all(
                              color: DomainColors
                                  .defaultPalette.primary
                                  .withValues(alpha: 0.4),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_circle_outline,
                                color: DomainColors
                                    .defaultPalette.primary,
                                size: 20,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Text(
                                _overscrollLocked
                                    ? 'Release to add'
                                    : 'New Domain',
                                style: AppTypography.ctaLabelText(
                                  color: DomainColors
                                      .defaultPalette.primary,
                                ).copyWith(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
