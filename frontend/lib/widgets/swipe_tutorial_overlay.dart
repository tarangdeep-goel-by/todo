import 'package:flutter/material.dart';
import '../config/constants.dart';
import '../config/spacing.dart';
import '../config/theme.dart';
import '../config/typography.dart';

/// Overlay on top of a task card during the swipe tutorial.
/// Shows animated arrow + instruction text for each step.
///
/// Step 0: right arrow → "Swipe to complete"
/// Step 1: left arrow → "Swipe to undo"
/// Step 2: left arrow → "Swipe to delete" (red tint)
///
/// Touches pass through to the Dismissible beneath.
class SwipeTutorialOverlay extends StatefulWidget {
  final int step;
  final Color domainColor;

  const SwipeTutorialOverlay({
    super.key,
    required this.step,
    required this.domainColor,
  });

  @override
  State<SwipeTutorialOverlay> createState() => _SwipeTutorialOverlayState();
}

class _SwipeTutorialOverlayState extends State<SwipeTutorialOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppAnimations.tutorialBounce,
    )..repeat(reverse: true);
    _slideAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRightSwipe = widget.step == 0;
    final isDelete = widget.step == 2;
    final color = isDelete ? AppColors.deleteAction : widget.domainColor;

    final String text;
    final IconData icon;
    switch (widget.step) {
      case 0:
        text = 'Swipe to complete';
        icon = Icons.arrow_forward_rounded;
        break;
      case 1:
        text = 'Swipe to undo';
        icon = Icons.arrow_back_rounded;
        break;
      case 2:
        text = 'Swipe to delete';
        icon = Icons.arrow_back_rounded;
        break;
      default:
        return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
        ),
        child: AnimatedBuilder(
          animation: _slideAnimation,
          builder: (context, child) {
            // 16px travel in swipe direction
            final offset = _slideAnimation.value * 16;
            final dx = isRightSwipe ? offset : -offset;

            return Transform.translate(
              offset: Offset(dx, 0),
              child: child,
            );
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isRightSwipe)
                Icon(icon, color: color, size: 24),
              if (!isRightSwipe)
                const SizedBox(width: AppSpacing.sm),
              Text(
                text,
                style: AppTypography.ctaLabelText(
                  color: color,
                ).copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (isRightSwipe)
                const SizedBox(width: AppSpacing.sm),
              if (isRightSwipe)
                Icon(icon, color: color, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}
