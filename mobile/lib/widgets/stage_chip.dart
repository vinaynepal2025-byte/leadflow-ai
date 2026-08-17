import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

Color stageColor(String stage) => stageColorFor(stage);

/// [styleJson] layers the same fine-grained controls the Edit Mode style
/// editor gives More Menu/Lead Detail/Share Target tiles (corner radius,
/// border, glow, blur) onto this chip -- deliberately never overriding
/// the chip's own colour, which is stage-coded (meaningful information,
/// not decoration) and would lose that at-a-glance signal if flattened
/// to one fixed colour. Null/empty styleJson renders exactly as before.
class StageChip extends StatelessWidget {
  final String stage;
  final Map<String, dynamic>? styleJson;
  const StageChip({super.key, required this.stage, this.styleJson});

  @override
  Widget build(BuildContext context) {
    final color = stageColor(stage);
    final sj = styleJson ?? const {};

    final double cornerRadius = ((sj['cornerRadius'] as num?)?.toDouble() ?? 20).clamp(0.0, 40.0);
    final double borderWidth = ((sj['borderWidth'] as num?)?.toDouble() ?? 1.0).clamp(0.0, 6.0);
    final double glowIntensity = ((sj['glowIntensity'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0);
    final double blurAmount = ((sj['blurAmount'] as num?)?.toDouble() ?? 0).clamp(0.0, 12.0);
    final double scale = ((sj['contentScale'] as num?)?.toDouble() ?? 1.0).clamp(0.8, 1.4);

    final radius = BorderRadius.circular(cornerRadius);
    Widget chip = Container(
      padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 4 * scale),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: radius,
        border: Border.all(color: color.withValues(alpha: 0.4), width: borderWidth),
        boxShadow: glowIntensity > 0
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.25 + glowIntensity * 0.55),
                  blurRadius: 4 + glowIntensity * 16,
                  spreadRadius: glowIntensity * 2,
                ),
              ]
            : null,
      ),
      child: Text(
        stage,
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12 * scale),
      ),
    );

    if (blurAmount > 0) {
      chip = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blurAmount, sigmaY: blurAmount),
          child: chip,
        ),
      );
    }
    return chip;
  }
}
