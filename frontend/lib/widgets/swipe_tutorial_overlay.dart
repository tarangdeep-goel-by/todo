import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/constants.dart';
import '../config/theme.dart';

/// Wraps a task row to show a partial-swipe preview during the tutorial.
///
/// Instead of an opaque overlay, this pre-translates the child row to reveal
/// the colored action background (like the Dismissible would show), with a
/// gentle bounce animation. A small label below tells the user what to do.
///
/// Step 0: right → "Swipe right to complete" (domain color, check icon)
/// Step 1: left  → "Swipe left to undo"      (domain color, undo icon)
/// Step 2: left  → "Swipe left to archive"    (delete color, archive icon)
/// Step 3: (profile nudge — not used here)
/// Step 4: right → "Swipe right to restore"   (green, undo icon)
/// Step 5: left  → "Swipe left to delete"     (delete color, delete icon)
class SwipeTutorialOverlay extends StatefulWidget {
  final int step;
  final Color domainColor;
  final Widget child;

  const SwipeTutorialOverlay({
    super.key,
    required this.step,
    required this.domainColor,
    required this.child,
  });

  @override
  State<SwipeTutorialOverlay> createState() => _SwipeTutorialOverlayState();
}

class _SwipeTutorialOverlayState extends State<SwipeTutorialOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _bounceAnimation;

  static const double _peekDistance = 48.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppAnimations.tutorialBounce,
    )..repeat(reverse: true);
    _bounceAnimation = CurvedAnimation(
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
    final isRightSwipe = widget.step == 0 || widget.step == 4;

    final String label;
    final IconData icon;
    final Color bgColor;
    final Color iconColor;
    switch (widget.step) {
      case 0:
        label = 'Swipe right to complete';
        icon = Icons.check_circle;
        bgColor = widget.domainColor;
        iconColor = AppColors.darkBg;
        break;
      case 1:
        label = 'Swipe left to undo';
        icon = Icons.undo_rounded;
        bgColor = widget.domainColor;
        iconColor = AppColors.darkBg;
        break;
      case 2:
        label = 'Swipe left to archive';
        icon = Icons.archive_rounded;
        bgColor = AppColors.deleteAction;
        iconColor = AppColors.darkBg;
        break;
      case 4:
        label = 'Swipe right to restore';
        icon = Icons.undo_rounded;
        bgColor = AppColors.completed;
        iconColor = AppColors.darkBg;
        break;
      case 5:
        label = 'Swipe left to delete';
        icon = Icons.delete_forever;
        bgColor = AppColors.deleteAction;
        iconColor = AppColors.darkBg;
        break;
      default:
        return widget.child;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Task row with peek background
        ClipRect(
          child: AnimatedBuilder(
            animation: _bounceAnimation,
            builder: (context, child) {
              // Bounce between 0 and _peekDistance
              final offset = _bounceAnimation.value * _peekDistance;
              final dx = isRightSwipe ? offset : -offset;

              return Stack(
                children: [
                  // Action background (revealed by translation)
                  Positioned.fill(
                    child: Container(
                      color: bgColor,
                      alignment: isRightSwipe
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      padding: EdgeInsets.only(
                        left: isRightSwipe ? 16 : 0,
                        right: isRightSwipe ? 0 : 16,
                      ),
                      child: Icon(icon, color: iconColor, size: 28),
                    ),
                  ),
                  // Translated task row with opaque background so it
                  // covers the action bg except where it slides away
                  Transform.translate(
                    offset: Offset(dx, 0),
                    child: Container(
                      color: AppColors.darkBg,
                      child: child,
                    ),
                  ),
                ],
              );
            },
            child: widget.child,
          ),
        ),
        // Label below
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: bgColor.withValues(alpha: 0.8),
            ),
          ),
        ),
      ],
    );
  }
}
