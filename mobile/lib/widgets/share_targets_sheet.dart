import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../services/api_service.dart';
import '../screens/customize_share_targets_screen.dart' show kShareTargetIconOptions, kShareTargetDefaultLabels, kShareTargetDefaultIcons;

/// Reusable Share Targets picker -- reads the tenant's own enabled/ordered
/// /share-targets configuration (managed in Settings > Share Targets) and
/// shows it as a row of branded quick-tap icons.
///
/// Honest limitation, stated once here rather than re-litigated at every
/// call site: `share_plus` cannot target a specific installed app on
/// Android (there's no public API for Intent.setPackage()-style direct
/// targeting), so every icon here -- regardless of which platform it
/// represents -- opens the same underlying system share sheet. The value
/// this UI actually adds is the tenant's own icon/colour/order
/// customization and a "Share to..." row that visually matches their
/// brand, not per-app direct targeting (which Flyer Studio's WhatsApp-
/// specific `wa.me` deep link already does correctly, elsewhere, where a
/// real phone number makes direct targeting genuinely possible).
Future<void> showShareTargetsSheet(
  BuildContext context, {
  required List<XFile> files,
  String? text,
}) async {
  final api = ApiService();
  List<Map<String, dynamic>> targets = [];
  try {
    targets = (await api.getShareTargets()).where((t) => t['enabled'] != false).toList();
  } catch (_) {
    // If the targets list can't load, fall back straight to the system
    // share sheet rather than blocking the person from sharing at all.
    await Share.shareXFiles(files, text: text);
    return;
  }

  if (!context.mounted) return;
  if (targets.isEmpty) {
    await Share.shareXFiles(files, text: text);
    return;
  }

  await showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Share via', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 20, runSpacing: 16,
              children: targets.map((t) {
                final key = t['target_key'] as String;
                final label = t['custom_label'] ?? kShareTargetDefaultLabels[key] ?? key;
                final iconKey = t['icon_override'] ?? kShareTargetDefaultIcons[key] ?? 'share_outlined';
                final icon = kShareTargetIconOptions[iconKey] ?? Icons.share_outlined;
                final colorHex = t['color_override'] as String?;
                final color = colorHex != null ? _hexToColor(colorHex) : Theme.of(ctx).colorScheme.primary;

                return InkWell(
                  onTap: () {
                    Navigator.pop(ctx);
                    Share.shareXFiles(files, text: text);
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 68,
                    child: Column(
                      children: [
                        Container(
                          width: 52, height: 52,
                          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                          child: Icon(icon, color: color, size: 24),
                        ),
                        const SizedBox(height: 6),
                        Text(label, style: const TextStyle(fontSize: 11), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    ),
  );
}

Color _hexToColor(String hex) {
  var h = hex.replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  return Color(int.parse(h, radix: 16));
}
