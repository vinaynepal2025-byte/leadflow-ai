// FlyerCanvasElementWidget — the reusable drag/resize/rotate interaction
// wrapper. Works identically for text, image, logo, and shape elements —
// the element's `type` only decides what renders *inside* the wrapper, not
// how it's manipulated. This is the "no-limitations freeform canvas" core:
// any element can go anywhere, any size, any angle.
//
// Coordinate model: the parent (FlyerStudioScreen) renders the canvas at a
// fixed on-screen pixel size and passes down `scale` (screenPx / canvasPx).
// This widget receives element.x/y/width/height in CANVAS units and
// multiplies by `scale` for on-screen layout, and divides drag deltas by
// `scale` when writing back — so canvas coordinates always stay resolution
// independent of the phone's actual screen size.

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

class FlyerCanvasElementWidget extends StatelessWidget {
  final FlyerElement element;
  final double scale;
  final bool selected;
  final VoidCallback onTap;
  final ElementChanged onChanged;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final VoidCallback onDelete;

  const FlyerCanvasElementWidget({
    super.key,
    required this.element,
    required this.scale,
    required this.selected,
    required this.onTap,
    required this.onChanged,
    required this.onDragStart,
    required this.onDragEnd,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final left = element.x * scale;
    final top = element.y * scale;
    final w = math.max(element.width * scale, 8.0);
    final h = math.max(element.height * scale, 8.0);

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onPanStart: (_) => onDragStart(),
        onPanEnd: (_) => onDragEnd(),
        onPanUpdate: (details) {
          element.x += details.delta.dx / scale;
          element.y += details.delta.dy / scale;
          onChanged(element);
        },
        child: Transform.rotate(
          angle: element.rotation * math.pi / 180,
          alignment: Alignment.center,
          child: SizedBox(
            width: w + 24,
            height: h + 40,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 12,
                  top: 12,
                  child: Container(
                    width: w,
                    height: h,
                    decoration: selected
                        ? BoxDecoration(
                            border: Border.all(color: const Color(0xFF4C6FFF), width: 2),
                          )
                        : null,
                    child: _buildContent(w, h),
                  ),
                ),
                if (selected) ...[
                  // Delete handle — top-left
                  Positioned(
                    left: 0,
                    top: 0,
                    child: _handle(
                      color: const Color(0xFFE5484D),
                      icon: Icons.close,
                      onTap: onDelete,
                    ),
                  ),
                  // Rotate handle — top-right
                  Positioned(
                    right: 0,
                    top: 0,
                    child: GestureDetector(
                      onPanStart: (_) => onDragStart(),
                      onPanEnd: (_) => onDragEnd(),
                      onPanUpdate: (details) {
                        final box = context.findRenderObject() as RenderBox?;
                        if (box == null) return;
                        final center = box.localToGlobal(
                          Offset(w / 2 + 12, h / 2 + 12),
                        );
                        final angle = math.atan2(
                          details.globalPosition.dy - center.dy,
                          details.globalPosition.dx - center.dx,
                        );
                        element.rotation = (angle * 180 / math.pi) + 90;
                        onChanged(element);
                      },
                      child: _handle(color: const Color(0xFF2FB344), icon: Icons.rotate_right),
                    ),
                  ),
                  // Resize handle — bottom-right
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onPanStart: (_) => onDragStart(),
                      onPanEnd: (_) => onDragEnd(),
                      onPanUpdate: (details) {
                        element.width =
                            (element.width + details.delta.dx / scale).clamp(20.0, 5000.0);
                        element.height =
                            (element.height + details.delta.dy / scale).clamp(20.0, 5000.0);
                        onChanged(element);
                      },
                      child: _handle(color: const Color(0xFF4C6FFF), icon: Icons.open_in_full),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _handle({required Color color, required IconData icon, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
        ),
        child: Icon(icon, size: 13, color: Colors.white),
      ),
    );
  }

  Widget _buildContent(double w, double h) {
    switch (element.type) {
      case FlyerElementType.text:
        return Container(
          width: w,
          height: h,
          alignment: _boxAlignFor(element.textAlign),
          color: element.backgroundColor != null
              ? flyerHexToColor(element.backgroundColor!)
              : Colors.transparent,
          padding: const EdgeInsets.all(4),
          child: Text(
            element.text?.isNotEmpty == true ? element.text! : 'Double-tap to edit',
            textAlign: _textAlignFor(element.textAlign),
            style: TextStyle(
              fontSize: element.fontSize * scale,
              fontFamily: element.fontFamily,
              color: flyerHexToColor(element.color),
              fontWeight: element.fontWeight == 'bold' ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        );
      case FlyerElementType.image:
      case FlyerElementType.logo:
        if (element.url == null || element.url!.isEmpty) {
          return Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              color: Colors.grey.shade200,
            ),
            child: Icon(
              element.type == FlyerElementType.logo ? Icons.workspace_premium : Icons.image,
              color: Colors.grey,
            ),
          );
        }
        return Opacity(
          opacity: element.opacity,
          child: Image.network(
            element.url!,
            width: w,
            height: h,
            fit: element.fit == 'contain' ? BoxFit.contain : BoxFit.cover,
            loadingBuilder: (ctx, child, progress) =>
                progress == null ? child : Container(width: w, height: h, color: Colors.grey.shade100),
            errorBuilder: (_, __, ___) => Container(
              width: w,
              height: h,
              color: Colors.grey.shade200,
              child: const Icon(Icons.broken_image, color: Colors.grey),
            ),
          ),
        );
      case FlyerElementType.shape:
        return Opacity(
          opacity: element.opacity,
          child: Container(width: w, height: h, color: flyerHexToColor(element.shapeColor)),
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
