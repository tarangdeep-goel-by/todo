import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/theme.dart';
import '../providers/tasks_provider.dart';
import '../widgets/domain_card.dart';
import '../widgets/empty_state.dart';
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
  int _focusedIndex = 0; // Currently focused card (0-4)
  double _dragStartY = 0.0;

  void _onVerticalDragStart(DragStartDetails details) {
    _dragStartY = details.globalPosition.dy;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    // Calculate drag distance
    final dragDistance = details.globalPosition.dy - _dragStartY;
    final viewportHeight = MediaQuery.of(context).size.height;

    // Threshold to change focus (5% of viewport for high sensitivity)
    final threshold = viewportHeight * 0.05;

    if (dragDistance > threshold && _focusedIndex > 0) {
      // Drag down - focus previous card (move up in list)
      HapticService.selection();
      setState(() {
        _focusedIndex--;
        _dragStartY = details.globalPosition.dy; // Reset reference
      });
    } else if (dragDistance < -threshold && _focusedIndex < 4) {
      // Drag up - focus next card (move down in list)
      HapticService.selection();
      setState(() {
        _focusedIndex++;
        _dragStartY = details.globalPosition.dy; // Reset reference
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(tasksProvider);

    return tasksAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(
          color: AppColors.darkText,
        ),
      ),
      error: (error, stack) {
        return const EmptyState(
          message: 'Unable to load tasks',
          textColor: AppColors.darkText,
          icon: Icons.error_outline,
        );
      },
      data: (tasks) {
        // Get all domains (dark mode only)
        final domains = DomainColors.getAllDomains(true);

        return LayoutBuilder(
          builder: (context, constraints) {
        // Use actual available height from layout constraints
        final liquidFocus = LiquidFocusScrollController.fromAvailable(
          totalCards: domains.length,
          availableHeight: constraints.maxHeight,
        );

        return SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: GestureDetector(
            onVerticalDragStart: _onVerticalDragStart,
            onVerticalDragUpdate: _onVerticalDragUpdate,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: List.generate(domains.length, (index) {
              final domain = domains[index];

              // Get tasks for this domain
              final domainTasks = tasks
                  .where((task) =>
                      task.category.toLowerCase() == domain.name.toLowerCase())
                  .toList();

              // Calculate focus progress based on distance from focused index
              final distance = (index - _focusedIndex).abs();
              final focusProgress = distance == 0 ? 1.0 : (1.0 / (distance + 1));

              // Get card height based on focus
              final height = index == _focusedIndex
                  ? liquidFocus.focusedHeight
                  : liquidFocus.compressedHeight;

              return GestureDetector(
                onTap: () {
                  if (index != _focusedIndex) {
                    HapticService.selection();
                    setState(() {
                      _focusedIndex = index;
                    });
                  }
                },
                child: DomainCard(
                  domain: domain,
                  tasks: domainTasks,
                  allTasks: tasks,
                  isDark: true, // Dark mode only
                  focusProgress: focusProgress,
                  height: height,
                ),
              );
            }),
            ),
          ),
        );
          },
        );
      },
    );
  }
}
