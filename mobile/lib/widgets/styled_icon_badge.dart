import 'dart:ui';
import 'package:flutter/material.dart';

/// Per-item visual style control -- the "look and style" layer on top
/// of the registry pattern (Lead Detail sections, Share Targets, More
/// Menu items). Where a plain tinted Icon() only lets each item pick a
/// flat colour, this renders a genuinely styled badge -- gradient fill,
/// glow, or frosted glass -- matching the same visual language the
/// app-wide Theme Engine (Aurora, gradient buttons, glass mode) already
/// uses, but chosen per-element instead of applied globally.
///
/// Deliberately reused across every registry screen that wants richer
/// per-item styling, rather than re-implemented per screen.
Widget styledIconBadge({
  required IconData icon,
  required Color color,
  Color? gradientEnd,
  String styleVariant = 'flat',
  double size = 40,
}) {
  final iconSize = size * 0.52;

  switch (styleVariant) {
    case 'gradient_badge':
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color, gradientEnd ?? color.withValues(alpha: 0.55)],
          ),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: iconSize),
      );

    case 'glow':
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.12),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 16, spreadRadius: 1),
          ],
        ),
        child: Icon(icon, color: color, size: iconSize),
      );

    case 'glass':
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
            ),
            child: Icon(icon, color: color, size: iconSize),
          ),
        ),
      );

    default: // 'flat' -- same look as before this feature, zero visual
      // change for anyone who hasn't touched the new style picker.
      return Icon(icon, color: color, size: size * 0.85);
  }
}

/// Human-readable labels for the style-variant picker UI.
const Map<String, String> kStyleVariantLabels = {
  'flat': 'Flat',
  'gradient_badge': 'Gradient Badge',
  'glow': 'Glow',
  'glass': 'Glass',
};
