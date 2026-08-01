import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef GlassSetter = void Function(bool);

/// Named font pairings — curated, not arbitrary. Mixing any heading font
/// with any body font tends to look accidental; these four are chosen
/// combinations, each with a distinct personality.
/// The overarching visual language for the whole app. Each mode is a
/// starting point — color, border thickness, opacity, texture, and
/// corner radius still layer on top of whichever mode is chosen, so two
/// people on "Corporate" with different accent colors still look
/// distinct, but recognizably "Corporate."
enum UIStyleMode {
  solid('Solid', Icons.crop_square, 'Fully opaque, soft shadow — the classic app look'),
  glass('Glass', Icons.blur_on, 'Frosted, blurred, crystal-edge'),
  liquid('Liquid', Icons.water_drop_outlined, 'Glossy glass with a soft light sheen'),
  transparent('Transparent', Icons.crop_free, 'Barely-there fill, thin outline only'),
  basic('Basic', Icons.check_box_outline_blank, 'No border, no shadow — pure minimal'),
  cartoon('Cartoon', Icons.emoji_emotions_outlined, 'Bold outlines, bright, playful'),
  corporate('Corporate', Icons.business_center_outlined, 'Muted, structured, professional');

  final String label;
  final IconData icon;
  final String description;
  const UIStyleMode(this.label, this.icon, this.description);
}

/// What happens visually the instant a finger touches a button or card —
/// a real, felt interaction detail, not just a static look.
enum TouchFeedback {
  none('None'),
  fade('Fade'),
  glow('Glow Pulse'),
  scale('Scale Down');

  final String label;
  const TouchFeedback(this.label);
}

enum NavPosition {
  bottom('Bottom'),
  top('Top Tabs');

  final String label;
  const NavPosition(this.label);
}

enum FontPairing {
  spaceGroteskInter('Modern (Space Grotesk + Inter)'),
  playfairLato('Editorial (Playfair Display + Lato)'),
  poppinsRoboto('Friendly (Poppins + Roboto)'),
  montserratOpenSans('Classic (Montserrat + Open Sans)');

  final String label;
  const FontPairing(this.label);
}

/// How cards render when Glass UI is off — a real stylistic choice, not
/// just a color. Flat (no shadow/border) reads minimal; Elevated adds a
/// soft shadow for depth; Outlined uses a border instead of a fill.
enum CardStyle {
  flat('Flat'),
  elevated('Elevated'),
  outlined('Outlined');

  final String label;
  const CardStyle(this.label);
}

/// Spacing density — maps to Flutter's own VisualDensity, so it's a real,
/// system-supported control (affects padding/touch-target sizing across
/// every Material widget), not a cosmetic-only slider.
enum SpacingDensity {
  compact('Compact', -2.0),
  standard('Standard', 0.0),
  comfortable('Comfortable', 1.5);

  final String label;
  final double value;
  const SpacingDensity(this.label, this.value);
}

/// A one-tap bundle of color + font + radius + mode choices — the "quick
/// pick" alternative to manually tuning every control one at a time.
class ThemePreset {
  final String name;
  final String tagline;
  final Color primary;
  final Color accent;
  final FontPairing font;
  final double radius;
  final bool dark;
  final UIStyleMode styleMode;
  final bool glow;
  final Color? glowColor;
  final bool floating;
  final bool texture;
  const ThemePreset(this.name, this.tagline, this.primary, this.accent, this.font, this.radius, this.dark, this.styleMode,
      {this.glow = false, this.glowColor, this.floating = false, this.texture = false});
}

