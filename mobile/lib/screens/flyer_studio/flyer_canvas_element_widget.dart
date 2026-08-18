// FlyerCanvasElementWidget — the reusable drag/resize/rotate interaction
// wrapper. Works identically for text, image, logo, and shape elements —
// the element's `type` only decides what renders *inside* the wrapper, not
// how it's manipulated. This is the "no-limitations freeform canvas" core:
// any element can go anywhere, any size, any angle.
//
// Coordinate model: the parent (FlyerStudioScreen) renders the canvas at a
// fixed on-screen pixel size and passes down `scale` (screenPx / canvasPx).
// Element x/y/width/height are always in CANVAS units and get multiplied by
// `scale` for layout; drag deltas get divided by `scale` on the way back.
// So a design made on a small phone renders identically at full 1080px+
// export resolution.
//
// Small-screen decisions that shaped this:
// - Handles are a 26px dot inside a 40px transparent hit area, because a
//   24px target under a thumb on a 6-inch screen is genuinely hard to grab.
// - Handles only appear when selected, so an unselected canvas reads as the
//   actual flyer rather than a mess of editor chrome.
// - Locked elements ignore drag/resize/rotate entirely, so a finished
//   background photo can't be knocked out of place while editing text on
//   top of it.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../../theme/appearance_settings.dart';
import 'flyer_element.dart';

typedef ElementChanged = void Function(FlyerElement element);

