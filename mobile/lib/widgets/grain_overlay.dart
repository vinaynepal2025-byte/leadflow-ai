import 'dart:math';
import 'package:flutter/material.dart';

/// A subtle procedural grain overlay — small semi-random dots at low
/// opacity, giving flat surfaces a bit of tactile "rough texture" without
/// needing an image asset. Deterministic seed so it doesn't flicker/
/// repaint differently on every frame.
class GrainOverlay extends StatelessWidget {
  final double opacity;
  const GrainOverlay({super.key, this.opacity = 0.05});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _GrainPainter(opacity: opacity),
        size: Size.infinite,
      ),
    );
  }
}

class _GrainPainter extends CustomPainter {
  final double opacity;
  _GrainPainter({required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(42); // fixed seed — stable pattern, not noisy per frame
    final paint = Paint()..color = Colors.black.withValues(alpha: opacity);
    const spacing = 3.5;

    for (double y = 0; y < size.height; y += spacing) {
      for (double x = 0; x < size.width; x += spacing) {
        if (random.nextDouble() > 0.5) continue; // ~50% density, irregular
        final dx = x + random.nextDouble() * spacing;
        final dy = y + random.nextDouble() * spacing;
        canvas.drawCircle(Offset(dx, dy), 0.6, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
