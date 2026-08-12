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
import 'flyer_element.dart';

typedef ElementChanged = void Function(FlyerElement element);

Color flyerHexToColor(String hex, {double opacity = 1.0}) {
  var h = hex.replaceAll('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return Colors.black.withOpacity(opacity);
  final value = int.tryParse(h, radix: 16);
  if (value == null) return Colors.black.withOpacity(opacity);
  return Color(value).withOpacity(opacity);
}

String flyerColorToHex(Color c) =>
    '#${c.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

/// A single alignment guide line shown while dragging.
class FlyerSnapGuide {
  final bool vertical;
  final double position; // canvas units

  const FlyerSnapGuide({required this.vertical, required this.position});
}

/// Paints active snap guides over the canvas.
class FlyerSnapGuidePainter extends CustomPainter {
  final List<FlyerSnapGuide> guides;
  final double scale;

  FlyerSnapGuidePainter({required this.guides, required this.scale});

  @override
  void paint(Canvas canvas, Size size) {
    if (guides.isEmpty) return;
    final paint = Paint()
      ..color = const Color(0xFFE5484D)
      ..strokeWidth = 1;
    for (final g in guides) {
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
  });

  static const double _snapThreshold = 18; // canvas units

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

    onSnapGuides(guides);
  }

  @override
  Widget build(BuildContext context) {
    final w = math.max(element.width * scale, 6.0);
    final h = math.max(element.height * scale, 6.0);

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
                onDoubleTap: onDoubleTap,
                onPanStart: element.locked ? null : (_) => onDragStart(),
                onPanEnd: element.locked
                    ? null
                    : (_) {
                        onSnapGuides(const []);
                        onDragEnd();
                      },
                onPanUpdate: element.locked
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
                  child: Container(
                    width: w,
                    height: h,
                    decoration: selected
                        ? BoxDecoration(
                            border: Border.all(
                              color: element.locked
                                  ? const Color(0xFF9AA0A6)
                                  : const Color(0xFF4C6FFF),
                              width: 2,
                            ),
                          )
                        : null,
                    child: _buildContent(w, h),
                  ),
                ),
              ),
            ),
            if (selected) ...[
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
                left: (w + pad * 2) / 2 - 20,
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
                Positioned(
                  right: 0,
                  top: 0,
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
                      // straight" and "exactly 45" should be reachable with
                      // a thumb, not approximately reachable.
                      final nearest = ((deg / 15).round() * 15).toDouble();
                      if ((deg - nearest).abs() < 4) deg = nearest;
                      element.rotation = deg;
                      onChanged(element);
                    },
                    child: _handle(
                        color: const Color(0xFF2FB344), icon: Icons.rotate_right),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onPanStart: (_) => onDragStart(),
                    onPanEnd: (_) => onDragEnd(),
                    onPanUpdate: (details) {
                      element.width = (element.width + details.delta.dx / scale)
                          .clamp(20.0, 8000.0);
                      element.height = (element.height + details.delta.dy / scale)
                          .clamp(20.0, 8000.0);
                      onChanged(element);
                    },
                    child: _handle(
                        color: const Color(0xFF4C6FFF), icon: Icons.open_in_full),
                  ),
                ),
              ],
            ],
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
            child: Text(
              element.text?.isNotEmpty == true
                  ? element.text!
                  : (exporting ? '' : 'Double-tap to edit'),
              textAlign: _textAlignFor(element.textAlign),
              style: TextStyle(
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
              ),
            ),
          ),
        );
      case FlyerElementType.image:
      case FlyerElementType.logo:
        if (element.url == null || element.url!.isEmpty) {
          if (exporting) return const SizedBox.shrink();
          return Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              color: Colors.grey.shade200,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  element.type == FlyerElementType.logo
                      ? Icons.workspace_premium
                      : Icons.image,
                  color: Colors.grey,
                ),
                if (h > 64)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('Tap, then Replace',
                        style: TextStyle(fontSize: 9, color: Colors.grey)),
                  ),
              ],
            ),
          );
        }
        return Opacity(
          opacity: element.opacity,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(element.cornerRadius * scale),
            child: Image.network(
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
            ),
          ),
        );
      case FlyerElementType.shape:
        return Opacity(
          opacity: element.opacity,
          child: Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
              color: flyerHexToColor(element.shapeColor),
              shape:
                  element.shapeKind == 'circle' ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: element.shapeKind == 'circle'
                  ? null
                  : BorderRadius.circular(element.cornerRadius * scale),
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
