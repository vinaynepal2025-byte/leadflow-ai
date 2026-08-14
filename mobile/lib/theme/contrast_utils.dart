import 'dart:math' as math;
import 'package:flutter/material.dart';

/// WCAG 2.1 contrast-ratio math, kept dependency-free (pure functions on
/// Color) so it can be reused anywhere a color gets picked -- the
/// Customize Studio's color picker today, and potentially the Settings >
/// Colors section or a future "check my whole theme" audit later.
///
/// Batch 3 of the Customize Studio master-prompt: "premium apps kabhi
/// accessibility todhte nahi" -- a real-time AA/AAA badge next to every
/// color control, not a one-time warning that's easy to ignore.
class ContrastUtils {
  ContrastUtils._();

  /// WCAG relative luminance (0.0 = black, 1.0 = white). Formula per
  /// https://www.w3.org/TR/WCAG21/#dfn-relative-luminance -- each channel
  /// is gamma-corrected before the weighted sum, not just averaged.
  static double relativeLuminance(Color c) {
    double gamma(double v) {
      if (v <= 0.03928) return v / 12.92;
      return math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    }

    final r = gamma(c.r);
    final g = gamma(c.g);
    final b = gamma(c.b);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  /// Contrast ratio between two colors, always >= 1.0 (identical colors)
  /// and <= 21.0 (pure black vs pure white). Order of arguments doesn't
  /// matter -- the formula is symmetric.
  static double contrastRatio(Color a, Color b) {
    final l1 = relativeLuminance(a);
    final l2 = relativeLuminance(b);
    final lighter = l1 > l2 ? l1 : l2;
    final darker = l1 > l2 ? l2 : l1;
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// WCAG level for normal-size text at the given ratio. Large text
  /// (18pt+/14pt+bold) has lower thresholds (3.0/4.5) but this app's
  /// primary/accent/status colors are used for buttons, chips and small
  /// labels far more often than large headings, so normal-text
  /// thresholds are the safer default to grade against.
  static ContrastLevel levelFor(double ratio) {
    if (ratio >= 7.0) return ContrastLevel.aaa;
    if (ratio >= 4.5) return ContrastLevel.aa;
    if (ratio >= 3.0) return ContrastLevel.aaLarge;
    return ContrastLevel.fail;
  }
}

enum ContrastLevel {
  aaa('AAA', Color(0xFF16A34A)),
  aa('AA', Color(0xFF16A34A)),
  aaLarge('AA · large text only', Color(0xFFCA8A04)),
  fail('Fails WCAG', Color(0xFFDC2626));

  final String label;
  final Color badgeColor;
  const ContrastLevel(this.label, this.badgeColor);
}
