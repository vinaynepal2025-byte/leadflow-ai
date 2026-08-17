import 'dart:math' as math;
import 'dart:ui' as ui;
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
/// [styleJson] is the fine-grained layer on top of the 4 style_variant
/// presets -- independent knobs (corner radius, border, glow, blur,
/// content scale, texture) rather than another fixed look, because
/// "sirf 4 preset combos" turned out not to be enough control (real
/// user feedback: wanted resize/gradient/texture/sharpness/edge/glow/
/// blur as separate controls, "customizable studio jaisa"). Every key
/// is optional and falls back to the variant's existing default
/// behaviour, so a tile with no styleJson set looks exactly like it did
/// before this was added.
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
  final Map<String, dynamic>? styleJson;
  // A user-uploaded image icon (via the Asset Library) overrides the
  // built-in Material [icon] glyph entirely when set -- "icon upload ka
  // option" -- rendered at the same slot/size, tinted by nothing (a
  // photo/logo keeps its own colours) unlike the vector Icon it replaces.
  final String? iconImageUrl;
  final VoidCallback onTap;
  final VoidCallback? onEditTap;

  const LauncherTile({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    this.gradientEnd,
    this.styleVariant = 'flat',
    this.styleJson,
    this.iconImageUrl,
    required this.onTap,
    this.onEditTap,
  });

  double? get _cornerRadius => (styleJson?['cornerRadius'] as num?)?.toDouble();
  double get _contentScale => ((styleJson?['contentScale'] as num?)?.toDouble() ?? 1.0).clamp(0.7, 1.6);
  double get _blurAmount => ((styleJson?['blurAmount'] as num?)?.toDouble() ?? 0).clamp(0, 20);
  String? get _textureId => styleJson?['textureId'] as String?;

  Color? _hexOrNull(String? key) {
    final hex = styleJson?[key] as String?;
    if (hex == null || hex.isEmpty) return null;
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    final value = int.tryParse(h, radix: 16);
    return value == null ? null : Color(value);
  }

  BoxDecoration _decoration(BorderRadius radius, bool editing) {
    final customBorderColor = _hexOrNull('borderColor');
    final customBorderWidth = (styleJson?['borderWidth'] as num?)?.toDouble();
    final glowColor = _hexOrNull('glowColor');
    final glowIntensity = ((styleJson?['glowIntensity'] as num?)?.toDouble() ?? 0).clamp(0, 1);

    BoxDecoration base;
    switch (styleVariant) {
      case 'gradient_badge':
        base = BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color, gradientEnd ?? color.withValues(alpha: 0.6)]),
          borderRadius: radius,
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4))],
          border: editing ? Border.all(color: Colors.white, width: 2) : null,
        );
        break;
      case 'glow':
        base = BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: radius,
          border: Border.all(color: editing ? color : color.withValues(alpha: 0.3), width: editing ? 2 : 1),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 14, spreadRadius: 1)],
        );
        break;
      case 'glass':
        base = BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: radius,
          border: Border.all(color: editing ? color : Colors.white.withValues(alpha: 0.35), width: editing ? 2 : 1),
        );
        break;
      default:
        base = BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: radius,
          border: Border.all(color: editing ? color : color.withValues(alpha: 0.28), width: editing ? 2 : 1),
        );
    }

    // Fine-grained overrides layer on top of whichever preset was picked
    // -- a custom border/glow always wins over the variant's own, so
    // "flat but with a strong glow" or "gradient with a thin gold edge"
    // are both reachable without a fifth/sixth/seventh preset name.
    return base.copyWith(
      border: editing
          ? base.border
          : (customBorderColor != null
              ? Border.all(color: customBorderColor, width: customBorderWidth ?? 1.5)
              : base.border),
      boxShadow: glowColor != null && glowIntensity > 0
          ? [
              ...?base.boxShadow,
              BoxShadow(
                color: glowColor.withValues(alpha: 0.25 + glowIntensity * 0.55),
                blurRadius: 6 + glowIntensity * 24,
                spreadRadius: glowIntensity * 3,
              ),
            ]
          : base.boxShadow,
    );
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular((_cornerRadius ?? 16).clamp(0, 40));
    final onGradient = styleVariant == 'gradient_badge';
    final editModeOn = onEditTap != null && context.watch<EditModeSettings>().enabled;
    final scale = _contentScale;

    Widget content = Container(
      padding: EdgeInsets.symmetric(vertical: 12 * scale, horizontal: 6),
      decoration: _decoration(radius, editModeOn),
      child: Stack(
        children: [
          if (_textureId != null && _textureId != 'none')
            Positioned.fill(
              child: ClipRRect(
                borderRadius: radius,
                child: CustomPaint(
                  painter: TileTexturePainter(
                    textureId: _textureId!,
                    color: (onGradient ? Colors.white : color).withValues(alpha: 0.14),
                  ),
                ),
              ),
            ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              iconImageUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        iconImageUrl!,
                        width: 30 * scale,
                        height: 30 * scale,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(icon, size: 26 * scale, color: onGradient ? Colors.white : color),
                      ),
                    )
                  : Icon(icon, size: 26 * scale, color: onGradient ? Colors.white : color),
              SizedBox(height: 8 * scale),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5 * scale, fontWeight: FontWeight.w600, height: 1.2, color: onGradient ? Colors.white : null),
              ),
            ],
          ),
        ],
      ),
    );

    if (_blurAmount > 0) {
      content = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: _blurAmount, sigmaY: _blurAmount),
          child: content,
        ),
      );
    }

    return Stack(
      children: [
        InkWell(
          onTap: editModeOn ? onEditTap : onTap,
          borderRadius: radius,
          child: content,
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

/// Named IDs a texture picker offers -- kept small and honest: real
/// procedural patterns, not a claim of photographic/material textures
/// this app doesn't have assets for.
const Map<String, String> kTileTextureLabels = {
  'none': 'None',
  'dots': 'Dots',
  'diagonal_lines': 'Diagonal lines',
  'grid': 'Grid',
  'noise': 'Noise',
  'crosshatch': 'Crosshatch',
  'waves': 'Waves',
  'chevron': 'Chevron',
  'brick': 'Brick',
  'honeycomb': 'Honeycomb',
  'checkerboard': 'Checkerboard',
  'stars': 'Stars',
  'confetti': 'Confetti',
};

/// Draws one of [kTileTextureLabels]'s patterns, clipped to the tile's
/// own rounded rect by the caller. Deterministic (no randomness that
/// would repaint differently frame to frame) -- 'noise' uses a fixed
/// seed so it looks like grain, not a flicker.
class TileTexturePainter extends CustomPainter {
  final String textureId;
  final Color color;

  const TileTexturePainter({required this.textureId, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    switch (textureId) {
      case 'dots':
        const spacing = 10.0;
        for (double y = spacing / 2; y < size.height; y += spacing) {
          for (double x = spacing / 2; x < size.width; x += spacing) {
            canvas.drawCircle(Offset(x, y), 1.1, paint);
          }
        }
        break;
      case 'diagonal_lines':
        final linePaint = Paint()
          ..color = color
          ..strokeWidth = 1.2;
        const spacing = 9.0;
        for (double x = -size.height; x < size.width; x += spacing) {
          canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), linePaint);
        }
        break;
      case 'grid':
        final linePaint = Paint()
          ..color = color
          ..strokeWidth = 1.0;
        const spacing = 12.0;
        for (double x = 0; x < size.width; x += spacing) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
        }
        for (double y = 0; y < size.height; y += spacing) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
        }
        break;
      case 'noise':
        final rnd = math.Random(42); // fixed seed -- deterministic grain
        final dotPaint = Paint()..color = color;
        final count = (size.width * size.height / 18).round();
        for (var i = 0; i < count; i++) {
          final dx = rnd.nextDouble() * size.width;
          final dy = rnd.nextDouble() * size.height;
          canvas.drawCircle(Offset(dx, dy), 0.6 + rnd.nextDouble() * 0.6, dotPaint);
        }
        break;
      case 'crosshatch':
        final linePaint = Paint()
          ..color = color
          ..strokeWidth = 1.0;
        const spacing = 10.0;
        for (double x = -size.height; x < size.width; x += spacing) {
          canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), linePaint);
          canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), linePaint);
        }
        break;
      case 'waves':
        final wavePaint = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        const rowSpacing = 11.0;
        const waveLength = 16.0;
        const amplitude = 3.0;
        for (double y = rowSpacing; y < size.height; y += rowSpacing) {
          final path = Path()..moveTo(0, y);
          for (double x = 0; x <= size.width; x += waveLength / 2) {
            final crest = ((x / (waveLength / 2)).round().isEven) ? y - amplitude : y + amplitude;
            path.lineTo(x, crest);
          }
          canvas.drawPath(path, wavePaint);
        }
        break;
      case 'chevron':
        final chevPaint = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3;
        const step = 10.0;
        for (double y = -step; y < size.height + step; y += step) {
          final path = Path()..moveTo(0, y);
          for (double x = 0; x <= size.width; x += step) {
            path.lineTo(x + step / 2, y + (((x / step).round().isEven) ? step / 2 : -step / 2));
          }
          canvas.drawPath(path, chevPaint);
        }
        break;
      case 'brick':
        final brickPaint = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
        const brickW = 20.0;
        const brickH = 9.0;
        var row = 0;
        for (double y = 0; y < size.height; y += brickH) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), brickPaint);
          final offset = (row.isOdd) ? brickW / 2 : 0.0;
          for (double x = -offset; x < size.width; x += brickW) {
            canvas.drawLine(Offset(x, y), Offset(x, y + brickH), brickPaint);
          }
          row++;
        }
        break;
      case 'honeycomb':
        final hexPaint = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
        const hexRadius = 7.0;
        const hexHeight = hexRadius * 1.732;
        var hexRow = 0;
        for (double cy = 0; cy < size.height + hexHeight; cy += hexHeight * 0.75) {
          final offsetX = (hexRow.isOdd) ? hexRadius * 1.5 : 0.0;
          for (double cx = offsetX; cx < size.width + hexRadius * 3; cx += hexRadius * 3) {
            final path = Path();
            for (var i = 0; i < 6; i++) {
              final angle = math.pi / 3 * i;
              final px = cx + hexRadius * math.cos(angle);
              final py = cy + hexRadius * math.sin(angle);
              if (i == 0) {
                path.moveTo(px, py);
              } else {
                path.lineTo(px, py);
              }
            }
            path.close();
            canvas.drawPath(path, hexPaint);
          }
          hexRow++;
        }
        break;
      case 'checkerboard':
        const cell = 9.0;
        var checkRow = 0;
        for (double y = 0; y < size.height; y += cell) {
          var col = 0;
          for (double x = 0; x < size.width; x += cell) {
            if ((checkRow + col).isEven) {
              canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), paint);
            }
            col++;
          }
          checkRow++;
        }
        break;
      case 'stars':
        final rnd = math.Random(7);
        const spacing = 22.0;
        for (double y = spacing / 2; y < size.height; y += spacing) {
          for (double x = spacing / 2; x < size.width; x += spacing) {
            final jitterX = x + (rnd.nextDouble() - 0.5) * 6;
            final jitterY = y + (rnd.nextDouble() - 0.5) * 6;
            _drawStar(canvas, Offset(jitterX, jitterY), 3.0, paint);
          }
        }
        break;
      case 'confetti':
        final rnd = math.Random(13); // fixed seed -- deterministic
        final confettiPaint = Paint()..color = color;
        final count = (size.width * size.height / 90).round();
        for (var i = 0; i < count; i++) {
          final cx = rnd.nextDouble() * size.width;
          final cy = rnd.nextDouble() * size.height;
          final angle = rnd.nextDouble() * math.pi;
          canvas.save();
          canvas.translate(cx, cy);
          canvas.rotate(angle);
          canvas.drawRect(const Rect.fromLTWH(-2, -1, 4, 2), confettiPaint);
          canvas.restore();
        }
        break;
    }
  }

  void _drawStar(Canvas canvas, Offset center, double radius, Paint paint) {
    final path = Path();
    for (var i = 0; i < 4; i++) {
      final angle = math.pi / 2 * i;
      final outer = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      final innerAngle = angle + math.pi / 4;
      final inner = center + Offset(math.cos(innerAngle), math.sin(innerAngle)) * (radius * 0.4);
      if (i == 0) {
        path.moveTo(outer.dx, outer.dy);
      } else {
        path.lineTo(outer.dx, outer.dy);
      }
      path.lineTo(inner.dx, inner.dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant TileTexturePainter old) =>
      old.textureId != textureId || old.color != color;
}
