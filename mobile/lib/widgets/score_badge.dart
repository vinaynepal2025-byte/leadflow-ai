import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/appearance_settings.dart';

/// Temperature -> colour, read from the user's own semantic palette rather
/// than hardcoded values, so restyling the app in Settings restyles these
/// badges too.
Color scoreTemperatureColor(BuildContext context, String temperature) {
  final a = context.read<AppearanceSettings>();
  switch (temperature) {
    case 'hot':
      return a.dangerColor;
    case 'warm':
      return a.warningColor;
    default:
      return a.mutedColor;
  }
}

IconData scoreTemperatureIcon(String temperature) {
  switch (temperature) {
    case 'hot':
      return Icons.local_fire_department;
    case 'warm':
      return Icons.wb_sunny_outlined;
    default:
      return Icons.ac_unit;
  }
}

/// Full-size pill badge, same visual language as StageChip — used on
/// Lead Detail's header row. Tappable to show the "why" behind the score
/// (the scoring engine already returns explainable signals; surfacing
/// them here costs nothing extra and is the whole point of a rule-based,
/// non-opaque scoring engine per leadScoring.js's own design comment).
class ScoreBadge extends StatelessWidget {
  final int score;
  final String temperature;
  final VoidCallback? onTap;
  const ScoreBadge({super.key, required this.score, required this.temperature, this.onTap});

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<AppearanceSettings>();
    final color = temperature == 'hot'
        ? appearance.dangerColor
        : temperature == 'warm'
            ? appearance.warningColor
            : appearance.mutedColor;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(scoreTemperatureIcon(temperature), size: 14, color: color),
            const SizedBox(width: 4),
            Text('$score', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// Compact dot+number variant for tight spaces like list-tile trailing,
/// stacked above a StageChip without pushing the row height much.
class ScoreBadgeCompact extends StatelessWidget {
  final int score;
  final String temperature;
  const ScoreBadgeCompact({super.key, required this.score, required this.temperature});

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<AppearanceSettings>();
    final color = temperature == 'hot'
        ? appearance.dangerColor
        : temperature == 'warm'
            ? appearance.warningColor
            : appearance.mutedColor;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(scoreTemperatureIcon(temperature), size: 12, color: color),
        const SizedBox(width: 2),
        Text('$score', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11)),
      ],
    );
  }
}

/// Shows the scoring engine's own explanation (positive_signals /
/// risk_signals) in a dialog — reuses whatever `scoreData` map came back
/// from getLeadScore/getRankedLeads, no extra API call.
void showScoreExplanation(BuildContext context, Map<String, dynamic> scoreData) {
  final appearance = context.read<AppearanceSettings>();
  final temperature = scoreData['temperature'] as String? ?? 'cold';
  final headerColor = temperature == 'hot'
      ? appearance.dangerColor
      : temperature == 'warm'
          ? appearance.warningColor
          : appearance.mutedColor;
  final positives = (scoreData['positive_signals'] as List? ?? []);
  final risks = (scoreData['risk_signals'] as List? ?? []);
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Icon(scoreTemperatureIcon(temperature), color: headerColor),
          const SizedBox(width: 8),
          Text('Score: ${scoreData['score']}/100'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (positives.isNotEmpty) ...[
                const Text('Working in their favor', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                ...positives.map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('+ ${s['reason']} (+${s['points']})', style: TextStyle(color: appearance.successColor)),
                    )),
                const SizedBox(height: 8),
              ],
              if (risks.isNotEmpty) ...[
                const Text('Working against them', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                ...risks.map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('- ${s['reason']} (${s['points']})', style: TextStyle(color: appearance.dangerColor)),
                    )),
              ],
              if (positives.isEmpty && risks.isEmpty) const Text('No scoring signals yet for this lead.'),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
    ),
  );
}
