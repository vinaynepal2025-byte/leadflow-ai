import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/appearance_settings.dart';
import 'glass_widgets.dart';
import 'score_badge.dart';

/// The Lead Detail screen's hero panel — the single place that shows
/// what's happening across EVERY module for this lead (fees, documents,
/// visa, travel, consent, meetings, reminders, engagement) as one
/// prioritized alert list, plus one AI narrative that connects the dots
/// across departments instead of each module having its own island of
/// insight. Backed by GET /lead360/:leadId.
class Lead360Panel extends StatelessWidget {
  final Map<String, dynamic>? data;
  final bool loading;
  final String? error;
  final VoidCallback onRefresh;
  final void Function(String module) onAlertTap;

  const Lead360Panel({
    super.key,
    required this.data,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.onAlertTap,
  });

  Color _severityColor(AppearanceSettings a, String severity) {
    switch (severity) {
      case 'critical':
        return a.dangerColor;
      case 'warning':
        return a.warningColor;
      default:
        return a.mutedColor;
    }
  }

  IconData _severityIcon(String severity) {
    switch (severity) {
      case 'critical':
        return Icons.error_outline;
      case 'warning':
        return Icons.warning_amber_outlined;
      default:
        return Icons.info_outline;
    }
  }

  Color _riskColor(AppearanceSettings a, String? risk) {
    switch (risk) {
      case 'high':
        return a.dangerColor;
      case 'medium':
        return a.warningColor;
      default:
        return a.successColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AppearanceSettings>();
    if (loading && data == null) {
      return GlassContainer(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: const [
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Text('Reading across every module for this lead…'),
          ],
        ),
      );
    }

    if (error != null && data == null) {
      return GlassContainer(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.cloud_off, color: a.mutedColor),
            const SizedBox(width: 10),
            const Expanded(child: Text('Lead 360 unavailable right now.')),
            TextButton(onPressed: onRefresh, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (data == null) return const SizedBox.shrink();

    final score = data!['score'] as int? ?? 0;
    final temperature = data!['temperature'] as String? ?? 'cold';
    final alerts = (data!['alerts'] as List? ?? []).cast<Map<String, dynamic>>();
    final ai = data!['ai'] as Map<String, dynamic>?;
    final hasAiError = ai == null || ai['error'] != null;
    final activeOffers = (data!['active_offers'] as List? ?? []);

    return GlassContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Row(
              children: [
                Icon(Icons.hub_outlined, color: a.primaryColor, size: 20),
                const SizedBox(width: 8),
                const Text('Lead 360', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                if (!hasAiError)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _riskColor(a, ai!['risk_level'] as String?).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${(ai!['risk_level'] as String? ?? 'low').toUpperCase()} RISK',
                      style: TextStyle(
                        color: _riskColor(a, ai!['risk_level'] as String?),
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                      ),
                    ),
                  ),
                IconButton(
                  icon: loading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh, size: 20),
                  onPressed: loading ? null : onRefresh,
                  tooltip: 'Refresh Lead 360',
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                ScoreBadge(score: score, temperature: temperature),
                if (activeOffers.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: a.successColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: a.successColor.withValues(alpha: 0.4)),
                    ),
                    child: Text('${activeOffers.length} active offer${activeOffers.length > 1 ? 's' : ''}',
                        style: TextStyle(color: a.successColor, fontWeight: FontWeight.w600, fontSize: 12)),
                  ),
                ],
              ],
            ),
            if (!hasAiError) ...[
              const SizedBox(height: 12),
              Text(ai!['headline'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 6),
              Text(ai!['narrative'] as String? ?? '', style: TextStyle(color: a.mutedColor, fontSize: 13, height: 1.4)),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: a.warningColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.bolt, size: 16, color: a.warningColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(ai!['top_action'] as String? ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ] else if (loading) ...[
              const SizedBox(height: 10),
              Text('Synthesizing cross-module insight…', style: TextStyle(color: a.mutedColor, fontSize: 12)),
            ],
            if (alerts.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Text('Needs attention (${alerts.length})',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: a.mutedColor)),
              const SizedBox(height: 6),
              ...alerts.map((a) {
                final severity = a['severity'] as String? ?? 'info';
                final color = _severityColor(a, severity);
                return InkWell(
                  onTap: () => onAlertTap(a['module'] as String? ?? ''),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(_severityIcon(severity), size: 16, color: color),
                        const SizedBox(width: 8),
                        Expanded(child: Text(a['message'] as String? ?? '', style: const TextStyle(fontSize: 13))),
                        Icon(Icons.chevron_right, size: 16, color: a.mutedColor),
                      ],
                    ),
                  ),
                );
              }),
            ] else if (data != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 16, color: a.successColor),
                  const SizedBox(width: 6),
                  Text('Nothing needs attention across any module right now',
                      style: TextStyle(color: a.successColor, fontSize: 12)),
                ],
              ),
          ],
          ],
        ),
      );
  }
}