/// 10 fully distinct, ready-to-launch looks — each a genuinely different
/// combination of color, font, shape, and effects, not just palette swaps.
const List<ThemePreset> themePresets = [
  ThemePreset('Classic Navy', 'Timeless & trustworthy', Color(0xFF1B2A4A), Color(0xFFE8A33D), FontPairing.spaceGroteskInter, 16, false, UIStyleMode.solid),
  ThemePreset('Midnight Glass', 'Frosted after-dark', Color(0xFF0F172A), Color(0xFF38BDF8), FontPairing.poppinsRoboto, 20, true, UIStyleMode.glass),
  ThemePreset('Liquid Sky', 'Glossy & weightless', Color(0xFF1D4ED8), Color(0xFF7DD3FC), FontPairing.spaceGroteskInter, 26, false, UIStyleMode.liquid),
  ThemePreset('Sunrise Minimal', 'Warm & unadorned', Color(0xFFB45309), Color(0xFFEA580C), FontPairing.montserratOpenSans, 8, false, UIStyleMode.basic),
  ThemePreset('Editorial Ink', 'Print-inspired, serif', Color(0xFF334155), Color(0xFFBE185D), FontPairing.playfairLato, 4, false, UIStyleMode.corporate),
  ThemePreset('Comic Pop', 'Bold, playful, loud', Color(0xFFDC2626), Color(0xFFFACC15), FontPairing.poppinsRoboto, 18, false, UIStyleMode.cartoon),
  ThemePreset('Ghost Mode', 'Barely-there, quiet', Color(0xFF334155), Color(0xFF64748B), FontPairing.spaceGroteskInter, 12, false, UIStyleMode.transparent),
  ThemePreset('Cyber Neon', 'Electric night-drive', Color(0xFF0A0A0F), Color(0xFF00E5FF), FontPairing.spaceGroteskInter, 10, true, UIStyleMode.solid,
      glow: true, glowColor: Color(0xFF00E5FF), floating: true),
  ThemePreset('Studio Paper', 'Tactile, hand-crafted', Color(0xFF57534E), Color(0xFFB45309), FontPairing.playfairLato, 6, false, UIStyleMode.corporate,
      texture: true),
  ThemePreset('Aurora Float', 'Soft glow, high lift', Color(0xFF6D28D9), Color(0xFFEC4899), FontPairing.montserratOpenSans, 24, true, UIStyleMode.glass,
      glow: true, glowColor: Color(0xFFEC4899), floating: true),
];

/// Every visual control the end user can personalize, all in one place,
/// all persisted on-device (personal display preference, not synced to
/// the backend / not shared with teammates).
class AppearanceSettings extends ChangeNotifier {
  static const _primaryKey = 'appearance_primary_color';
  static const _accentKey = 'appearance_accent_color';
  static const _fontKey = 'appearance_font_pairing';
  static const _fontScaleKey = 'appearance_font_scale';
  static const _radiusKey = 'appearance_corner_radius';
  static const _darkModeKey = 'appearance_dark_mode';
  static const _cardStyleKey = 'appearance_card_style';
  static const _densityKey = 'appearance_density';
  static const _hapticsKey = 'appearance_haptics';
  static const _styleModeKey = 'appearance_style_mode';
  static const _borderThicknessKey = 'appearance_border_thickness';
  static const _opacityKey = 'appearance_opacity';
  static const _componentScaleKey = 'appearance_component_scale';
  static const _textureKey = 'appearance_texture';
  static const _glowEnabledKey = 'appearance_glow_enabled';
  static const _glowColorKey = 'appearance_glow_color';
  static const _glowIntensityKey = 'appearance_glow_intensity';
  static const _edgeBlurKey = 'appearance_edge_blur';
  static const _outlineColorKey = 'appearance_outline_color';
  static const _floatingEnabledKey = 'appearance_floating_enabled';
  static const _floatingIntensityKey = 'appearance_floating_intensity';
  static const _touchFeedbackKey = 'appearance_touch_feedback';
  static const _swipeActionsKey = 'appearance_swipe_actions';
  static const _navPositionKey = 'appearance_nav_position';

  // Defaults match the original LeadFlow AI identity (Ink Navy / Signal Amber).
  Color _primaryColor = const Color(0xFF1B2A4A);
  Color _accentColor = const Color(0xFFE8A33D);
  FontPairing _fontPairing = FontPairing.spaceGroteskInter;
  double _fontScale = 1.0;
  double _cornerRadius = 16.0;
  bool _darkMode = false;
  CardStyle _cardStyle = CardStyle.flat;
  SpacingDensity _density = SpacingDensity.standard;
  bool _haptics = true;
  UIStyleMode _styleMode = UIStyleMode.solid;
  double _borderThickness = 1.0;
  double _componentOpacity = 1.0;
  double _componentScale = 1.0;
  bool _textureEnabled = false;
  bool _glowEnabled = false;
  Color _glowColor = const Color(0xFF00E5FF); // cyan neon default
  double _glowIntensity = 0.5;
  double _edgeBlur = 0.0;
  Color? _outlineColor; // null = auto-derived from primary color, as before
  bool _floatingEnabled = false;
  double _floatingIntensity = 0.5;
  TouchFeedback _touchFeedback = TouchFeedback.fade;
  bool _swipeActionsEnabled = false;
  NavPosition _navPosition = NavPosition.bottom;
  bool _loaded = false;