Color flyerHexToColor(String hex, {double opacity = 1.0}) {
  // 'transparent' is a sentinel, not a real hex value -- used by Logo
  // Studio (a logo composites onto other designs, so a genuinely
  // transparent canvas background matters there in a way it never did
  // for flyers, which always render onto an opaque page).
  if (hex == 'transparent') return Colors.transparent;
  var h = hex.replaceAll('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return Colors.black.withOpacity(opacity);
  final value = int.tryParse(h, radix: 16);
  if (value == null) return Colors.black.withOpacity(opacity);
  return Color(value).withOpacity(opacity);
}

/// Photo adjustments (Canva-parity Phase C, see CANVA_PARITY_PLAN.md) --
/// combines brightness/contrast/saturation into the single 4x5 matrix
/// `ColorFilter.matrix` accepts, entirely client-side, no new dependency.
/// Flutter's matrix operates on channel values in the 0-255 range (not
/// 0-1), with the 5th column of each row being an additive offset in
/// that same range.
List<double> imageAdjustmentMatrix({
  required double brightness, // -100..100
  required double contrast, // -100..100
  required double saturation, // 0 (greyscale) .. 2 (double), 1 = no change
}) {
  // Standard luminance-preserving saturation matrix.
  const lumR = 0.2126, lumG = 0.7152, lumB = 0.0722;
  final sr = (1 - saturation) * lumR;
  final sg = (1 - saturation) * lumG;
  final sb = (1 - saturation) * lumB;
  final saturationMatrix = <double>[
    sr + saturation, sg, sb, 0, 0,
    sr, sg + saturation, sb, 0, 0,
    sr, sg, sb + saturation, 0, 0,
    0, 0, 0, 1, 0,
  ];

  // contrast: -100..100 -> a multiplicative factor around 1.0, pivoting
  // around mid-grey (128) so contrast changes don't also shift brightness.
  final contrastFactor = 1 + (contrast.clamp(-100, 100) / 100);
  final contrastOffset = 128 * (1 - contrastFactor);
  final contrastMatrix = <double>[
    contrastFactor, 0, 0, 0, contrastOffset,
    0, contrastFactor, 0, 0, contrastOffset,
    0, 0, contrastFactor, 0, contrastOffset,
    0, 0, 0, 1, 0,
  ];

  final brightnessOffset = brightness.clamp(-100, 100).toDouble();
  final brightnessMatrix = <double>[
    1, 0, 0, 0, brightnessOffset,
    0, 1, 0, 0, brightnessOffset,
    0, 0, 1, 0, brightnessOffset,
    0, 0, 0, 1, 0,
  ];

  // Compose as brightness(contrast(saturation(colour))) -- apply
  // saturation first (so contrast/brightness act on the final tone), via
  // proper 5x5 homogeneous matrix multiplication (each 4x5 input
  // represents a 5x5 affine matrix with an implicit [0,0,0,0,1] last row).
  return _multiplyColorMatrices(brightnessMatrix, _multiplyColorMatrices(contrastMatrix, saturationMatrix));
}

List<double> _multiplyColorMatrices(List<double> a, List<double> b) {
  List<List<double>> to5x5(List<double> m) => [
        [m[0], m[1], m[2], m[3], m[4]],
        [m[5], m[6], m[7], m[8], m[9]],
        [m[10], m[11], m[12], m[13], m[14]],
        [m[15], m[16], m[17], m[18], m[19]],
        [0, 0, 0, 0, 1],
      ];
  final ma = to5x5(a);
  final mb = to5x5(b);
  final result = List.generate(5, (_) => List<double>.filled(5, 0));
  for (var i = 0; i < 5; i++) {
    for (var j = 0; j < 5; j++) {
      var sum = 0.0;
      for (var k = 0; k < 5; k++) {
        sum += ma[i][k] * mb[k][j];
      }
      result[i][j] = sum;
    }
  }
  return [
    result[0][0], result[0][1], result[0][2], result[0][3], result[0][4],
    result[1][0], result[1][1], result[1][2], result[1][3], result[1][4],
    result[2][0], result[2][1], result[2][2], result[2][3], result[2][4],
    result[3][0], result[3][1], result[3][2], result[3][3], result[3][4],
  ];
}

String flyerColorToHex(Color c) =>
    '#${c.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

/// A single alignment guide line shown while dragging. Canvas-bound guides
/// (page centre/edges) are red; guides that align against a sibling
/// element's own edges/centre are magenta — the same red-vs-magenta split
/// Figma/Canva use so a counsellor can tell "centred on the page" from
/// "lined up with that other headline" at a glance.
class FlyerSnapGuide {
  final bool vertical;
  final double position; // canvas units
  final Color color;

  const FlyerSnapGuide({
    required this.vertical,
    required this.position,
    this.color = const Color(0xFFE5484D),
  });
}

/// Paints active snap guides over the canvas.
class FlyerSnapGuidePainter extends CustomPainter {
  final List<FlyerSnapGuide> guides;
  final double scale;

  FlyerSnapGuidePainter({required this.guides, required this.scale});

  @override
  void paint(Canvas canvas, Size size) {
    if (guides.isEmpty) return;
    for (final g in guides) {
      final paint = Paint()
        ..color = g.color
        ..strokeWidth = 1;
      final p = g.position * scale;
      if (g.vertical) {
        canvas.drawLine(Offset(p, 0), Offset(p, size.height), paint);
      } else {
        canvas.drawLine(Offset(0, p), Offset(size.width, p), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant FlyerSnapGuidePainter old) =>
      old.guides.length != guides.length;
}

/// A faint 10x10 alignment grid, purely a visual placement aid (never
/// exported -- callers only mount this outside `exporting` mode). Off by
/// default; toggled from the Background & size sheet.
/// The classic grey/white checkerboard indicating "genuinely
/// transparent" -- shown BEHIND the canvas (outside its RepaintBoundary)
/// when Logo Studio's background is set to transparent, so the person
/// editing can see exactly what won't render, without that pattern
/// itself ever ending up baked into the exported PNG.
class CheckerboardPainter extends CustomPainter {
  final double cellSize;
  const CheckerboardPainter({this.cellSize = 12});

  @override
  void paint(Canvas canvas, Size size) {
    final light = Paint()..color = const Color(0xFFF0F0F0);
    final dark = Paint()..color = const Color(0xFFD8D8D8);
    canvas.drawRect(Offset.zero & size, light);
    final cols = (size.width / cellSize).ceil();
    final rows = (size.height / cellSize).ceil();
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        if ((row + col) % 2 == 0) continue;
        canvas.drawRect(
          Rect.fromLTWH(col * cellSize, row * cellSize, cellSize, cellSize),
          dark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CheckerboardPainter old) => old.cellSize != cellSize;
}

class FlyerGridPainter extends CustomPainter {
  final double scale;
  final double canvasWidth;
  final double canvasHeight;

  const FlyerGridPainter({
    required this.scale,
    required this.canvasWidth,
    required this.canvasHeight,
  });

  static const int _divisions = 10;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (var i = 1; i < _divisions; i++) {
      final x = canvasWidth * i / _divisions * scale;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      final y = canvasHeight * i / _divisions * scale;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant FlyerGridPainter old) =>
      old.scale != scale ||
      old.canvasWidth != canvasWidth ||
      old.canvasHeight != canvasHeight;
}

/// Numbered tick marks along the canvas's top and left edges, in canvas
/// units (not screen pixels) -- lets a counsellor place something "at
/// exactly 200" instead of eyeballing it. Draws inside the canvas bounds
/// as a thin translucent band rather than reserving extra layout space
/// around the canvas, so it never changes the canvas's on-screen scale.
/// Same "never exported" rule as the grid.
class FlyerRulerPainter extends CustomPainter {
  final double scale;
  final double canvasWidth;
  final double canvasHeight;

  const FlyerRulerPainter({
    required this.scale,
    required this.canvasWidth,
    required this.canvasHeight,
  });

  static const double _step = 100; // canvas units between labelled ticks
  static const double _bandThickness = 14;

  @override
  void paint(Canvas canvas, Size size) {
    final bandPaint = Paint()..color = Colors.black.withValues(alpha: 0.35);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, _bandThickness), bandPaint);
    canvas.drawRect(Rect.fromLTWH(0, 0, _bandThickness, size.height), bandPaint);

    final tickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..strokeWidth = 1;
    const textStyle = TextStyle(color: Colors.white, fontSize: 8);

    for (var u = 0.0; u <= canvasWidth; u += _step) {
      final x = u * scale;
      if (x > size.width) break;
      canvas.drawLine(Offset(x, 0), Offset(x, _bandThickness), tickPaint);
      final tp = TextPainter(
        text: TextSpan(text: u.toInt().toString(), style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x + 2, 1));
    }
    for (var u = 0.0; u <= canvasHeight; u += _step) {
      final y = u * scale;
      if (y > size.height) break;
      canvas.drawLine(Offset(0, y), Offset(_bandThickness, y), tickPaint);
      final tp = TextPainter(
        text: TextSpan(text: u.toInt().toString(), style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(1, y + 1));
    }
  }

  @override
  bool shouldRepaint(covariant FlyerRulerPainter old) =>
      old.scale != scale ||
      old.canvasWidth != canvasWidth ||
      old.canvasHeight != canvasHeight;
}

/// A 5-point star path, shared by FlyerShapePainter's own 'star' shape
/// kind and by frame masking (framePathFor) below -- one definition
/// rather than two copies that could drift.
Path starPath(Size size) {
  const points = 5;
  final w = size.width, h = size.height;
  final cx = w / 2, cy = h / 2;
  final outerR = math.min(w, h) / 2;
  final innerR = outerR * 0.42;
  final path = Path();
  for (var i = 0; i < points * 2; i++) {
    final r = i.isEven ? outerR : innerR;
    final angle = (math.pi / points) * i - math.pi / 2;
    final x = cx + r * math.cos(angle);
    final y = cy + r * math.sin(angle);
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  path.close();
  return path;
}

Path _hexagonPath(Size size) {
  final w = size.width, h = size.height;
  final cx = w / 2, cy = h / 2;
  final r = math.min(w, h) / 2;
  final path = Path();
  for (var i = 0; i < 6; i++) {
    final angle = (math.pi / 3) * i - math.pi / 2;
    final x = cx + r * math.cos(angle);
    final y = cy + r * math.sin(angle);
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  path.close();
  return path;
}

/// An organic "blob" frame -- a smooth closed curve through 8 points at
/// a deterministically wobbled radius (fixed multi-frequency sine/cosine
/// perturbation, not random, so the same element renders identically
/// every time rather than jittering between rebuilds), connected with
/// quadratic beziers through midpoints for a rounded, non-polygonal feel.
Path _blobPath(Size size) {
  final w = size.width, h = size.height;
  final cx = w / 2, cy = h / 2;
  final baseR = math.min(w, h) / 2;
  const n = 8;
  final pts = <Offset>[];
  for (var i = 0; i < n; i++) {
    final angle = (2 * math.pi / n) * i;
    final r = baseR * (1 + 0.16 * math.sin(3 * angle) + 0.08 * math.cos(5 * angle));
    pts.add(Offset(cx + r * math.cos(angle), cy + r * math.sin(angle)));
  }
  final path = Path()..moveTo((pts[0].dx + pts[n - 1].dx) / 2, (pts[0].dy + pts[n - 1].dy) / 2);
  for (var i = 0; i < n; i++) {
    final next = pts[(i + 1) % n];
    final mid = Offset((pts[i].dx + next.dx) / 2, (pts[i].dy + next.dy) / 2);
    path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
  }
  path.close();
  return path;
}

/// The frame shapes offered for masking an image/logo element (Canva-
/// parity Phase D). Returns null for 'rect' -- meaning "no mask, use the
/// normal ClipRRect+cornerRadius path" -- so an element with the default
/// shapeKind renders exactly as it did before frames existed.
Path? framePathFor(String kind, Size size) {
  switch (kind) {
    case 'circle':
      return Path()..addOval(Rect.fromLTWH(0, 0, size.width, size.height));
    case 'star':
      return starPath(size);
    case 'hexagon':
      return _hexagonPath(size);
    case 'blob':
      return _blobPath(size);
    default:
      return null;
  }
}

const Map<String, String> kFrameShapeLabels = {
  'rect': 'None',
  'circle': 'Circle',
  'star': 'Star',
  'hexagon': 'Hexagon',
  'blob': 'Blob',
};

class FramePathClipper extends CustomClipper<Path> {
  final String kind;
  const FramePathClipper({required this.kind});

  @override
  Path getClip(Size size) => framePathFor(kind, size) ?? (Path()..addRect(Offset.zero & size));

  @override
  bool shouldReclip(covariant FramePathClipper oldClipper) => oldClipper.kind != kind;
}

/// Draws the shape kinds that don't fit a plain BoxDecoration (triangle,
/// line, arrow, star). 'rect'/'circle' stay on BoxDecoration in
/// _buildContent -- cheaper, and the only kinds cornerRadius means
/// anything for.
class FlyerShapePainter extends CustomPainter {
  final String kind;
  final Color fillColor;
  final Color? fillColorEnd;
  final Color? strokeColor;
  final double strokeWidth;

  const FlyerShapePainter({
    required this.kind,
    required this.fillColor,
    this.fillColorEnd,
    this.strokeColor,
    this.strokeWidth = 0,
  });

  Path _pathFor(Size size) {
    final w = size.width;
    final h = size.height;
    switch (kind) {
      case 'line':
        return Path()
          ..moveTo(0, h / 2)
          ..lineTo(w, h / 2);
      case 'triangle':
        return Path()
          ..moveTo(w / 2, 0)
          ..lineTo(w, h)
          ..lineTo(0, h)
          ..close();
      case 'arrow':
        final shaftH = h * 0.35;
        final headW = w * 0.35;
        return Path()
          ..moveTo(0, h / 2 - shaftH / 2)
          ..lineTo(w - headW, h / 2 - shaftH / 2)
          ..lineTo(w - headW, 0)
          ..lineTo(w, h / 2)
          ..lineTo(w - headW, h)
          ..lineTo(w - headW, h / 2 + shaftH / 2)
          ..lineTo(0, h / 2 + shaftH / 2)
          ..close();
      case 'star':
        return starPath(Size(w, h));
      default:
        return Path()..addRect(Rect.fromLTWH(0, 0, w, h));
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _pathFor(size);

    if (kind != 'line') {
      final fillPaint = Paint()..style = PaintingStyle.fill;
      if (fillColorEnd != null) {
        fillPaint.shader = LinearGradient(colors: [fillColor, fillColorEnd!])
            .createShader(Offset.zero & size);
      } else {
        fillPaint.color = fillColor;
      }
      canvas.drawPath(path, fillPaint);
    }

    if (strokeColor != null && strokeWidth > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..color = strokeColor!
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );
    } else if (kind == 'line') {
      // A line has no fill to fall back on, so it always needs a visible
      // stroke -- use the shape colour itself when no explicit stroke was set.
      canvas.drawPath(
        path,
        Paint()
          ..color = fillColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth > 0 ? strokeWidth : 6
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant FlyerShapePainter old) =>
      old.kind != kind ||
      old.fillColor != fillColor ||
      old.fillColorEnd != fillColorEnd ||
      old.strokeColor != strokeColor ||
      old.strokeWidth != strokeWidth;
}

class FlyerCanvasElementWidget extends StatelessWidget {
  final FlyerElement element;
  final double scale;
  final bool selected;
  final bool exporting;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final ElementChanged onChanged;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final VoidCallback onDelete;
  final double canvasWidth;
  final double canvasHeight;
  final void Function(List<FlyerSnapGuide> guides) onSnapGuides;
  final List<FlyerElement> siblings;
  final bool groupMode;
  final bool groupSelected;

  const FlyerCanvasElementWidget({
    super.key,
    required this.element,
    required this.scale,
    required this.selected,
    required this.exporting,
    required this.onTap,
    required this.onDoubleTap,
    required this.onChanged,
    required this.onDragStart,
    required this.onDragEnd,
    required this.onDelete,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.onSnapGuides,
    this.siblings = const [],
    this.groupMode = false,
    this.groupSelected = false,
  });

  static const Color _groupHighlightColor = Color(0xFF9C6ADE);

  static const double _snapThreshold = 18; // canvas units
  static const Color _siblingGuideColor = Color(0xFFFF3366);

  void _applySnapping() {
    final guides = <FlyerSnapGuide>[];

    final centreX = element.x + element.width / 2;
    if ((centreX - canvasWidth / 2).abs() < _snapThreshold) {
      element.x = canvasWidth / 2 - element.width / 2;
      guides.add(FlyerSnapGuide(vertical: true, position: canvasWidth / 2));
    }
    final centreY = element.y + element.height / 2;
    if ((centreY - canvasHeight / 2).abs() < _snapThreshold) {
      element.y = canvasHeight / 2 - element.height / 2;
      guides.add(FlyerSnapGuide(vertical: false, position: canvasHeight / 2));
    }
    if (element.x.abs() < _snapThreshold) {
      element.x = 0;
      guides.add(const FlyerSnapGuide(vertical: true, position: 0));
    }
    if ((element.x + element.width - canvasWidth).abs() < _snapThreshold) {
      element.x = canvasWidth - element.width;
      guides.add(FlyerSnapGuide(vertical: true, position: canvasWidth));
    }
    if (element.y.abs() < _snapThreshold) {
      element.y = 0;
      guides.add(const FlyerSnapGuide(vertical: false, position: 0));
    }
    if ((element.y + element.height - canvasHeight).abs() < _snapThreshold) {
      element.y = canvasHeight - element.height;
      guides.add(FlyerSnapGuide(vertical: false, position: canvasHeight));
    }

    // Smart guides — align against a sibling element's edges/centre, the
    // way Figma/Canva highlight alignment against neighbouring objects,
    // not just the page bounds. One axis-lock per sibling (centre wins
    // over edges) keeps this from fighting itself on a single drag tick.
    for (final sib in siblings) {
      final sibCentreX = sib.x + sib.width / 2;
      final sibCentreY = sib.y + sib.height / 2;
      final myCentreX = element.x + element.width / 2;
      final myCentreY = element.y + element.height / 2;

      if ((myCentreX - sibCentreX).abs() < _snapThreshold) {
        element.x = sibCentreX - element.width / 2;
        guides.add(FlyerSnapGuide(
            vertical: true, position: sibCentreX, color: _siblingGuideColor));
      } else if ((element.x - sib.x).abs() < _snapThreshold) {
        element.x = sib.x;
        guides.add(FlyerSnapGuide(
            vertical: true, position: sib.x, color: _siblingGuideColor));
      } else if ((element.x + element.width - (sib.x + sib.width)).abs() <
          _snapThreshold) {
        element.x = sib.x + sib.width - element.width;
        guides.add(FlyerSnapGuide(
            vertical: true, position: sib.x + sib.width, color: _siblingGuideColor));
      }

      if ((myCentreY - sibCentreY).abs() < _snapThreshold) {
        element.y = sibCentreY - element.height / 2;
        guides.add(FlyerSnapGuide(
            vertical: false, position: sibCentreY, color: _siblingGuideColor));
      } else if ((element.y - sib.y).abs() < _snapThreshold) {
        element.y = sib.y;
        guides.add(FlyerSnapGuide(
            vertical: false, position: sib.y, color: _siblingGuideColor));
      } else if ((element.y + element.height - (sib.y + sib.height)).abs() <
          _snapThreshold) {
        element.y = sib.y + sib.height - element.height;
        guides.add(FlyerSnapGuide(
            vertical: false, position: sib.y + sib.height, color: _siblingGuideColor));
      }
    }

    onSnapGuides(guides);
  }

  /// Shared corner-resize math. `isLeftEdge`/`isTopEdge` say which edges
  /// this particular handle drags (e.g. the bottom-right handle drags
  /// neither, so the top-left corner stays the anchor). When the element's
  /// aspect ratio is locked, height is derived from the new width instead
  /// of read from the vertical drag delta, so a diagonal drag can't skew it.
  void _applyResize(Offset rawDelta, {required bool isLeftEdge, required bool isTopEdge}) {
    final dx = rawDelta.dx / scale;
    final dy = rawDelta.dy / scale;

    if (element.aspectLocked && element.height > 0 && element.width > 0) {
      final aspect = element.width / element.height;
      var newWidth = isLeftEdge ? element.width - dx : element.width + dx;
      newWidth = newWidth.clamp(20.0, 8000.0);
      final newHeight = (newWidth / aspect).clamp(20.0, 8000.0);
      if (isLeftEdge) element.x += element.width - newWidth;
      if (isTopEdge) element.y += element.height - newHeight;
      element.width = newWidth;
      element.height = newHeight;
      return;
    }

    if (isLeftEdge) {
      final newWidth = (element.width - dx).clamp(20.0, 8000.0);
      element.x += element.width - newWidth;
      element.width = newWidth;
    } else {
      element.width = (element.width + dx).clamp(20.0, 8000.0);
    }
    if (isTopEdge) {
      final newHeight = (element.height - dy).clamp(20.0, 8000.0);
      element.y += element.height - newHeight;
      element.height = newHeight;
    } else {
      element.height = (element.height + dy).clamp(20.0, 8000.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<AppearanceSettings>();
    final w = math.max(element.width * scale, 6.0);
    final h = math.max(element.height * scale, 6.0);
    // In group-select mode, taps toggle group membership instead of
    // dragging -- an accidental drag while trying to tap-select several
    // elements would be worse than losing per-element drag temporarily.
    final dragDisabled = element.locked || groupMode;
    final showSelBorder = selected || groupSelected;
    final selBorderColor = groupSelected
        ? _groupHighlightColor
        : (element.locked ? const Color(0xFF9AA0A6) : appearance.primaryColor);

    // During export we render the bare element with no chrome and no
    // gesture padding, so the exported PNG is exactly the design.
    if (exporting) {
      return Positioned(
        left: element.x * scale,
        top: element.y * scale,
        child: Transform.rotate(
          angle: element.rotation * math.pi / 180,
          alignment: Alignment.center,
          child: SizedBox(width: w, height: h, child: _buildContent(w, h)),
        ),
      );
    }

    const pad = 20.0; // room for handles to sit outside the element box

    return Positioned(
      left: element.x * scale - pad,
      top: element.y * scale - pad,
      child: SizedBox(
        width: w + pad * 2,
        height: h + pad * 2,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: pad,
              top: pad,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                onDoubleTap: groupMode ? null : onDoubleTap,
                onPanStart: dragDisabled ? null : (_) => onDragStart(),
                onPanEnd: dragDisabled
                    ? null
                    : (_) {
                        onSnapGuides(const []);
                        onDragEnd();
                      },
                onPanUpdate: dragDisabled
                    ? null
                    : (details) {
                        element.x += details.delta.dx / scale;
                        element.y += details.delta.dy / scale;
                        _applySnapping();
                        onChanged(element);
                      },
                child: Transform.rotate(
                  angle: element.rotation * math.pi / 180,
                  alignment: Alignment.center,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOut,
                    width: w,
                    height: h,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: selBorderColor.withValues(alpha: showSelBorder ? 1 : 0),
                        width: showSelBorder ? 2 : 0,
                      ),
                    ),
                    child: _buildContent(w, h),
                  ),
                ),
              ),
            ),
            if (groupMode && groupSelected)
              Positioned(
                left: 0,
                top: 0,
                child: IgnorePointer(
                  child: Container(
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: _groupHighlightColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.check, size: 13, color: Colors.white),
                  ),
                ),
              ),
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !selected,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 140),
                  opacity: selected ? 1 : 0,
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOutBack,
                    scale: selected ? 1 : 0.85,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: 0,
                          top: 0,
                          child: _handle(
                            color: const Color(0xFFE5484D),
                            icon: Icons.close,
                            onTap: onDelete,
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: _handle(
                            color: element.locked
                                ? const Color(0xFF9AA0A6)
                                : const Color(0xFF5F6368),
                            icon: element.locked ? Icons.lock : Icons.lock_open,
                            onTap: () {
                              element.locked = !element.locked;
                              onChanged(element);
                            },
                          ),
                        ),
                        if (!element.locked) ...[
                          // A stalk connecting the element's top edge to a
                          // free-floating rotate handle above it — the
                          // Canva/PowerPoint pattern, kept off the corners
                          // so all four corners are free for resizing.
                          Positioned(
                            left: (w + pad * 2) / 2 - 1,
                            top: 6,
                            child: Container(
                                width: 2, height: pad - 6, color: Colors.white70),
                          ),
                          Positioned(
                            left: (w + pad * 2) / 2 - 20,
                            top: -14,
                            child: GestureDetector(
                              onPanStart: (_) => onDragStart(),
                              onPanEnd: (_) => onDragEnd(),
                              onPanUpdate: (details) {
                                final box = context.findRenderObject() as RenderBox?;
                                if (box == null) return;
                                final centre =
                                    box.localToGlobal(Offset(w / 2 + pad, h / 2 + pad));
                                final angle = math.atan2(
                                  details.globalPosition.dy - centre.dy,
                                  details.globalPosition.dx - centre.dx,
                                );
                                var deg = (angle * 180 / math.pi) + 90;
                                // Snap to 15-degree steps when close — "perfectly
                                // straight" and "exactly 45" should be reachable
                                // with a thumb, not approximately reachable.
                                final nearest = ((deg / 15).round() * 15).toDouble();
                                if ((deg - nearest).abs() < 4) deg = nearest;
                                element.rotation = deg;
                                onChanged(element);
                              },
                              child: _handle(
                                  color: const Color(0xFF2FB344), icon: Icons.rotate_right),
                            ),
                          ),
                          // Both bottom corners resize now (top corners stay
                          // delete/lock), each anchored on its opposite top
                          // corner, with an aspect-lock toggle (see the
                          // nudge row) that keeps width/height in ratio from
                          // either handle.
                          Positioned(
                            left: 0,
                            bottom: 0,
                            child: GestureDetector(
                              onPanStart: (_) => onDragStart(),
                              onPanEnd: (_) => onDragEnd(),
                              onPanUpdate: (details) {
                                _applyResize(details.delta, isLeftEdge: true, isTopEdge: false);
                                onChanged(element);
                              },
                              child: _handle(
                                  color: appearance.primaryColor, icon: Icons.open_in_full),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: GestureDetector(
                              onPanStart: (_) => onDragStart(),
                              onPanEnd: (_) => onDragEnd(),
                              onPanUpdate: (details) {
                                _applyResize(details.delta, isLeftEdge: false, isTopEdge: false);
                                onChanged(element);
                              },
                              child: _handle(
                                  color: appearance.primaryColor, icon: Icons.open_in_full),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _handle({required Color color, required IconData icon, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        color: Colors.transparent,
        alignment: Alignment.center,
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
          ),
          child: Icon(icon, size: 14, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildContent(double w, double h) {
    switch (element.type) {
      case FlyerElementType.text:
        final displayText = element.text?.isNotEmpty == true
            ? element.text!
            : (exporting ? '' : 'Double-tap to edit');
        final baseStyle = TextStyle(
          fontSize: element.fontSize * scale,
          fontFamily: element.fontFamily,
          color: flyerHexToColor(element.color),
          fontWeight:
              element.fontWeight == 'bold' ? FontWeight.bold : FontWeight.normal,
          fontStyle: element.italic ? FontStyle.italic : FontStyle.normal,
          height: element.lineHeight,
          letterSpacing: element.letterSpacing * scale,
          decoration:
              element.underline ? TextDecoration.underline : TextDecoration.none,
          shadows: element.textShadow
              ? [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 6 * scale,
                    offset: Offset(0, 2 * scale),
                  ),
                ]
              : null,
        );
        final hasOutline = element.outlineColor != null && element.outlineWidth > 0;
        Widget textChild;
        if (element.curveAmount != 0 && displayText.isNotEmpty) {
          // Curved text (Canva-parity Phase B) -- each glyph placed along a
          // real circular arc via CustomPainter, same trig used server-side
          // by archText() in logoTemplates.js, ported to the live canvas.
          textChild = CustomPaint(
            size: Size(w, h),
            painter: CurvedTextPainter(
              text: displayText,
              style: baseStyle,
              curveAmount: element.curveAmount,
              outlineColor: hasOutline ? flyerHexToColor(element.outlineColor!) : null,
              outlineWidth: element.outlineWidth * scale,
            ),
          );
        } else if (hasOutline) {
          // Stroke-outline effect: paint a stroked copy of the text behind
          // the normal filled copy, both identically laid out via Stack.
          textChild = Stack(
            children: [
              Text(
                displayText,
                textAlign: _textAlignFor(element.textAlign),
                style: baseStyle.copyWith(
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = element.outlineWidth * scale
                    ..color = flyerHexToColor(element.outlineColor!),
                  shadows: null,
                ),
              ),
              Text(
                displayText,
                textAlign: _textAlignFor(element.textAlign),
                style: baseStyle,
              ),
            ],
          );
        } else {
          textChild = Text(
            displayText,
            textAlign: _textAlignFor(element.textAlign),
            style: baseStyle,
          );
        }
        return Opacity(
          opacity: element.opacity,
          child: Container(
            width: w,
            height: h,
            alignment: _boxAlignFor(element.textAlign),
            color: element.backgroundColor != null
                ? flyerHexToColor(element.backgroundColor!)
                : Colors.transparent,
            padding: const EdgeInsets.all(4),
            child: textChild,
          ),
        );
      case FlyerElementType.image:
      case FlyerElementType.logo:
      case FlyerElementType.qrcode:
        if (element.url == null || element.url!.isEmpty) {
          if (exporting) return const SizedBox.shrink();
          return Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(element.cornerRadius * scale),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  element.type == FlyerElementType.logo
                      ? Icons.workspace_premium
                      : element.type == FlyerElementType.qrcode
                          ? Icons.qr_code
                          : Icons.image,
                  color: Colors.grey,
                ),
                if (h > 64)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                        element.type == FlyerElementType.qrcode
                            ? 'Tap, then Edit QR data'
                            : 'Tap, then Replace',
                        style: const TextStyle(fontSize: 9, color: Colors.grey)),
                  ),
              ],
            ),
          );
        }
        final hasPhotoAdjustments = element.brightness != 0 || element.contrast != 0 || element.saturation != 1;
        Widget photo = Image.network(
          element.url!,
          width: w,
          height: h,
          fit: element.fit == 'contain' ? BoxFit.contain : BoxFit.cover,
          loadingBuilder: (ctx, child, progress) => progress == null
              ? child
              : Container(width: w, height: h, color: Colors.grey.shade100),
          errorBuilder: (_, __, ___) => Container(
            width: w,
            height: h,
            color: Colors.grey.shade200,
            child: const Icon(Icons.broken_image, color: Colors.grey),
          ),
        );
        if (hasPhotoAdjustments) {
          photo = ColorFiltered(
            colorFilter: ColorFilter.matrix(imageAdjustmentMatrix(
              brightness: element.brightness,
              contrast: element.contrast,
              saturation: element.saturation,
            )),
            child: photo,
          );
        }
        // Frames (Canva-parity Phase D) -- an image/logo can mask into a
        // shape via shapeKind, the same field the 'shape' element type
        // already uses (reuse, not a new field). Deliberately excluded
        // for qrcode: masking away the quiet-zone/corners of a QR code
        // can make it unscannable, so it always stays a plain rounded
        // rect regardless of shapeKind.
        final frameKind =
            element.type != FlyerElementType.qrcode ? element.shapeKind : 'rect';
        return Opacity(
          opacity: element.opacity,
          child: frameKind == 'rect'
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(element.cornerRadius * scale),
                  child: photo,
                )
              : ClipPath(
                  clipper: FramePathClipper(kind: frameKind),
                  child: photo,
                ),
        );
      case FlyerElementType.shape:
        if (const {'triangle', 'line', 'arrow', 'star'}.contains(element.shapeKind)) {
          return Opacity(
            opacity: element.opacity,
            child: CustomPaint(
              size: Size(w, h),
              painter: FlyerShapePainter(
                kind: element.shapeKind,
                fillColor: flyerHexToColor(element.shapeColor),
                fillColorEnd: element.shapeGradientEnd != null
                    ? flyerHexToColor(element.shapeGradientEnd!)
                    : null,
                strokeColor:
                    element.strokeColor != null ? flyerHexToColor(element.strokeColor!) : null,
                strokeWidth: element.strokeWidth * scale,
              ),
            ),
          );
        }
        return Opacity(
          opacity: element.opacity,
          child: Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
              color: element.shapeGradientEnd == null ? flyerHexToColor(element.shapeColor) : null,
              gradient: element.shapeGradientEnd != null
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        flyerHexToColor(element.shapeColor),
                        flyerHexToColor(element.shapeGradientEnd!),
                      ],
                    )
                  : null,
              shape:
                  element.shapeKind == 'circle' ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: element.shapeKind == 'circle'
                  ? null
                  : BorderRadius.circular(element.cornerRadius * scale),
              border: (element.strokeColor != null && element.strokeWidth > 0)
                  ? Border.all(
                      color: flyerHexToColor(element.strokeColor!),
                      width: element.strokeWidth * scale,
                    )
                  : null,
            ),
          ),
        );
      case FlyerElementType.icon:
        return Opacity(
          opacity: element.opacity,
          child: Center(
            child: Icon(
              kFlyerIconLibrary[element.iconKey] ?? Icons.star,
              size: (w < h ? w : h) * 0.82,
              color: flyerHexToColor(element.shapeColor),
            ),
          ),
        );
      case FlyerElementType.svg:
        if (element.svgData == null || element.svgData!.isEmpty) {
          if (exporting) return const SizedBox.shrink();
          return Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(Icons.polyline, color: Colors.grey),
          );
        }
        return Opacity(
          opacity: element.opacity,
          child: SvgPicture.string(
            element.svgData!,
            width: w,
            height: h,
            fit: BoxFit.contain,
            colorFilter: element.svgRecolor
                ? ColorFilter.mode(flyerHexToColor(element.shapeColor), BlendMode.srcIn)
                : null,
            placeholderBuilder: (_) => SizedBox(width: w, height: h),
            errorBuilder: (_, __, ___) => Container(
              width: w,
              height: h,
              color: Colors.grey.shade200,
              child: const Icon(Icons.broken_image, color: Colors.grey),
            ),
          ),
        );
      case FlyerElementType.chart:
        return Opacity(
          opacity: element.opacity,
          child: CustomPaint(
            size: Size(w, h),
            painter: ChartPainter(
              kind: element.chartKind,
              labels: element.chartLabels,
              values: element.chartValues,
              seriesColor: flyerHexToColor(element.shapeColor),
            ),
          ),
        );
      case FlyerElementType.drawing:
        return Opacity(
          opacity: element.opacity,
          child: CustomPaint(
            size: Size(w, h),
            painter: DrawingPainter(
              points: element.drawingPoints,
              color: flyerHexToColor(element.shapeColor),
              strokeWidth: (element.strokeWidth > 0 ? element.strokeWidth : 4) * scale,
            ),
          ),
        );
    }
  }

  Alignment _boxAlignFor(String a) {
    switch (a) {
      case 'center':
        return Alignment.center;
      case 'right':
        return Alignment.centerRight;
      default:
        return Alignment.centerLeft;
    }
  }

  TextAlign _textAlignFor(String a) {
    switch (a) {
      case 'center':
        return TextAlign.center;
      case 'right':
        return TextAlign.right;
      default:
        return TextAlign.left;
    }
  }
}

