import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The signature visual element: a few soft arcs suggesting a flight path /
/// journey line, referencing the "students crossing a threshold abroad"
/// concept the whole palette is built around. Deliberately restrained —
/// one idea, quiet execution, not decoration for its own sake.
class JourneyPathPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint1 = Paint()
      ..color = AppColors.signalAmber.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final paint2 = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    // Three arcs of increasing radius, all departing from the same
    // bottom-left "origin" point — a simple, legible motif at small size.
    final origin = Offset(-size.width * 0.15, size.height * 1.1);

    canvas.drawArc(
      Rect.fromCircle(center: origin, radius: size.width * 0.65),
      -0.95, 0.55, false, paint1,
    );
    canvas.drawArc(
      Rect.fromCircle(center: origin, radius: size.width * 0.85),
      -1.05, 0.5, false, paint2,
    );
    canvas.drawArc(
      Rect.fromCircle(center: origin, radius: size.width * 1.05),
      -1.0, 0.42, false, paint2,
    );

    // A small dot near the nearest arc's leading edge — the journey's
    // destination, echoing a pin/stamp. Position is deliberately
    // approximate (ambient texture, not a precise diagram).
    final dotRadius = size.width * 0.65;
    final dot = origin + Offset(dotRadius * -0.98, dotRadius * -0.2);
    canvas.drawCircle(dot, 3, Paint()..color = AppColors.signalAmber);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
