// FlyerElement — the core data model for Flyer Studio v2's freeform canvas.
// Every visual thing on a flyer (text, image, logo, colored shape) is one of
// these. This mirrors the backend's `canvas_json` array shape exactly
// (flyerProjects.js), so toJson()/fromJson() round-trip cleanly through
// PATCH /flyer-projects/:id with zero server-side transformation needed.
//
// New fields are always written with a safe default in fromJson, so a
// project saved by an older build of the app still opens correctly in a
// newer one — canvas_json is schemaless JSONB on the server precisely so
// this stays true as the editor gains features.

import 'package:flutter/material.dart' show IconData, Icons;

enum FlyerElementType { text, image, logo, shape, icon, svg, qrcode, chart, drawing }

FlyerElementType flyerElementTypeFromString(String? s) {
  switch (s) {
    case 'image':
      return FlyerElementType.image;
    case 'logo':
      return FlyerElementType.logo;
    case 'shape':
      return FlyerElementType.shape;
    case 'icon':
      return FlyerElementType.icon;
    case 'svg':
      return FlyerElementType.svg;
    case 'qrcode':
      return FlyerElementType.qrcode;
    case 'chart':
      return FlyerElementType.chart;
    case 'drawing':
      return FlyerElementType.drawing;
    case 'text':
    default:
      return FlyerElementType.text;
  }
}

String flyerElementTypeToString(FlyerElementType t) {
  switch (t) {
    case FlyerElementType.image:
      return 'image';
    case FlyerElementType.logo:
      return 'logo';
    case FlyerElementType.shape:
      return 'shape';
    case FlyerElementType.icon:
      return 'icon';
    case FlyerElementType.svg:
      return 'svg';
    case FlyerElementType.qrcode:
      return 'qrcode';
    case FlyerElementType.chart:
      return 'chart';
    case FlyerElementType.drawing:
      return 'drawing';
    case FlyerElementType.text:
      return 'text';
  }
}

// The bundled font list itself lives in flyer_fonts.dart (kFlyerFontOptions
// / kFlyerFontFamilies) — it also needs to know each font's server-side
// registered name for GenerateLogoScreen's template pipeline, which
// doesn't belong in this file's plain element-model concerns.

/// Shape kinds available on the Shape tool. 'rect' and 'circle' render via
/// a plain BoxDecoration (cheap, and cornerRadius applies); everything
/// else is a hand-drawn Path in FlyerShapePainter, where cornerRadius has
/// no meaning.
const Map<String, String> kFlyerShapeKindLabels = {
  'rect': 'Rectangle',
  'circle': 'Circle',
  'triangle': 'Triangle',
  'line': 'Line',
  'arrow': 'Arrow',
  'star': 'Star',
};

// A proper icon library -- "different shapes, different styles" was the
// direct ask, and 6 hand-drawn Path shapes is a narrow answer next to a
// real icon set. String-key-to-IconData, same pattern as every other
// curated icon picker in this app (kMoreMenuIconOptions etc.), so a
// FlyerElement only ever stores a stable string key, never a raw
// codepoint/fontFamily pair. Grouped loosely by theme for the picker UI;
// the grouping itself isn't persisted anywhere.
const Map<String, IconData> kFlyerIconLibrary = {
  // Education & consultancy
  'school': Icons.school,
  'menu_book': Icons.menu_book,
  'local_library': Icons.local_library,
  'science': Icons.science,
  'calculate': Icons.calculate,
  'psychology': Icons.psychology,
  'workspace_premium': Icons.workspace_premium,
  'emoji_events': Icons.emoji_events,
  'card_membership': Icons.card_membership,
  'verified': Icons.verified,
  'verified_user': Icons.verified_user,
  // Travel & global
  'public': Icons.public,
  'flight_takeoff': Icons.flight_takeoff,
  'language': Icons.language,
  'explore': Icons.explore,
  'location_on': Icons.location_on,
  // Business & growth
  'business_center': Icons.business_center,
  'trending_up': Icons.trending_up,
  'insights': Icons.insights,
  'handshake': Icons.handshake,
  'groups': Icons.groups,
  'diversity_3': Icons.diversity_3,
  'rocket_launch': Icons.rocket_launch,
  'lightbulb': Icons.lightbulb,
  // Communication
  'chat_bubble': Icons.chat_bubble,
  'campaign': Icons.campaign,
  'notifications': Icons.notifications,
  'mail': Icons.mail,
  'call': Icons.call,
  // Tech
  'computer': Icons.computer,
  'auto_awesome': Icons.auto_awesome,
  'bolt': Icons.bolt,
  'shield': Icons.shield,
  // Symbols & shapes
  'star_rounded': Icons.star_rounded,
  'favorite': Icons.favorite,
  'diamond': Icons.diamond,
  'celebration': Icons.celebration,
  'flag': Icons.flag,
  'circle': Icons.circle,
  'hexagon': Icons.hexagon,
  'square': Icons.square,
  'change_history': Icons.change_history,
  'arrow_circle_right': Icons.arrow_circle_right,
  'check_circle': Icons.check_circle,
  'favorite_border': Icons.favorite_border,
  'add_circle': Icons.add_circle,
  'sunny': Icons.sunny,
  'eco': Icons.eco,
  'palette': Icons.palette,
  'brush': Icons.brush,
};

