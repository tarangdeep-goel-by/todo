import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Custom painter for subtle grain texture overlay
/// Used in light mode only, 2% opacity
class GrainTexturePainter extends CustomPainter {
  final Color color;
  final double opacity;

  GrainTexturePainter({
    this.color = Colors.black,
    this.opacity = 0.02,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;

    final random = math.Random(42); // Fixed seed for consistent pattern

    // Draw random dots for grain effect
    final dotCount = (size.width * size.height / 16).toInt(); // Density

    for (int i = 0; i < dotCount; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final radius = random.nextDouble() * 0.5 + 0.3; // Tiny dots

      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(GrainTexturePainter oldDelegate) {
    return false; // Static grain pattern
  }
}