  Color get primaryColor => _primaryColor;
  Color get accentColor => _accentColor;
  FontPairing get fontPairing => _fontPairing;
  double get fontScale => _fontScale;
  double get cornerRadius => _cornerRadius;
  bool get darkMode => _darkMode;
  CardStyle get cardStyle => _cardStyle;
  SpacingDensity get density => _density;
  bool get haptics => _haptics;
  UIStyleMode get styleMode => _styleMode;
  double get borderThickness => _borderThickness;
  double get componentOpacity => _componentOpacity;
  double get componentScale => _componentScale;
  bool get textureEnabled => _textureEnabled;
  bool get glowEnabled => _glowEnabled;
  Color get glowColor => _glowColor;
  double get glowIntensity => _glowIntensity;
  double get edgeBlur => _edgeBlur;
  Color? get outlineColor => _outlineColor;
  bool get floatingEnabled => _floatingEnabled;
  double get floatingIntensity => _floatingIntensity;
  TouchFeedback get touchFeedback => _touchFeedback;
  bool get swipeActionsEnabled => _swipeActionsEnabled;
  NavPosition get navPosition => _navPosition;
  bool get loaded => _loaded;

  /// Whether the current mode implies a translucent/blurred treatment —
  /// hero widgets (GlassContainer/GlassButton) use this to decide whether
  /// to render their true-blur variant.
  bool get isGlassy => _styleMode == UIStyleMode.glass || _styleMode == UIStyleMode.liquid;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final primaryValue = prefs.getInt(_primaryKey);
    final accentValue = prefs.getInt(_accentKey);
    if (primaryValue != null) _primaryColor = Color(primaryValue);
    if (accentValue != null) _accentColor = Color(accentValue);
    final fontIndex = prefs.getInt(_fontKey);
    if (fontIndex != null && fontIndex < FontPairing.values.length) {
      _fontPairing = FontPairing.values[fontIndex];
    }
    _fontScale = prefs.getDouble(_fontScaleKey) ?? 1.0;
    _cornerRadius = prefs.getDouble(_radiusKey) ?? 16.0;
    _darkMode = prefs.getBool(_darkModeKey) ?? false;
    final cardStyleIndex = prefs.getInt(_cardStyleKey);
    if (cardStyleIndex != null && cardStyleIndex < CardStyle.values.length) {
      _cardStyle = CardStyle.values[cardStyleIndex];
    }
    final densityIndex = prefs.getInt(_densityKey);
    if (densityIndex != null && densityIndex < SpacingDensity.values.length) {
      _density = SpacingDensity.values[densityIndex];
    }
    _haptics = prefs.getBool(_hapticsKey) ?? true;
    final styleModeIndex = prefs.getInt(_styleModeKey);
    if (styleModeIndex != null && styleModeIndex < UIStyleMode.values.length) {
      _styleMode = UIStyleMode.values[styleModeIndex];
    }
    _borderThickness = prefs.getDouble(_borderThicknessKey) ?? 1.0;
    _componentOpacity = prefs.getDouble(_opacityKey) ?? 1.0;
    _componentScale = prefs.getDouble(_componentScaleKey) ?? 1.0;
    _textureEnabled = prefs.getBool(_textureKey) ?? false;
    _glowEnabled = prefs.getBool(_glowEnabledKey) ?? false;
    final glowColorValue = prefs.getInt(_glowColorKey);
    if (glowColorValue != null) _glowColor = Color(glowColorValue);
    _glowIntensity = prefs.getDouble(_glowIntensityKey) ?? 0.5;
    _edgeBlur = prefs.getDouble(_edgeBlurKey) ?? 0.0;
    final outlineValue = prefs.getInt(_outlineColorKey);
    if (outlineValue != null) _outlineColor = Color(outlineValue);
    _floatingEnabled = prefs.getBool(_floatingEnabledKey) ?? false;
    _floatingIntensity = prefs.getDouble(_floatingIntensityKey) ?? 0.5;
    final touchIndex = prefs.getInt(_touchFeedbackKey);
    if (touchIndex != null && touchIndex < TouchFeedback.values.length) {
      _touchFeedback = TouchFeedback.values[touchIndex];
    }
    _swipeActionsEnabled = prefs.getBool(_swipeActionsKey) ?? false;
    final navIndex = prefs.getInt(_navPositionKey);
    if (navIndex != null && navIndex < NavPosition.values.length) {
      _navPosition = NavPosition.values[navIndex];
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setPrimaryColor(Color c) async {
    _primaryColor = c;
    notifyListeners();
    (await SharedPreferences.getInstance()).setInt(_primaryKey, c.value);
  }

  Future<void> setAccentColor(Color c) async {
    _accentColor = c;
    notifyListeners();
    (await SharedPreferences.getInstance()).setInt(_accentKey, c.value);
  }

  Future<void> setFontPairing(FontPairing f) async {
    _fontPairing = f;
    notifyListeners();
    (await SharedPreferences.getInstance()).setInt(_fontKey, f.index);
  }

  Future<void> setFontScale(double v) async {
    _fontScale = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setDouble(_fontScaleKey, v);
  }

  Future<void> setCornerRadius(double v) async {
    _cornerRadius = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setDouble(_radiusKey, v);
  }

  Future<void> setDarkMode(bool v) async {
    _darkMode = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_darkModeKey, v);
  }