/// Canvas size presets. A flyer that's going to Instagram Stories has very
/// different proportions from one going to WhatsApp or a printed A4 poster,
/// and getting that wrong means the design is cropped or letterboxed at the
/// worst possible moment — right when it's being sent to a lead.
class FlyerCanvasPreset {
  final String id;
  final String name;
  final String note;
  final double width;
  final double height;

  const FlyerCanvasPreset({
    required this.id,
    required this.name,
    required this.note,
    required this.width,
    required this.height,
  });
}

const List<FlyerCanvasPreset> kFlyerCanvasPresets = [
  FlyerCanvasPreset(
      id: 'portrait',
      name: 'Flyer / Post (4:5)',
      note: 'Best all-round for WhatsApp & Instagram feed',
      width: 1080,
      height: 1350),
  FlyerCanvasPreset(
      id: 'square',
      name: 'Square (1:1)',
      note: 'Instagram & Facebook feed',
      width: 1080,
      height: 1080),
  FlyerCanvasPreset(
      id: 'story',
      name: 'Story / Reel (9:16)',
      note: 'Instagram & WhatsApp status',
      width: 1080,
      height: 1920),
  FlyerCanvasPreset(
      id: 'landscape',
      name: 'Landscape (16:9)',
      note: 'Facebook link posts, presentations',
      width: 1200,
      height: 675),
  FlyerCanvasPreset(
      id: 'a4',
      name: 'A4 Poster (print)',
      note: 'For printing and PDF handouts',
      width: 2480,
      height: 3508),
];

class FlyerElement {
  String id;
  FlyerElementType type;
  double x;
  double y;
  double width;
  double height;
  double rotation; // degrees
  int zIndex;
  bool locked;
  double opacity;
  bool aspectLocked;

  // Text-specific
  String? text;
  double fontSize;
  String fontFamily;
  String color; // hex "#RRGGBB"
  String fontWeight; // 'normal' | 'bold'
  bool italic;
  bool underline;
  String textAlign; // 'left' | 'center' | 'right'
  String? backgroundColor; // hex or null (transparent)
  double lineHeight;
  double letterSpacing;
  bool textShadow;
  // Text effects (Canva-parity Phase B). outlineWidth 0 / curveAmount 0 both
  // mean "no effect", so existing text elements render and serialize
  // identically to before these fields existed.
  String? outlineColor; // hex or null (no stroke outline)
  double outlineWidth; // 0..12, logical px before scale
  double curveAmount; // -100..100; 0 = straight, + arcs up, - arcs down

  // Image / logo-specific
  String? url;
  String fit; // 'cover' | 'contain'
  double cornerRadius;
  // Photo adjustments (Canva-parity Phase C) -- 0 means "no change" for
  // all three, so an element with no adjustments applied renders and
  // serializes identically to before these fields existed.
  double brightness; // -100..100
  double contrast; // -100..100
  double saturation; // 0 (greyscale) .. 2 (double), 1 = no change

  // Shape-specific
  String shapeColor;
  String shapeKind; // 'rect' | 'circle'
  String? shapeGradientEnd; // hex or null (flat fill)
  String? strokeColor; // hex or null (no stroke)
  double strokeWidth;

  // Chart-specific (Canva-parity Phase F). Reuses shapeColor as the
  // primary series colour (bar/line) -- same reuse reasoning as icons
  // below -- so the existing colour picker/AI Quick Restyle machinery
  // works on a chart's colour for free. Pie mode ignores shapeColor in
  // favour of a small fixed high-contrast palette, since a single colour
  // can't distinguish slices.
  String chartKind; // 'bar' | 'line' | 'pie'
  List<String> chartLabels;
  List<double> chartValues;

