import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

Color stageColor(String stage) => stageColorFor(stage);

class StageChip extends StatelessWidget {
  final String stage;
  const StageChip({super.key, required this.stage});

  @override
  Widget build(BuildContext context) {
    final color = stageColor(stage);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        stage,
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}
