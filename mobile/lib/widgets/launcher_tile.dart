import 'package:flutter/material.dart';

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
class LauncherTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Color? gradientEnd;
  final String styleVariant;
  final VoidCallback onTap;

  const LauncherTile({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    this.gradientEnd,
    this.styleVariant = 'flat',
    required this.onTap,
  });

  BoxDecoration _decoration(BorderRadius radius) {
    switch (styleVariant) {
      case 'gradient_badge':
        return BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color, gradientEnd ?? color.withValues(alpha: 0.6)]),
          borderRadius: radius,
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4))],
        );
      case 'glow':
        return BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: radius,
          border: Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 14, spreadRadius: 1)],
        );
      case 'glass':
        return BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: radius,
          border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
        );
      default:
        return BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: radius,
          border: Border.all(color: color.withValues(alpha: 0.28)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    final onGradient = styleVariant == 'gradient_badge';
    return InkWell(
      onTap: onTap,
      borderRadius: radius,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: _decoration(radius),
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
    );
  }
}