  Future<void> setCardStyle(CardStyle v) async {
    _cardStyle = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setInt(_cardStyleKey, v.index);
  }

  Future<void> setDensity(SpacingDensity v) async {
    _density = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setInt(_densityKey, v.index);
  }

  Future<void> setHaptics(bool v) async {
    _haptics = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_hapticsKey, v);
  }

  /// Changing the style mode also flips the (separate) GlassSettings.enabled
  /// flag automatically — glass/liquid modes want true backdrop blur on
  /// hero surfaces, every other mode doesn't. Callers pass GlassSettings'
  /// own setter so this file doesn't need a direct dependency on it.
  Future<void> setStyleMode(UIStyleMode mode, GlassSetter setGlassEnabled) async {
    _styleMode = mode;
    notifyListeners();
    (await SharedPreferences.getInstance()).setInt(_styleModeKey, mode.index);
    setGlassEnabled(mode == UIStyleMode.glass || mode == UIStyleMode.liquid);
  }

  Future<void> setBorderThickness(double v) async {
    _borderThickness = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setDouble(_borderThicknessKey, v);
  }

  Future<void> setComponentOpacity(double v) async {
    _componentOpacity = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setDouble(_opacityKey, v);
  }

  Future<void> setComponentScale(double v) async {
    _componentScale = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setDouble(_componentScaleKey, v);
  }

  Future<void> setTextureEnabled(bool v) async {
    _textureEnabled = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_textureKey, v);
  }

  Future<void> setGlowEnabled(bool v) async {
    _glowEnabled = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_glowEnabledKey, v);
  }

  Future<void> setGlowColor(Color c) async {
    _glowColor = c;
    notifyListeners();
    (await SharedPreferences.getInstance()).setInt(_glowColorKey, c.value);
  }

  Future<void> setGlowIntensity(double v) async {
    _glowIntensity = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setDouble(_glowIntensityKey, v);
  }

  Future<void> setEdgeBlur(double v) async {
    _edgeBlur = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setDouble(_edgeBlurKey, v);
  }

  Future<void> setOutlineColor(Color? c) async {
    _outlineColor = c;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (c == null) {
      await prefs.remove(_outlineColorKey);
    } else {
      await prefs.setInt(_outlineColorKey, c.value);
    }
  }

  Future<void> setFloatingEnabled(bool v) async {
    _floatingEnabled = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_floatingEnabledKey, v);
  }

  Future<void> setFloatingIntensity(double v) async {
    _floatingIntensity = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setDouble(_floatingIntensityKey, v);
  }

  Future<void> setTouchFeedback(TouchFeedback v) async {
    _touchFeedback = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setInt(_touchFeedbackKey, v.index);
  }

  Future<void> setSwipeActionsEnabled(bool v) async {
    _swipeActionsEnabled = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_swipeActionsKey, v);
  }

  Future<void> setNavPosition(NavPosition v) async {
    _navPosition = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setInt(_navPositionKey, v.index);
  }

  /// Applies every value from a curated preset at once — the "quick pick"
  /// path, still fully overridable afterward via the individual controls.
  Future<void> applyPreset(ThemePreset preset, GlassSetter setGlassEnabled) async {
    _primaryColor = preset.primary;
    _accentColor = preset.accent;
    _fontPairing = preset.font;
    _cornerRadius = preset.radius;
    _darkMode = preset.dark;
    _styleMode = preset.styleMode;
    _glowEnabled = preset.glow;
    if (preset.glowColor != null) _glowColor = preset.glowColor!;
    _floatingEnabled = preset.floating;
    _textureEnabled = preset.texture;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setInt(_primaryKey, preset.primary.value),
      prefs.setInt(_accentKey, preset.accent.value),
      prefs.setInt(_fontKey, preset.font.index),
      prefs.setDouble(_radiusKey, preset.radius),
      prefs.setBool(_darkModeKey, preset.dark),
      prefs.setInt(_styleModeKey, preset.styleMode.index),
      prefs.setBool(_glowEnabledKey, preset.glow),
      prefs.setBool(_floatingEnabledKey, preset.floating),
      prefs.setBool(_textureKey, preset.texture),
      if (preset.glowColor != null) prefs.setInt(_glowColorKey, preset.glowColor!.value),
    ]);
    setGlassEnabled(preset.styleMode == UIStyleMode.glass || preset.styleMode == UIStyleMode.liquid);
  }

  Future<void> resetToDefaults() async {
    _primaryColor = const Color(0xFF1B2A4A);
    _accentColor = const Color(0xFFE8A33D);
    _fontPairing = FontPairing.spaceGroteskInter;
    _fontScale = 1.0;
    _cornerRadius = 16.0;
    _darkMode = false;
    _cardStyle = CardStyle.flat;
    _density = SpacingDensity.standard;
    _haptics = true;
    _styleMode = UIStyleMode.solid;
    _borderThickness = 1.0;
    _componentOpacity = 1.0;
    _componentScale = 1.0;
    _textureEnabled = false;
    _glowEnabled = false;
    _glowColor = const Color(0xFF00E5FF);
    _glowIntensity = 0.5;
    _edgeBlur = 0.0;
    _outlineColor = null;
    _floatingEnabled = false;
    _floatingIntensity = 0.5;
    _touchFeedback = TouchFeedback.fade;
    _swipeActionsEnabled = false;
    _navPosition = NavPosition.bottom;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_primaryKey),
      prefs.remove(_accentKey),
      prefs.remove(_fontKey),
      prefs.remove(_fontScaleKey),
      prefs.remove(_radiusKey),
      prefs.remove(_darkModeKey),
      prefs.remove(_cardStyleKey),
      prefs.remove(_densityKey),
      prefs.remove(_hapticsKey),
      prefs.remove(_styleModeKey),
      prefs.remove(_borderThicknessKey),
      prefs.remove(_opacityKey),
      prefs.remove(_componentScaleKey),
      prefs.remove(_textureKey),
      prefs.remove(_glowEnabledKey),
      prefs.remove(_glowColorKey),
      prefs.remove(_glowIntensityKey),
      prefs.remove(_edgeBlurKey),
      prefs.remove(_outlineColorKey),
      prefs.remove(_floatingEnabledKey),
      prefs.remove(_floatingIntensityKey),
      prefs.remove(_touchFeedbackKey),
      prefs.remove(_swipeActionsKey),
      prefs.remove(_navPositionKey),
    ]);
  }
}