  // Drawing-specific (Canva-parity Phase E). Points are stored as
  // FRACTIONAL coordinates -- each [x, y] pair in 0.0..1.0 of the
  // element's own width/height -- rather than absolute pixels, so
  // dragging this element's resize handles scales the stroke correctly
  // for free (the painter just multiplies by the current size.width/
  // size.height every repaint) instead of needing a separate
  // re-normalization step on every resize. Reuses shapeColor (pen
  // colour) and strokeWidth (pen thickness), same reuse reasoning as
  // icons/SVG/chart above.
  List<List<double>> drawingPoints;

  // Icon-specific -- deliberately reuses shapeColor for fill rather than
  // adding a separate colour field: an icon is conceptually a special
  // shape (single-colour glyph), and every colour-editing control the
  // style panel already has for shapes (picker, AI Quick Restyle-style
  // apply) works on it for free this way.
  String iconKey; // key into kFlyerIconLibrary

  // SVG-specific. svgData holds the sanitized SVG markup itself (already
  // run through svg_sanitizer.dart before an element is ever created), not
  // a URL -- this is what keeps an imported SVG a true vector object that
  // stays editable (recolourable, re-exportable as SVG) through save/
  // reopen, rather than a bitmap. svgRecolor reuses shapeColor (same
  // reasoning as icons above) to force the whole graphic to one flat
  // colour via a ColorFilter, for monochrome/icon-style source SVGs;
  // multi-colour source SVGs should leave it off and render as authored.
  String? svgData;
  bool svgRecolor;

  FlyerElement({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    this.width = 200,
    this.height = 100,
    this.rotation = 0,
    this.zIndex = 0,
    this.locked = false,
    this.opacity = 1.0,
    this.aspectLocked = false,
    this.text,
    this.fontSize = 24,
    this.fontFamily = 'Roboto',
    this.color = '#000000',
    this.fontWeight = 'normal',
    this.italic = false,
    this.underline = false,
    this.textAlign = 'left',
    this.backgroundColor,
    this.lineHeight = 1.2,
    this.letterSpacing = 0,
    this.textShadow = false,
    this.outlineColor,
    this.outlineWidth = 0,
    this.curveAmount = 0,
    this.url,
    this.fit = 'cover',
    this.cornerRadius = 0,
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 1,
    this.shapeColor = '#CCCCCC',
    this.shapeKind = 'rect',
    this.shapeGradientEnd,
    this.strokeColor,
    this.strokeWidth = 0,
    this.chartKind = 'bar',
    List<String>? chartLabels,
    List<double>? chartValues,
    this.drawingPoints = const [],
    this.iconKey = 'star',
    this.svgData,
    this.svgRecolor = false,
  })  : chartLabels = chartLabels ?? const ['A', 'B', 'C'],
        chartValues = chartValues ?? const [30, 60, 45];