/// Curved text (Canva-parity Phase B). Places each character along a real
/// circular arc computed from a chord/sagitta relationship: the arc always
/// spans exactly the element's width, and how far it bulges is driven by
/// [curveAmount] (-100..100; 0 is handled by the caller before reaching
/// here, positive bulges the text upward like a rainbow, negative bulges it
/// downward). Same character-placement trig as the server-side archText()
/// in backend/services/logoTemplates.js, ported to a live, editable canvas.
class CurvedTextPainter extends CustomPainter {
  final String text;
  final TextStyle style;
  final double curveAmount;
  final Color? outlineColor;
  final double outlineWidth;

  CurvedTextPainter({
    required this.text,
    required this.style,
    required this.curveAmount,
    this.outlineColor,
    this.outlineWidth = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final chars = text.split('');
    if (chars.isEmpty || size.width <= 0 || size.height <= 0) return;

    final bulgeUp = curveAmount >= 0;
    final maxSagitta = size.height * 0.5;
    final sagitta = (curveAmount.abs() / 100).clamp(0.0, 1.0) * maxSagitta;
    final halfChord = size.width / 2;
    final cx = size.width / 2;
    final centerY = size.height / 2;

    // Degenerate case (sagitta ~0, e.g. a near-flat element): fall back to
    // a straight baseline rather than dividing by ~0 in the radius formula.
    if (sagitta < 0.5) {
      _paintStraightFallback(canvas, size);
      return;
    }

    final radius = (halfChord * halfChord + sagitta * sagitta) / (2 * sagitta);
    final halfSpanRad = math.asin((halfChord / radius).clamp(-1.0, 1.0));
    final cyCenter =
        bulgeUp ? centerY - sagitta / 2 + radius : centerY + sagitta / 2 - radius;

    // Measure each character's width up front so characters are spaced by
    // actual glyph advance, not a uniform guess.
    final painters = chars
        .map((ch) => TextPainter(
              text: TextSpan(text: ch, style: style),
              textDirection: TextDirection.ltr,
            )..layout())
        .toList();
    final totalWidth = painters.fold<double>(0, (sum, p) => sum + p.width);
    if (totalWidth <= 0) return;

    var traveled = 0.0;
    for (var i = 0; i < chars.length; i++) {
      final p = painters[i];
      // Character's centre, as a fraction of total advance, mapped onto the
      // arc's angular span.
      final midFraction = (traveled + p.width / 2) / totalWidth;
      traveled += p.width;
      final rad = -halfSpanRad + (2 * halfSpanRad) * midFraction;

      final x = cx + radius * math.sin(rad);
      final y = bulgeUp
          ? cyCenter - radius * math.cos(rad)
          : cyCenter + radius * math.cos(rad);
      final rotation = bulgeUp ? rad : -rad;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);
      final glyphOffset = Offset(-p.width / 2, -p.height / 2);
      if (outlineColor != null && outlineWidth > 0) {
        final strokePainter = TextPainter(
          text: TextSpan(
            text: chars[i],
            style: style.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = outlineWidth
                ..color = outlineColor!,
              shadows: null,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        strokePainter.paint(canvas, glyphOffset);
      }
      p.paint(canvas, glyphOffset);
      canvas.restore();
    }
  }

  void _paintStraightFallback(Canvas canvas, Size size) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);
    tp.paint(canvas, Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));
  }

  @override
  bool shouldRepaint(covariant CurvedTextPainter oldDelegate) {
    return oldDelegate.text != text ||
        oldDelegate.style != style ||
        oldDelegate.curveAmount != curveAmount ||
        oldDelegate.outlineColor != outlineColor ||
        oldDelegate.outlineWidth != outlineWidth;
  }
}

