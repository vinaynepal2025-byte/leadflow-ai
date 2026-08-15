import 'package:flutter/material.dart';

/// Theme Engine v2 — foundation.
///
/// The root cause of every theme "looking cheap" in dark mode: the whole
/// app's background and card colors were hardcoded flat constants
/// (Color(0xFF14171F), Color(0xFF1E2230)) completely independent of the
/// theme's own primary color. A cyan-accented theme and a purple-accented
/// theme rendered the *exact same* background and card color -- only the
/// buttons differed. That's why 19 "distinct" templates all read as "one
/// grey app with different-colored buttons."
///
/// This derives a small tonal palette (Material 3's own technique, and
/// the same one Stripe/Linear/Vercel use in their own dark modes) FROM
/// the theme's seed color via HSL, so background/surface always carry a
/// subtle hint of the theme's own hue instead of being generic.
class TonalPalette {
  final Color background; // base canvas (scaffold)
  final Color surfaceLow; // cards, list tiles -- one step lifted off background
  final Color surfaceHigh; // dialogs, sheets, app bar -- two steps lifted
  final Color onSurface; // text/icon color that reads correctly on all three above

  const TonalPalette({
    required this.background,
    required this.surfaceLow,
    required this.surfaceHigh,
    required this.onSurface,
  });
}

/// [saturationBoost] lets a template lean the tint stronger or weaker
/// without changing its actual hue -- e.g. a "Minimal Mono" template can
/// pass a near-zero boost for an almost-neutral grey, while "Holographic
/// Lens" can pass a high boost for a much more visibly tinted dark
/// surface. Defaults to a tasteful, always-safe middle value.
TonalPalette deriveTonalPalette(Color seed, bool isDark, {double saturationBoost = 1.0}) {
  final hsl = HSLColor.fromColor(seed);
  double sat(double base) => (hsl.saturation * base * saturationBoost).clamp(0.0, 1.0);

  if (isDark) {
    // Very low lightness so it still reads as "dark app," but never
    // fully desaturated -- that residual saturation is the whole fix.
    final background = hsl.withLightness(0.07).withSaturation(sat(0.35)).toColor();
    final surfaceLow = hsl.withLightness(0.13).withSaturation(sat(0.30)).toColor();
    final surfaceHigh = hsl.withLightness(0.19).withSaturation(sat(0.26)).toColor();
    return TonalPalette(background: background, surfaceLow: surfaceLow, surfaceHigh: surfaceHigh, onSurface: Colors.white);
  }

  // Light mode was already less "cheap-feeling" than dark (white/paper
  // reads clean regardless), but it had the identical structural gap:
  // zero relationship to the theme's own hue. A near-white background
  // with a whisper of tint, and genuinely pure-white cards floating on
  // top of it, is what makes light Stripe/Notion-style UIs feel
  // considered rather than a default Bootstrap white.
  final background = hsl.withLightness(0.98).withSaturation(sat(0.12)).toColor();
  const surfaceLow = Colors.white;
  final surfaceHigh = hsl.withLightness(0.995).withSaturation(sat(0.05)).toColor();
  return TonalPalette(background: background, surfaceLow: surfaceLow, surfaceHigh: surfaceHigh, onSurface: const Color(0xFF1B2A4A));
}