  factory FlyerElement.fromJson(Map<String, dynamic> json) {
    return FlyerElement(
      id: json['id']?.toString() ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      type: flyerElementTypeFromString(json['type']?.toString()),
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      width: (json['width'] as num?)?.toDouble() ?? 200,
      height: (json['height'] as num?)?.toDouble() ?? 100,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
      zIndex: (json['zIndex'] as num?)?.toInt() ?? 0,
      locked: json['locked'] == true,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      aspectLocked: json['aspectLocked'] == true,
      text: json['text']?.toString(),
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 24,
      fontFamily: json['fontFamily']?.toString() ?? 'Roboto',
      color: json['color']?.toString() ?? '#000000',
      fontWeight: json['fontWeight']?.toString() ?? 'normal',
      italic: json['italic'] == true,
      underline: json['underline'] == true,
      textAlign: json['textAlign']?.toString() ?? 'left',
      backgroundColor: json['backgroundColor']?.toString(),
      lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.2,
      letterSpacing: (json['letterSpacing'] as num?)?.toDouble() ?? 0,
      textShadow: json['textShadow'] == true,
      outlineColor: json['outlineColor']?.toString(),
      outlineWidth: (json['outlineWidth'] as num?)?.toDouble() ?? 0,
      curveAmount: (json['curveAmount'] as num?)?.toDouble() ?? 0,
      url: json['url']?.toString(),
      fit: json['fit']?.toString() ?? 'cover',
      cornerRadius: (json['cornerRadius'] as num?)?.toDouble() ?? 0,
      brightness: (json['brightness'] as num?)?.toDouble() ?? 0,
      contrast: (json['contrast'] as num?)?.toDouble() ?? 0,
      saturation: (json['saturation'] as num?)?.toDouble() ?? 1,
      shapeColor: json['shapeColor']?.toString() ?? '#CCCCCC',
      shapeKind: json['shapeKind']?.toString() ?? 'rect',
      shapeGradientEnd: json['shapeGradientEnd']?.toString(),
      strokeColor: json['strokeColor']?.toString(),
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 0,
      chartKind: json['chartKind']?.toString() ?? 'bar',
      chartLabels: (json['chartLabels'] as List?)?.map((e) => e.toString()).toList(),
      chartValues: (json['chartValues'] as List?)?.map((e) => (e as num).toDouble()).toList(),
      drawingPoints: (json['drawingPoints'] as List?)
              ?.map((p) => (p as List).map((n) => (n as num).toDouble()).toList())
              .toList() ??
          const [],
      iconKey: json['iconKey']?.toString() ?? 'star',
      svgData: json['svgData']?.toString(),
      svgRecolor: json['svgRecolor'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'id': id,
      'type': flyerElementTypeToString(type),
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'rotation': rotation,
      'zIndex': zIndex,
      'locked': locked,
      'opacity': opacity,
      'aspectLocked': aspectLocked,
    };
    if (type == FlyerElementType.text) {
      map['text'] = text ?? '';
      map['fontSize'] = fontSize;
      map['fontFamily'] = fontFamily;
      map['color'] = color;
      map['fontWeight'] = fontWeight;
      map['italic'] = italic;
      map['underline'] = underline;
      map['textAlign'] = textAlign;
      map['lineHeight'] = lineHeight;
      map['letterSpacing'] = letterSpacing;
      map['textShadow'] = textShadow;
      if (backgroundColor != null) map['backgroundColor'] = backgroundColor;
      if (outlineColor != null) map['outlineColor'] = outlineColor;
      map['outlineWidth'] = outlineWidth;
      map['curveAmount'] = curveAmount;
    } else if (type == FlyerElementType.image || type == FlyerElementType.logo) {
      map['url'] = url ?? '';
      map['fit'] = fit;
      map['cornerRadius'] = cornerRadius;
      map['brightness'] = brightness;
      map['contrast'] = contrast;
      map['saturation'] = saturation;
    } else if (type == FlyerElementType.qrcode) {
      // Renders through the same image codepath as image/logo (url/fit/
      // cornerRadius), but also keeps the raw encoded text and the
      // fg/bg colours used to generate it, so "Edit QR data" can
      // regenerate the PNG without the user retyping anything.
      map['text'] = text ?? '';
      map['url'] = url ?? '';
      map['fit'] = 'contain';
      map['cornerRadius'] = cornerRadius;
      map['color'] = color;
      if (backgroundColor != null) map['backgroundColor'] = backgroundColor;
    } else if (type == FlyerElementType.shape) {
      map['shapeColor'] = shapeColor;
      map['shapeKind'] = shapeKind;
      map['cornerRadius'] = cornerRadius;
      if (shapeGradientEnd != null) map['shapeGradientEnd'] = shapeGradientEnd;
      if (strokeColor != null) map['strokeColor'] = strokeColor;
      map['strokeWidth'] = strokeWidth;
    } else if (type == FlyerElementType.icon) {
      map['iconKey'] = iconKey;
      map['shapeColor'] = shapeColor;
    } else if (type == FlyerElementType.svg) {
      map['svgData'] = svgData ?? '';
      map['svgRecolor'] = svgRecolor;
      if (svgRecolor) map['shapeColor'] = shapeColor;
    } else if (type == FlyerElementType.chart) {
      map['chartKind'] = chartKind;
      map['chartLabels'] = chartLabels;
      map['chartValues'] = chartValues;
      map['shapeColor'] = shapeColor;
    } else if (type == FlyerElementType.drawing) {
      map['drawingPoints'] = drawingPoints;
      map['shapeColor'] = shapeColor;
      map['strokeWidth'] = strokeWidth;
    }
    return map;
  }

  FlyerElement clone() => FlyerElement.fromJson(toJson());
}
