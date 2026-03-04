import 'package:flutter/material.dart';
import '../config/typography.dart';

/// Bouncing downward arrow + "See all tasks" text, positioned above the bottom nav.
/// Dismissed when user switches to flat view.
class FlatViewNudge extends StatefulWidget {
  final Color domainColor;

  const FlatViewNudge({super.key, required this.domainColor});

  @override
  State<FlatViewNudge> createState() => _FlatViewNudgeState();
}

class _FlatViewNudgeState extends State<FlatViewNudge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
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
    final color = widget.domainColor.withValues(alpha: 0.6);

    return AnimatedBuilder(
      animation: _bounceAnimation,
      builder: (context, child) {
        final dy = _bounceAnimation.value * 4;
        return Transform.translate(
          offset: Offset(0, dy),
          child: child,
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'See all tasks',
            style: AppTypography.ctaLabelText(
              color: color,
            ).copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            color: color,
            size: 20,
          ),
        ],
      ),
    );
  }
}