/// Charts (Canva-parity Phase F) -- a small element type that turns a
/// {labels, values} data table the user typed in into a real bar/line/pie
/// chart, no charting package needed for these 3 basic kinds. All three
/// modes guard the same degenerate cases: an empty/all-zero value set
/// renders flat bars/a flat line rather than dividing by zero, and a
/// single-value pie renders one full circle rather than nothing.
class ChartPainter extends CustomPainter {
  final String kind;
  final List<String> labels;
  final List<double> values;
  final Color seriesColor;

  ChartPainter({
    required this.kind,
    required this.labels,
    required this.values,
    required this.seriesColor,
  });

  static const List<Color> _pieColors = [
    Color(0xFF1B2A4A),
    Color(0xFF2563EB),
    Color(0xFF0EA5E9),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.width <= 0 || size.height <= 0) return;
    switch (kind) {
      case 'line':
        _paintLine(canvas, size);
        break;
      case 'pie':
        _paintPie(canvas, size);
        break;
      case 'bar':
      default:
        _paintBar(canvas, size);
    }
  }

  bool get _hasLabels => labels.any((l) => l.trim().isNotEmpty);

  void _drawLabel(Canvas canvas, String text, Offset topLeft, double maxWidth) {
    if (text.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(fontSize: 10, color: Colors.black87)),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, Offset(topLeft.dx + (maxWidth - tp.width) / 2, topLeft.dy));
  }

  void _paintBar(Canvas canvas, Size size) {
    final labelSpace = _hasLabels ? 16.0 : 0.0;
    final chartH = size.height - labelSpace;
    if (chartH <= 0) return;
    final maxV = values.fold<double>(0, (m, v) => math.max(m, v));
    final n = values.length;
    final slotW = size.width / n;
    final barW = slotW * 0.6;
    final paint = Paint()..color = seriesColor;
    for (var i = 0; i < n; i++) {
      final barH = maxV > 0 ? (values[i] / maxV) * chartH : 0.0;
      final left = i * slotW + (slotW - barW) / 2;
      final rect = Rect.fromLTWH(left, chartH - barH, barW, barH);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)), paint);
      if (labelSpace > 0 && i < labels.length) {
        _drawLabel(canvas, labels[i], Offset(i * slotW, chartH + 2), slotW);
      }
    }
  }

  void _paintLine(Canvas canvas, Size size) {
    final labelSpace = _hasLabels ? 16.0 : 0.0;
    final chartH = size.height - labelSpace;
    if (chartH <= 0) return;
    final n = values.length;
    final maxV = values.fold<double>(values.first, (m, v) => math.max(m, v));
    final minV = values.fold<double>(values.first, (m, v) => math.min(m, v));
    final range = maxV - minV;
    final stepX = n > 1 ? size.width / (n - 1) : 0.0;

    final points = <Offset>[];
    for (var i = 0; i < n; i++) {
      // A flat series (range == 0) draws a horizontal line through the
      // middle rather than dividing by zero.
      final norm = range > 0 ? (values[i] - minV) / range : 0.5;
      final x = n > 1 ? i * stepX : size.width / 2;
      final y = chartH - norm * chartH;
      points.add(Offset(x, y));
    }

    final linePaint = Paint()
      ..color = seriesColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()..color = seriesColor;
    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(points[i], 3.5, dotPaint);
      if (labelSpace > 0 && i < labels.length) {
        final labelW = n > 1 ? stepX : size.width;
        _drawLabel(canvas, labels[i], Offset(points[i].dx - labelW / 2, chartH + 2), labelW);
      }
    }
  }

  void _paintPie(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (a, b) => a + b);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 * 0.85;
    final rect = Rect.fromCircle(center: center, radius: radius);
    if (total <= 0) {
      // No data yet to proportion slices from -- an empty ring reads as
      // "nothing entered" rather than a misleading full-colour disc.
      final paint = Paint()
        ..color = Colors.grey.shade300
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawCircle(center, radius, paint);
      return;
    }
    var startAngle = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = (values[i] / total) * 2 * math.pi;
      final paint = Paint()..color = _pieColors[i % _pieColors.length];
      canvas.drawArc(rect, startAngle, sweep, true, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant ChartPainter oldDelegate) {
    return oldDelegate.kind != kind ||
        oldDelegate.seriesColor != seriesColor ||
        !_listEquals(oldDelegate.labels, labels) ||
        !_listEquals(oldDelegate.values, values);
  }

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Freehand drawing (Canva-parity Phase E). [points] are fractional
/// (0.0..1.0 of the element's own width/height, see FlyerElement.
/// drawingPoints) so the stroke redraws correctly at whatever size the
/// element widget is currently laid out at -- while actively drawing
/// (DrawCaptureOverlay below) and after a resize alike, the same painter
/// runs, just fed a different [size].
class DrawingPainter extends CustomPainter {
  final List<List<double>> points;
  final Color color;
  final double strokeWidth;

  DrawingPainter({required this.points, required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(points.first[0] * size.width, points.first[1] * size.height);
    for (final p in points.skip(1)) {
      path.lineTo(p[0] * size.width, p[1] * size.height);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant DrawingPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.points.length != points.length;
  }
}

/// The in-progress stroke preview while actively drawing (before pan-end
/// turns it into a real FlyerElement) -- raw screen-space points, unlike
/// DrawingPainter's fractional element-local ones above, since this
/// paints directly over the live canvas view at a fixed size for the
/// duration of one gesture.
class LiveStrokePainter extends CustomPainter {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;

  LiveStrokePainter({required this.points, required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant LiveStrokePainter oldDelegate) => true;
}
