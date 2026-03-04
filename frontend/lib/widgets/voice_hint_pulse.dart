import 'package:flutter/material.dart';
import '../config/constants.dart';
import '../config/theme.dart';

/// Breathing glow ring + "Hold for voice" label above the PTT button.
/// When [isActive], pulses continuously. When inactive, renders child directly.
class VoiceHintPulse extends StatefulWidget {
  final Widget child;
  final bool isActive;

  const VoiceHintPulse({
    super.key,
    required this.child,
    required this.isActive,
  });

  @override
  State<VoiceHintPulse> createState() => _VoiceHintPulseState();
}

class _VoiceHintPulseState extends State<VoiceHintPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppAnimations.voicePulse,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
    if (widget.isActive) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(VoiceHintPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isActive && oldWidget.isActive) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) return widget.child;

    final glowColor = DomainColors.careerDark.primary;

    // Glow ring around child — no floating label
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final blur = 12.0 + _animation.value * 8.0;
        final alpha = 0.3 + _animation.value * 0.3;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(23),
            boxShadow: [
              BoxShadow(
                color: glowColor.withValues(alpha: alpha),
                blurRadius: blur,
                spreadRadius: 2,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
