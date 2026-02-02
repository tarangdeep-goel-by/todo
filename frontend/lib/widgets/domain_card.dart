import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../config/constants.dart';
import '../models/task.dart';

/// Domain card widget with focus/compressed states
class DomainCard extends StatelessWidget {
  final DomainPalette domain;
  final List<Task> tasks;
  final bool isDark;
  final double focusProgress; // 0.0 = compressed, 1.0 = focused
  final double height;

  const DomainCard({
    super.key,
    required this.domain,
    required this.tasks,
    required this.isDark,
    required this.focusProgress,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppAnimations.cardExpand,
      curve: AppAnimations.easeOutCubic,
      width: double.infinity,
      height: height,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.cardMargin,
        vertical: AppSpacing.xs,
      ),
      // Use LayoutBuilder to pick content based on actual animated height,
      // not focusProgress — avoids overflow during height animation
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Need at least ~100px to render focused content comfortably
          final showFocused = constraints.maxHeight > 100;
          return showFocused
              ? _buildFocusedCard(context)
              : _buildCompressedCard(context);
        },
      ),
    );
  }

  /// Focused card: full bleed, domain primary background
  Widget _buildFocusedCard(BuildContext context) {
    final taskCount = tasks.where((t) => t.status == 'active').length;
    final activeTasks = tasks.where((t) => t.status == 'active').take(4).toList();

    return Stack(
      children: [
        // Background with domain color
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: domain.primary,
            borderRadius: BorderRadius.circular(AppSpacing.radiusNone),
          ),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Domain name and task count row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Domain name (large)
                  Expanded(
                    child: Text(
                      domain.name,
                      style: AppTypography.domainTitle(
                        context,
                        color: domain.textOnPrimary,
                      ),
                    ),
                  ),

                  // Task count (right aligned)
                  Text(
                    '$taskCount ${taskCount == 1 ? 'task' : 'tasks'}',
                    style: AppTypography.metadataText(
                      color: domain.textOnPrimary.withValues(alpha: 0.8),
                    ).copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const Spacer(),

              // Task preview (top 3-4 tasks) - constrain to available space
              Flexible(
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: activeTasks.map((task) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          task.title,
                          style: AppTypography.taskPreview(
                            context,
                            color: domain.textOnPrimary,
                          ).copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Grain texture removed (was light mode only)
      ],
    );
  }

  /// Compressed card: surface background, left accent bar
  Widget _buildCompressedCard(BuildContext context) {
    final taskCount = tasks.where((t) => t.status == 'active').length;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: domain.surface,
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(AppSpacing.radiusMd),
          bottomRight: Radius.circular(AppSpacing.radiusMd),
        ),
        border: Border(
          left: BorderSide(
            color: domain.primary,
            width: AppSpacing.leftAccentBar,
          ),
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Domain name (smaller)
          Text(
            domain.name,
            style: AppTypography.ctaLabelText(color: domain.primary).copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),

          // Task count (right aligned, bolder)
          Text(
            '$taskCount ${taskCount == 1 ? 'task' : 'tasks'}',
            style: AppTypography.metadataText(
              color: domain.primary.withValues(alpha: 0.8),
            ).copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

