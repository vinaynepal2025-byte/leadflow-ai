import 'dart:ui';
import 'package:flutter/material.dart';

/// Theme Engine v3 -- the actual fix for "glass mein glass wala feel
/// nahi aa raha." A flat LinearGradient behind a BackdropFilter just
/// produces one uniform tinted panel -- real premium glass UIs (iOS
/// Control Center, the reference screenshots) get their depth from
/// several large, independently-positioned, heavily-blurred colour
/// blobs sitting behind the content, so the blur actually has varied
/// colour and light to pick up as it samples different parts of the
/// screen. This is that layer: cheap to build (three circles), correct
/// to render (ImageFiltered blur, not a fake gradient), and fully
/// driven by the user's own primary/accent colours so it always
/// matches their theme rather than being a fixed decoration.
class AuroraBackdrop extends StatelessWidget {
  final Color primary;
  final Color accent;
  final Color background;
  final double intensity;

  const AuroraBackdrop({
    super.key,
    required this.primary,
    required this.accent,
    required this.background,
    this.intensity = 1.0,
  });

  Widget _blob({
    double? top,
    double? bottom,
    double? left,
    double? right,
    required double diameter,
    required Color color,
    required double blurSigma,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final clampedIntensity = intensity.clamp(0.0, 1.0);
    final blurSigma = 70 * clampedIntensity;
    final blobAlpha = 0.55 * clampedIntensity;

    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: background)),
        _blob(
          top: -size.height * 0.10,
          left: -size.width * 0.30,
          diameter: size.width * 1.0,
          color: primary.withValues(alpha: blobAlpha),
          blurSigma: blurSigma,
        ),
        _blob(
          top: size.height * 0.15,
          right: -size.width * 0.35,
          diameter: size.width * 0.90,
          color: accent.withValues(alpha: blobAlpha * 0.9),
          blurSigma: blurSigma,
        ),
        _blob(
          bottom: -size.height * 0.18,
          left: size.width * 0.05,
          diameter: size.width * 0.80,
          color: primary.withValues(alpha: blobAlpha * 0.75),
          blurSigma: blurSigma,
        ),
      ],
    );
  }
}
