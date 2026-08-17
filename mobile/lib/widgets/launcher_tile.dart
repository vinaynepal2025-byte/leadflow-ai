import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/edit_mode_settings.dart';

/// A single "destination" tile — tinted/gradient/glow/glass card
/// background with a centred icon and label. This is the one shared
/// premium visual language for every "menu of destinations" screen in
/// the app (More, Settings, Lead Detail's Modules grid) so they read as
/// one consistent design system instead of each screen inventing its
/// own flat ListTile look. style_variant/gradientEnd map directly onto
/// the same per-item override fields the backend-customizable screens
/// (More Menu, Lead Detail sections) already persist; screens with no
/// backend customization yet (like Settings) can just pass a fixed
/// colour and 'flat' variant.
///
/// Edit Mode: when [onEditTap] is set and EditModeSettings.enabled is
/// true, this tile shows a small pencil badge and taps open the quick
/// style editor (onEditTap) instead of the normal destination (onTap)
/// -- the live design-mode overlay ("koi bhi button/card ka look apne
/// hisaab se design kar sake"). Tiles that pass null for onEditTap
/// (nothing to persist a style change to yet, e.g. Settings'
/// destinations) are simply unaffected by Edit Mode, same as before.
class LauncherTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Color? gradientEnd;
  final String styleVariant;
  final VoidCallback onTap;
  final VoidCallback? onEditTap;

  const LauncherTile({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    this.gradientEnd,
    this.styleVariant = 'flat',
    required this.onTap,
    this.onEditTap,
  });

  BoxDecoration _decoration(BorderRadius radius, bool editing) {
    switch (styleVariant) {
      case 'gradient_badge':
        return BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color, gradientEnd ?? color.withValues(alpha: 0.6)]),
          borderRadius: radius,
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4))],
          border: editing ? Border.all(color: Colors.white, width: 2) : null,
        );
      case 'glow':
        return BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: radius,
          border: Border.all(color: editing ? color : color.withValues(alpha: 0.3), width: editing ? 2 : 1),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 14, spreadRadius: 1)],
        );
      case 'glass':
        return BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: radius,
          border: Border.all(color: editing ? color : Colors.white.withValues(alpha: 0.35), width: editing ? 2 : 1),
        );
      default:
        return BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: radius,
          border: Border.all(color: editing ? color : color.withValues(alpha: 0.28), width: editing ? 2 : 1),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    final onGradient = styleVariant == 'gradient_badge';
    final editModeOn = onEditTap != null && context.watch<EditModeSettings>().enabled;

    return Stack(
      children: [
        InkWell(
          onTap: editModeOn ? onEditTap : onTap,
          borderRadius: radius,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            decoration: _decoration(radius, editModeOn),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 26, color: onGradient ? Colors.white : color),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.2, color: onGradient ? Colors.white : null),
                ),
              ],
            ),
          ),
        ),
        if (editModeOn)
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)]),
              child: const Icon(Icons.edit, size: 11, color: Colors.white),
            ),
          ),
      ],
    );
  }
}
