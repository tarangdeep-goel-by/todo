import 'dart:math' as math;
import 'package:flutter/material.dart';

/// CustomPainter for focused card — warm, saturated, painterly gradient.
/// No metallic/glass effects. Pure color layering like acrylic paint.
class GlassCardPainter extends CustomPainter {
  final Color primaryColor;
  final Color darkShade;
  final double focusProgress;

  GlassCardPainter({
    required this.primaryColor,
    required this.darkShade,
    required this.focusProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Layer 1: Rich saturated base — diagonal sweep of primary hues
    // No white blending. Pure color: bright primary → full primary → warm darkShade
    final angle = 140 * math.pi / 180;
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    final baseGradient = LinearGradient(
      begin: Alignment(cos, sin),
      end: Alignment(-cos, -sin),
      colors: [
        primaryColor,
        Color.lerp(primaryColor, darkShade, 0.15)!,
        Color.lerp(primaryColor, darkShade, 0.40)!,
        darkShade,
      ],
      stops: const [0.0, 0.40, 0.70, 1.0],
    );
    canvas.drawRect(
      rect,
      Paint()..shader = baseGradient.createShader(rect),
    );

    // Layer 2: Warm radial glow — primary color light at top-left
    // Mimics layered acrylic paint catching light, NOT metallic sheen
    final spotCenter = Offset(size.width * 0.25, size.height * 0.20);
    final spotGradient = RadialGradient(
      center: Alignment(
        (spotCenter.dx / size.width) * 2 - 1,
        (spotCenter.dy / size.height) * 2 - 1,
      ),
      radius: 0.8,
      colors: [
        primaryColor.withValues(alpha: 0.35 * focusProgress),
        primaryColor.withValues(alpha: 0.0),
      ],
    );
    canvas.drawRect(
      rect,
      Paint()..shader = spotGradient.createShader(rect),
    );

    // Layer 3: Subtle bottom warmth — darkShade radial at bottom-right
    final bottomGlow = RadialGradient(
      center: const Alignment(0.7, 0.8),
      radius: 0.6,
      colors: [
        darkShade.withValues(alpha: 0.25 * focusProgress),
        darkShade.withValues(alpha: 0.0),
      ],
    );
    canvas.drawRect(
      rect,
      Paint()..shader = bottomGlow.createShader(rect),
    );
  }

  @override
  bool shouldRepaint(GlassCardPainter oldDelegate) {
    return oldDelegate.primaryColor != primaryColor ||
        oldDelegate.darkShade != darkShade ||
        oldDelegate.focusProgress != focusProgress;
  }
}
