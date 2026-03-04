import 'package:flutter/material.dart';
import '../config/typography.dart';

/// Bottom-anchored bouncing arrow with "Pull up for new domain" text.
/// Visible when focused on the last domain card with < 8 domains.
class OverscrollHintIndicator extends StatefulWidget {
  final Color domainColor;

  const OverscrollHintIndicator({
    super.key,
    required this.domainColor,
  });

  @override
  State<OverscrollHintIndicator> createState() =>
      _OverscrollHintIndicatorState();
}

class _OverscrollHintIndicatorState extends State<OverscrollHintIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, -4),
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.domainColor.withValues(alpha: 0.5);

    return AnimatedBuilder(
      animation: _slideAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: _slideAnimation.value,
          child: child,
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.keyboard_arrow_up_rounded,
            size: 20,
            color: color,
          ),
          Text(
            'Pull up for new domain',
            style: AppTypography.metadataText(
              color: color,
            ).copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}
