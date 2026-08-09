// FlyerElement — the core data model for Flyer Studio v2's freeform canvas.
// Every visual thing on a flyer (text, image, logo, colored shape) is one of
// these. This mirrors the backend's `canvas_json` array shape exactly
// (flyerProjects.js), so toJson()/fromJson() round-trip cleanly through
// PATCH /flyer-projects/:id with zero server-side transformation needed.

enum FlyerElementType { text, image, logo, shape }

FlyerElementType flyerElementTypeFromString(String? s) {
  switch (s) {
    case 'image':
      return FlyerElementType.image;
    case 'logo':
      return FlyerElementType.logo;
    case 'shape':
      return FlyerElementType.shape;
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
    case FlyerElementType.text:
      return 'text';
  }
}

// The 8 real bundled Google Fonts from the earlier "premium fonts" fix —
// reusing this exact list keeps Flyer Studio visually consistent with the
// rest of the app's typography system, and lets the AI-generate endpoint
// whitelist against a font set that's guaranteed to actually render
// on-device (no network font-fetch, ships in the APK).
const List<String> kFlyerFontFamilies = [
  'SpaceGrotesk',
  'Inter',
  'PlayfairDisplay',
  'Lato',
  'Poppins',
  'Roboto',
  'Montserrat',
  'OpenSans',
];

class FlyerElement {
  String id;
  FlyerElementType type;
  double x;
  double y;
  double width;
  double height;
  double rotation; // degrees, 0-360
  int zIndex;

  // Text-specific
  String? text;
  double fontSize;
  String fontFamily;
  String color; // hex, e.g. "#000000"
  String fontWeight; // 'normal' | 'bold'
  String textAlign; // 'left' | 'center' | 'right'
  String? backgroundColor; // hex or null (transparent)

  // Image / logo-specific
  String? url;
  String fit; // 'cover' | 'contain'
  double opacity;

  // Shape-specific
  String shapeColor;

  FlyerElement({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    this.width = 200,
    this.height = 100,
    this.rotation = 0,
    this.zIndex = 0,
    this.text,
    this.fontSize = 24,
    this.fontFamily = 'Roboto',
    this.color = '#000000',
    this.fontWeight = 'normal',
    this.textAlign = 'left',
    this.backgroundColor,
    this.url,
    this.fit = 'cover',
    this.opacity = 1.0,
    this.shapeColor = '#CCCCCC',
  });

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
      text: json['text']?.toString(),
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 24,
      fontFamily: json['fontFamily']?.toString() ?? 'Roboto',
      color: json['color']?.toString() ?? '#000000',
      fontWeight: json['fontWeight']?.toString() ?? 'normal',
      textAlign: json['textAlign']?.toString() ?? 'left',
      backgroundColor: json['backgroundColor']?.toString(),
      url: json['url']?.toString(),
      fit: json['fit']?.toString() ?? 'cover',
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      shapeColor: json['shapeColor']?.toString() ?? '#CCCCCC',
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
    };
    if (type == FlyerElementType.text) {
      map['text'] = text ?? '';
      map['fontSize'] = fontSize;
      map['fontFamily'] = fontFamily;
      map['color'] = color;
      map['fontWeight'] = fontWeight;
      map['textAlign'] = textAlign;
      if (backgroundColor != null) map['backgroundColor'] = backgroundColor;
    } else if (type == FlyerElementType.image || type == FlyerElementType.logo) {
      map['url'] = url ?? '';
      map['fit'] = fit;
      map['opacity'] = opacity;
    } else if (type == FlyerElementType.shape) {
      map['shapeColor'] = shapeColor;
      map['opacity'] = opacity;
    }
    return map;
  }

  FlyerElement clone() => FlyerElement.fromJson(toJson());
}
