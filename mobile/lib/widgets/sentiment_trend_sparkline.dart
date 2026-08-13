import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A compact sentiment sparkline for the Notes screen — closes the gap
/// left in Phase 5 (sentiment/tags were captured but never visualized as
/// a trend). Deliberately a lightweight CustomPainter rather than pulling
/// in a charting package: this is one line, doesn't need axes, legends,
/// or interactivity, and a new dependency isn't worth it for that.
class SentimentTrendSparkline extends StatelessWidget {
  final List<Map<String, dynamic>> points; // [{at, sentiment, score}]

  const SentimentTrendSparkline({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) return const SizedBox.shrink();

    final latest = points.last['sentiment'] as String;
    final latestColor = _colorFor(latest);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: latestColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: latestColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            height: 36,
            child: CustomPaint(painter: _SparklinePainter(points)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Sentiment trend', style: TextStyle(fontSize: 11, color: AppColors.slate, fontWeight: FontWeight.w600)),
                Text(
                  'Currently ${latest} across ${points.length} tracked note${points.length > 1 ? 's' : ''}',
                  style: TextStyle(fontSize: 12, color: latestColor, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Color _colorFor(String sentiment) {
    switch (sentiment) {
      case 'positive':
        return AppColors.successGreen;
      case 'negative':
        return AppColors.coralAlert;
      default:
        return AppColors.slate;
    }
  }
}

class _SparklinePainter extends CustomPainter {
  final List<Map<String, dynamic>> points;
  _SparklinePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final scores = points.map((p) => (p['score'] as num).toDouble()).toList();
    final path = Path();
    final dx = size.width / (scores.length - 1);

    // score is -1..1 — map to the vertical space with a little padding so
    // a flat "all neutral" line doesn't hug an edge.
    double yFor(double s) => size.height / 2 - (s * (size.height / 2 - 4));

    final fillPath = Path()..moveTo(0, size.height);
    for (int i = 0; i < scores.length; i++) {
      final x = dx * i;
      final y = yFor(scores[i]);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      fillPath.lineTo(x, y);
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    final trendColor = scores.last > 0
        ? AppColors.successGreen
        : scores.last < 0
            ? AppColors.coralAlert
            : AppColors.slate;

    canvas.drawPath(
      fillPath,
      Paint()..color = trendColor.withValues(alpha: 0.08),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = trendColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Dot on the most recent point.
    canvas.drawCircle(
      Offset(dx * (scores.length - 1), yFor(scores.last)),
      3,
      Paint()..color = trendColor,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) => oldDelegate.points != points;
}
