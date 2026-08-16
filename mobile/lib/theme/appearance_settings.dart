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
  montserratOpenSans('Classic (Montserrat + Open Sans)'),
  // Batch 4 additions -- every one of these recombines the same 8
  // already-bundled local .ttf families above in a fresh pairing. No new
  // font files, no google_fonts, no network dependency: this is the
  // exact property the earlier crash-fix relied on, deliberately kept
  // intact rather than reaching for "real" premium web fonts.
  interRoboto('Minimal SaaS (Inter + Roboto)'),
  playfairOpenSans('Warm Editorial (Playfair Display + Open Sans)'),
  spaceGroteskLato('Tech Warm (Space Grotesk + Lato)'),
  montserratInter('Bold Corporate (Montserrat + Inter)'),
  poppinsOpenSans('Soft Friendly (Poppins + Open Sans)'),
  interLato('Quiet Premium (Inter + Lato)');

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

/// Batch 1 (Customize Studio upgrade) additions below.

/// How screen-to-screen navigation animates. Purely visual; does not
/// affect app_theme.dart's page-route wiring on its own -- screens that
/// want to honor this read it from AppearanceSettings when building
/// their PageRouteBuilder, same as every other token here.
enum PageTransitionStyle {
  slide('Slide'),
  fade('Fade'),
  scale('Scale');

  final String label;
  const PageTransitionStyle(this.label);
}

/// List rows vs a grid vs denser compact rows -- primarily for the Leads
/// list and similar record lists, not a global layout override.
enum CardLayoutStyle {
  list('List'),
  grid('Grid'),
  compactRows('Compact Rows');

  final String label;
  const CardLayoutStyle(this.label);
}

/// Independent of the FontPairing bundle's built-in weight -- lets a user
/// nudge boldness without switching the whole font pairing.
enum FontWeightChoice {
  regular('Regular', FontWeight.w400),
  medium('Medium', FontWeight.w500),
  bold('Bold', FontWeight.w700);

  final String label;
  final FontWeight weight;
  const FontWeightChoice(this.label, this.weight);
}

/// Which tab a template appears under in the 20-template gallery
/// (Batch 5's UI). Kept here, next to ThemePreset, since it's metadata
/// about presets, not a runtime AppearanceSettings value -- nothing
/// persists "the current category," it only groups the gallery.
enum TemplateCategory {
  glass('Glass'),
  solidCorporate('Solid & Corporate'),
  softPlayful('Soft & Playful'),
  boldDark('Bold & Dark');

  final String label;
  const TemplateCategory(this.label);
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
  final TemplateCategory category;
  // Batch 2 additions -- optional, so every preset above didn't need
  // touching. When set, applyPreset() also turns on the primary-color
  // gradient / backdrop blur added in Batch 1's token foundation, so a
  // handful of templates (the glass/holographic ones) are the first real
  // consumers of those fields rather than them sitting unused.
  final Color? gradientEnd;
  final double backdropBlur;
  // Theme Engine v2 -- lets each template lean its tonal background/
  // surface tint stronger or weaker without changing its hue. A
  // restrained corporate template can pass a low value for an
  // almost-neutral surface; a bold/holographic one can pass a high
  // value for a much more visibly tinted dark surface. This is the
  // single biggest lever for making 19 templates' *background feel*
  // (not just their accent color) genuinely distinct from each other.
  final double tonalSaturationBoost;
  // Fix for a real gap found in review: Neo-Brutalist's tagline promises
  // "bold borders" but nothing in the preset actually set border
  // thickness -- applying it left whatever the global default was,
  // meaning the template's own stated personality was unfulfilled
  // unless the person separately, manually cranked Border Thickness
  // themselves. Defaults to 1.0, the existing app-wide default, so
  // templates that don't have a specific border opinion are unaffected.
  final double borderThickness;
  const ThemePreset(this.name, this.tagline, this.primary, this.accent, this.font, this.radius, this.dark, this.styleMode,
      {this.glow = false, this.glowColor, this.floating = false, this.texture = false, required this.category, this.gradientEnd, this.backdropBlur = 0.0, this.tonalSaturationBoost = 1.0, this.borderThickness = 1.0});
}

/// 19 fully distinct, ready-to-launch looks, matching the Customize
/// Studio master-prompt's 20-template spec (#20, "Custom AI-Generated,"
/// is intentionally not a static entry here -- it's the existing AI
/// Design Engine card, generated live, never a fixed preset).
///
/// Ten of the original ten presets are enriched + renamed to match the
/// spec's official template names rather than replaced, so a user who
/// already applied one of them keeps the same underlying look; nine are
/// new. Each carries a `category` for the gallery's tab filter (Glass /
/// Solid & Corporate / Soft & Playful / Bold & Dark).
const List<ThemePreset> themePresets = [
  // --- Glass ---
  // Theme Engine v2: tonalSaturationBoost is what actually makes these
  // 19 templates feel distinct from each other in their background/
  // surface, not just their accent button color -- each value below is
  // deliberately tied to the template's own stated personality (a
  // "banking-grade" template stays near-neutral; a "holographic" one
  // leans hard into visible tint), not picked arbitrarily.
  ThemePreset('iOS Liquid Glass', 'Apple-style frosted, specular highlight', Color(0xFF0A84FF), Color(0xFF64D2FF), FontPairing.spaceGroteskInter, 28, false, UIStyleMode.liquid,
      category: TemplateCategory.glass, gradientEnd: Color(0xFF64D2FF), backdropBlur: 0.8, tonalSaturationBoost: 1.0),
  ThemePreset('Midnight Glass Pro', 'Dark glassmorphism, neon accent glow', Color(0xFF0F172A), Color(0xFF38BDF8), FontPairing.poppinsRoboto, 20, true, UIStyleMode.glass,
      glow: true, glowColor: Color(0xFF38BDF8), category: TemplateCategory.glass, backdropBlur: 0.7, tonalSaturationBoost: 1.3),
  ThemePreset('Liquid Sky', 'Gradient-mesh, glossy, weightless', Color(0xFF1D4ED8), Color(0xFF7DD3FC), FontPairing.spaceGroteskInter, 26, false, UIStyleMode.liquid,
      category: TemplateCategory.glass, gradientEnd: Color(0xFF7DD3FC), backdropBlur: 0.5, tonalSaturationBoost: 1.3),
  ThemePreset('Holographic Lens', 'Iridescent gradient glass, light-refraction shimmer', Color(0xFF6D28D9), Color(0xFFEC4899), FontPairing.montserratOpenSans, 24, true, UIStyleMode.glass,
      glow: true, glowColor: Color(0xFFEC4899), floating: true, category: TemplateCategory.glass, gradientEnd: Color(0xFF06B6D4), backdropBlur: 0.6, tonalSaturationBoost: 1.8),
  ThemePreset('Frosted Acrylic', 'Fluent-style acrylic blur + depth layering', Color(0xFF2564CF), Color(0xFF60CDFF), FontPairing.poppinsRoboto, 8, false, UIStyleMode.glass,
      category: TemplateCategory.glass, backdropBlur: 0.9, tonalSaturationBoost: 1.1),

  // --- Solid & Corporate ---
  ThemePreset('Corporate Trust', 'Navy/slate, banking-grade seriousness', Color(0xFF1B2A4A), Color(0xFFE8A33D), FontPairing.spaceGroteskInter, 12, false, UIStyleMode.solid,
      category: TemplateCategory.solidCorporate, tonalSaturationBoost: 0.4),
  ThemePreset('Clinical Precision', 'Clean white/teal, high-legibility, zero clutter', Color(0xFF0D9488), Color(0xFF14B8A6), FontPairing.montserratOpenSans, 14, false, UIStyleMode.basic,
      category: TemplateCategory.solidCorporate, tonalSaturationBoost: 0.2, borderThickness: 0.6),
  ThemePreset('Editorial Premium', 'Serif display + sans body, magazine feel', Color(0xFF334155), Color(0xFFBE185D), FontPairing.playfairLato, 4, false, UIStyleMode.corporate,
      category: TemplateCategory.solidCorporate, tonalSaturationBoost: 0.3, borderThickness: 0.5),
  ThemePreset('Minimal Mono', 'Near-monochrome, single accent, brutalist-clean grid', Color(0xFF18181B), Color(0xFF71717A), FontPairing.spaceGroteskInter, 4, false, UIStyleMode.basic,
      category: TemplateCategory.solidCorporate, tonalSaturationBoost: 0.15, borderThickness: 0.5),
  ThemePreset('Pure Transparent', 'Barely-there fill, thin outline, content-first', Color(0xFF334155), Color(0xFF64748B), FontPairing.spaceGroteskInter, 12, false, UIStyleMode.transparent,
      category: TemplateCategory.solidCorporate, tonalSaturationBoost: 0.25, borderThickness: 0.5),
  ThemePreset('Executive Slate', 'Muted greys + single jewel accent, boardroom minimalism', Color(0xFF3F3F46), Color(0xFF7C3AED), FontPairing.playfairLato, 8, false, UIStyleMode.corporate,
      category: TemplateCategory.solidCorporate, tonalSaturationBoost: 0.3, borderThickness: 0.75),

  // --- Soft & Playful ---
  ThemePreset('Soft UI 2.0', 'Accessible neumorphism, tactile press states', Color(0xFF6366F1), Color(0xFFA5B4FC), FontPairing.montserratOpenSans, 20, false, UIStyleMode.basic,
      category: TemplateCategory.softPlayful, tonalSaturationBoost: 0.9),
  ThemePreset('Material 3 Expressive', 'Google M3 tonal palettes, dynamic color roles', Color(0xFF6750A4), Color(0xFF7D5260), FontPairing.poppinsRoboto, 20, false, UIStyleMode.solid,
      category: TemplateCategory.softPlayful, tonalSaturationBoost: 1.2),
  ThemePreset('Warm Consultancy', 'Cream/terracotta warmth, friendly rounded shapes', Color(0xFFB45309), Color(0xFFEA580C), FontPairing.montserratOpenSans, 18, false, UIStyleMode.basic,
      category: TemplateCategory.softPlayful, tonalSaturationBoost: 0.9),
  ThemePreset('Paper & Ink', 'Subtle paper texture, ink-accent CTAs, notebook feel', Color(0xFF57534E), Color(0xFFB45309), FontPairing.playfairLato, 6, false, UIStyleMode.corporate,
      texture: true, category: TemplateCategory.softPlayful, tonalSaturationBoost: 0.3),
  ThemePreset('Playful Rounded', 'Soft pastel, big radius, polished (not childish)', Color(0xFFDC2626), Color(0xFFFACC15), FontPairing.poppinsRoboto, 22, false, UIStyleMode.cartoon,
      category: TemplateCategory.softPlayful, tonalSaturationBoost: 1.1),

  // --- Bold & Dark ---
  ThemePreset('Fintech Dark', 'Deep charcoal, emerald/gold, dashboard-density optimized', Color(0xFF10B981), Color(0xFFEAB308), FontPairing.spaceGroteskInter, 10, true, UIStyleMode.solid,
      category: TemplateCategory.boldDark, tonalSaturationBoost: 1.1),
  ThemePreset('Neo-Brutalist', 'Bold borders, flat blocks, high-contrast, confident type', Color(0xFF000000), Color(0xFFFFD400), FontPairing.spaceGroteskInter, 0, false, UIStyleMode.basic,
      category: TemplateCategory.boldDark, tonalSaturationBoost: 0.0, borderThickness: 3.0),
  ThemePreset('Cyberpunk Neon', 'Electric night-drive, neon edges, gradient borders', Color(0xFF0A0A0F), Color(0xFF00E5FF), FontPairing.spaceGroteskInter, 10, true, UIStyleMode.solid,
      glow: true, glowColor: Color(0xFF00E5FF), floating: true, category: TemplateCategory.boldDark, gradientEnd: Color(0xFFFF00E5), tonalSaturationBoost: 2.0, borderThickness: 1.5),
];

/// Every visual control the end user can personalize, all in one place,
/// all persisted on-device (personal display preference, not synced to
/// the backend / not shared with teammates).
/// Where the custom branding logo renders relative to the app bar --
/// deliberately just these three, not free-drag positioning, since a
/// logo that can be dragged anywhere risks overlapping real content
/// on a 6-inch screen with no way to recover except resetting.
enum LogoPosition {
  topLeft('Top Left'),
  topCenter('Top Center'),
  topRight('Top Right');

  final String label;
  const LogoPosition(this.label);
}

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

  // Batch 1 (Customize Studio upgrade) — new token fields. Each follows
  // the exact same field/getter/setter/load/reset pattern as everything
  // above; grouped here by the Part-2 section they belong to so a later
  // batch wiring up UI for one section can find all its keys together.
  static const _primaryGradientEnabledKey = 'appearance_primary_gradient_enabled';
  static const _primaryGradientEndKey = 'appearance_primary_gradient_end';
  static const _accentGradientEnabledKey = 'appearance_accent_gradient_enabled';
  static const _accentGradientEndKey = 'appearance_accent_gradient_end';
  static const _shadowElevationKey = 'appearance_shadow_elevation';
  static const _cardDensityScaleKey = 'appearance_card_density_scale';
  static const _pageTransitionKey = 'appearance_page_transition';
  static const _reduceMotionKey = 'appearance_reduce_motion';
  static const _backdropBlurIntensityKey = 'appearance_backdrop_blur_intensity';
  static const _cardLayoutStyleKey = 'appearance_card_layout_style';
  static const _autoDarkModeKey = 'appearance_auto_dark_mode';
  static const _accessibilityFontScaleKey = 'appearance_accessibility_font_scale';
  static const _highContrastModeKey = 'appearance_high_contrast_mode';
  static const _letterSpacingKey = 'appearance_letter_spacing';
  static const _fontWeightChoiceKey = 'appearance_font_weight_choice';

  // Theme Engine v2 -- independent overrides for the three surfaces that
  // used to be one flat hardcoded color for the entire app regardless of
  // theme. null = auto-derive from primaryColor via tonal_palette.dart
  // (the good default); set = the person deliberately chose their own,
  // e.g. wants a pure-black background but the auto-tinted surface cards.
  static const _backgroundOverrideKey = 'appearance_background_override';
  static const _surfaceOverrideKey = 'appearance_surface_override';
  static const _appBarOverrideKey = 'appearance_appbar_override';
  static const _saturationBoostKey = 'appearance_tonal_saturation_boost';
  static const _auroraEnabledKey = 'appearance_aurora_backdrop_enabled';
  static const _auroraIntensityKey = 'appearance_aurora_intensity';
  static const _customBackgroundPathKey = 'appearance_custom_background_path';
  static const _customLogoPathKey = 'appearance_custom_logo_path';
  static const _logoPositionKey = 'appearance_logo_position';
  // Semantic colours. These were previously hardcoded in AppColors and read
  // directly by badges, alerts and status chips, which meant a tenant could
  // restyle the whole app and still be stuck with our green/amber/red.
  static const _successKey = 'appearance_success_color';
  static const _warningKey = 'appearance_warning_color';
  static const _dangerKey = 'appearance_danger_color';
  static const _mutedKey = 'appearance_muted_color';

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
  Color _successColor = const Color(0xFF2E9E6D);
  Color _warningColor = const Color(0xFFE8A33D);
  Color _dangerColor = const Color(0xFFE85D4E);
  Color _mutedColor = const Color(0xFF5B6478);

  // Batch 1 additions. Defaults are all "off / neutral" so an existing
  // user's app looks identical the instant this ships -- nothing here
  // changes what renders until a later batch's UI lets someone touch it.
  bool _primaryGradientEnabled = false;
  Color? _primaryGradientEnd;
  bool _accentGradientEnabled = false;
  Color? _accentGradientEnd;
  double _shadowElevation = 0.0;
  double _cardDensityScale = 1.0;
  PageTransitionStyle _pageTransitionStyle = PageTransitionStyle.slide;
  bool _reduceMotion = false;
  double _backdropBlurIntensity = 0.0;
  CardLayoutStyle _cardLayoutStyle = CardLayoutStyle.list;
  bool _autoDarkMode = false;
  double _accessibilityFontScale = 1.0;
  bool _highContrastMode = false;
  double _letterSpacing = 0.0;
  FontWeightChoice _fontWeightChoice = FontWeightChoice.regular;

  // Theme Engine v2 fields. All null/1.0 defaults = auto-derive, zero
  // visual change until someone actually opens the new advanced controls.
  Color? _backgroundOverride;
  Color? _surfaceOverride;
  Color? _appBarOverride;
  double _tonalSaturationBoost = 1.0;

  // Theme Engine v3 -- ambient multi-blob glow backdrop (see
  // widgets/aurora_backdrop.dart). Default false = zero visual change
  // on ship; existing flat-gradient glass backdrop stays exactly as-is
  // until someone opts in from Settings > Effects.
  bool _auroraBackdropEnabled = false;
  double _auroraIntensity = 0.85;

  // Theme Engine v3 -- local branding assets (custom background
  // wallpaper + logo). Paths point into app-local storage via
  // services/local_branding_assets.dart; null = not set, falls back
  // to Aurora/gradient backdrop and no logo, exactly current behaviour.
  String? _customBackgroundImagePath;
  String? _customLogoPath;
  LogoPosition _logoPosition = LogoPosition.topLeft;

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

  /// Semantic colours — used by score badges, Lead 360 alert severities,
  /// sentiment indicators, document/fee status chips and anything else that
  /// signals "good / needs attention / problem / inactive". Fully
  /// user-controlled like every other colour in the system.
  Color get successColor => _successColor;
  Color get warningColor => _warningColor;
  Color get dangerColor => _dangerColor;
  Color get mutedColor => _mutedColor;
  bool get loaded => _loaded;

  /// Whether the current mode implies a translucent/blurred treatment —
  /// hero widgets (GlassContainer/GlassButton) use this to decide whether
  /// to render their true-blur variant.
  bool get isGlassy => _styleMode == UIStyleMode.glass || _styleMode == UIStyleMode.liquid;

  // Batch 1 getters.
  bool get primaryGradientEnabled => _primaryGradientEnabled;
  Color? get primaryGradientEnd => _primaryGradientEnd;
  bool get accentGradientEnabled => _accentGradientEnabled;
  Color? get accentGradientEnd => _accentGradientEnd;
  double get shadowElevation => _shadowElevation;
  double get cardDensityScale => _cardDensityScale;
  PageTransitionStyle get pageTransitionStyle => _pageTransitionStyle;
  bool get reduceMotion => _reduceMotion;
  double get backdropBlurIntensity => _backdropBlurIntensity;
  CardLayoutStyle get cardLayoutStyle => _cardLayoutStyle;
  bool get autoDarkMode => _autoDarkMode;
  double get accessibilityFontScale => _accessibilityFontScale;
  bool get highContrastMode => _highContrastMode;
  double get letterSpacing => _letterSpacing;
  FontWeightChoice get fontWeightChoice => _fontWeightChoice;

  // Theme Engine v2 getters.
  Color? get backgroundOverride => _backgroundOverride;
  Color? get surfaceOverride => _surfaceOverride;
  Color? get appBarOverride => _appBarOverride;
  double get tonalSaturationBoost => _tonalSaturationBoost;
  bool get auroraBackdropEnabled => _auroraBackdropEnabled;
  double get auroraIntensity => _auroraIntensity;
  String? get customBackgroundImagePath => _customBackgroundImagePath;
  String? get customLogoPath => _customLogoPath;
  LogoPosition get logoPosition => _logoPosition;

  // ---------- Custom presets ("Save current as preset") ----------
  // Encoded as '~~'-delimited strings (not JSON, to avoid adding a
  // dart:convert import for one small feature) in a SharedPreferences
  // string list. Overwrites any existing preset with the same name.
  static const _customPresetsKey = 'custom_theme_presets';

  String _encodePreset(ThemePreset p) {
    return [
      p.name, p.tagline,
      p.primary.value.toString(), p.accent.value.toString(),
      p.font.index.toString(), p.radius.toString(), p.dark.toString(), p.styleMode.index.toString(),
      p.glow.toString(), p.glowColor?.value.toString() ?? '', p.floating.toString(), p.texture.toString(),
      // Batch 2 additions, appended rather than interleaved so a preset
      // saved before this change still parses (see _decodePreset below).
      p.category.index.toString(), p.gradientEnd?.value.toString() ?? '', p.backdropBlur.toString(),
      // Theme Engine v2 additions, same append-only approach.
      p.tonalSaturationBoost.toString(), p.borderThickness.toString(),
    ].join('~~');
  }

  ThemePreset? _decodePreset(String raw) {
    try {
      final parts = raw.split('~~');
      // Accept the original 12-field format, the Batch-2 15-field one,
      // the 16-field one, and the new 17-field one -- old saves
      // shouldn't silently vanish just because the schema grew again.
      if (parts.length != 12 && parts.length != 15 && parts.length != 16 && parts.length != 17) return null;
      return ThemePreset(
        parts[0], parts[1],
        Color(int.parse(parts[2])), Color(int.parse(parts[3])),
        FontPairing.values[int.parse(parts[4])],
        double.parse(parts[5]), parts[6] == 'true',
        UIStyleMode.values[int.parse(parts[7])],
        glow: parts[8] == 'true',
        glowColor: parts[9].isEmpty ? null : Color(int.parse(parts[9])),
        floating: parts[10] == 'true',
        texture: parts[11] == 'true',
        category: parts.length >= 15 ? TemplateCategory.values[int.parse(parts[12])] : TemplateCategory.solidCorporate,
        gradientEnd: parts.length >= 15 && parts[13].isNotEmpty ? Color(int.parse(parts[13])) : null,
        backdropBlur: parts.length >= 15 ? double.parse(parts[14]) : 0.0,
        tonalSaturationBoost: parts.length >= 16 ? double.parse(parts[15]) : 1.0,
        borderThickness: parts.length == 17 ? double.parse(parts[16]) : 1.0,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<ThemePreset>> getCustomPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_customPresetsKey) ?? [];
    return raw.map(_decodePreset).whereType<ThemePreset>().toList();
  }

  Future<void> saveCurrentAsPreset(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_customPresetsKey) ?? [];
    final preset = ThemePreset(
      name, 'Custom', _primaryColor, _accentColor, _fontPairing, _cornerRadius, _darkMode, _styleMode,
      glow: _glowEnabled, glowColor: _glowEnabled ? _glowColor : null, floating: _floatingEnabled, texture: _textureEnabled,
      // "Custom" doesn't fit a fixed category -- Solid & Corporate is the
      // neutral default (matches _decodePreset's fallback for the same
      // reason), and current gradient/blur/tonal/border state carries
      // over so a user's saved look round-trips exactly, not just its
      // base colors.
      category: TemplateCategory.solidCorporate,
      gradientEnd: _primaryGradientEnabled ? _primaryGradientEnd : null,
      backdropBlur: _backdropBlurIntensity,
      tonalSaturationBoost: _tonalSaturationBoost,
      borderThickness: _borderThickness,
    );
    raw.removeWhere((r) => r.split('~~').first == name);
    raw.add(_encodePreset(preset));
    await prefs.setStringList(_customPresetsKey, raw);
    notifyListeners();
  }

  Future<void> deleteCustomPreset(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_customPresetsKey) ?? [];
    raw.removeWhere((r) => r.split('~~').first == name);
    await prefs.setStringList(_customPresetsKey, raw);
    notifyListeners();
  }

  // ---------- Theme Engine v3: Aurora backdrop ----------
  Future<void> setAuroraBackdropEnabled(bool value) async {
    _auroraBackdropEnabled = value;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_auroraEnabledKey, value);
  }

  Future<void> setAuroraIntensity(double value) async {
    _auroraIntensity = value;
    notifyListeners();
    (await SharedPreferences.getInstance()).setDouble(_auroraIntensityKey, value);
  }

  // ---------- Theme Engine v3: local branding assets ----------
  Future<void> setCustomBackgroundImagePath(String? path) async {
    _customBackgroundImagePath = path;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove(_customBackgroundPathKey);
    } else {
      await prefs.setString(_customBackgroundPathKey, path);
    }
  }

  Future<void> setCustomLogoPath(String? path) async {
    _customLogoPath = path;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove(_customLogoPathKey);
    } else {
      await prefs.setString(_customLogoPathKey, path);
    }
  }

  Future<void> setLogoPosition(LogoPosition v) async {
    _logoPosition = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setInt(_logoPositionKey, v.index);
  }

  // ---------- Per-section reset ----------
  // Each of these only touches the fields shown in that section of the
  // Customize screen -- reuses the existing public setters (already
  // proven correct) rather than duplicating SharedPreferences key names.
  Future<void> resetColors() async {
    await setPrimaryColor(const Color(0xFF1B2A4A));
    await setAccentColor(const Color(0xFFE8A33D));
    await setOutlineColor(null);
    await setSuccessColor(const Color(0xFF2E9E6D));
    await setWarningColor(const Color(0xFFE8A33D));
    await setDangerColor(const Color(0xFFE85D4E));
    await setMutedColor(const Color(0xFF5B6478));
  }

  Future<void> resetTypography() async {
    await setFontPairing(FontPairing.spaceGroteskInter);
    await setFontScale(1.0);
    // Batch 4 additions.
    await setLetterSpacing(0.0);
    await setFontWeightChoice(FontWeightChoice.regular);
    await setAccessibilityFontScale(1.0);
  }

  Future<void> resetShape() async {
    await setCornerRadius(16.0);
    await setBorderThickness(1.0);
    await setComponentOpacity(1.0);
    await setComponentScale(1.0);
    await setEdgeBlur(0.0);
  }

  Future<void> resetEffects() async {
    await setGlowEnabled(false);
    await setGlowColor(const Color(0xFF00E5FF));
    await setGlowIntensity(0.5);
    await setFloatingEnabled(false);
    await setFloatingIntensity(0.5);
    await setTextureEnabled(false);
  }

  Future<void> resetLayout() async {
    await setDensity(SpacingDensity.standard);
    await setNavPosition(NavPosition.bottom);
    await setSwipeActionsEnabled(false);
  }

  Future<void> resetModeAndAccessibility() async {
    await setDarkMode(false);
    await setHaptics(true);
    await setTouchFeedback(TouchFeedback.fade);
  }

  Future<void> resetBranding() async {
    await setAuroraBackdropEnabled(false);
    await setAuroraIntensity(0.85);
    await setCustomBackgroundImagePath(null);
    await setCustomLogoPath(null);
    await setLogoPosition(LogoPosition.topLeft);
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final primaryValue = prefs.getInt(_primaryKey);
    final accentValue = prefs.getInt(_accentKey);
    if (primaryValue != null) _primaryColor = Color(primaryValue);
    if (accentValue != null) _accentColor = Color(accentValue);
    final successValue = prefs.getInt(_successKey);
    final warningValue = prefs.getInt(_warningKey);
    final dangerValue = prefs.getInt(_dangerKey);
    final mutedValue = prefs.getInt(_mutedKey);
    if (successValue != null) _successColor = Color(successValue);
    if (warningValue != null) _warningColor = Color(warningValue);
    if (dangerValue != null) _dangerColor = Color(dangerValue);
    if (mutedValue != null) _mutedColor = Color(mutedValue);
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

    // Batch 1 additions.
    _primaryGradientEnabled = prefs.getBool(_primaryGradientEnabledKey) ?? false;
    final primaryGradEndValue = prefs.getInt(_primaryGradientEndKey);
    if (primaryGradEndValue != null) _primaryGradientEnd = Color(primaryGradEndValue);
    _accentGradientEnabled = prefs.getBool(_accentGradientEnabledKey) ?? false;
    final accentGradEndValue = prefs.getInt(_accentGradientEndKey);
    if (accentGradEndValue != null) _accentGradientEnd = Color(accentGradEndValue);
    _shadowElevation = prefs.getDouble(_shadowElevationKey) ?? 0.0;
    _cardDensityScale = prefs.getDouble(_cardDensityScaleKey) ?? 1.0;
    final transitionIndex = prefs.getInt(_pageTransitionKey);
    if (transitionIndex != null && transitionIndex < PageTransitionStyle.values.length) {
      _pageTransitionStyle = PageTransitionStyle.values[transitionIndex];
    }
    _reduceMotion = prefs.getBool(_reduceMotionKey) ?? false;
    _backdropBlurIntensity = prefs.getDouble(_backdropBlurIntensityKey) ?? 0.0;
    final layoutIndex = prefs.getInt(_cardLayoutStyleKey);
    if (layoutIndex != null && layoutIndex < CardLayoutStyle.values.length) {
      _cardLayoutStyle = CardLayoutStyle.values[layoutIndex];
    }
    _autoDarkMode = prefs.getBool(_autoDarkModeKey) ?? false;
    _accessibilityFontScale = prefs.getDouble(_accessibilityFontScaleKey) ?? 1.0;
    _highContrastMode = prefs.getBool(_highContrastModeKey) ?? false;
    _letterSpacing = prefs.getDouble(_letterSpacingKey) ?? 0.0;
    final weightIndex = prefs.getInt(_fontWeightChoiceKey);
    if (weightIndex != null && weightIndex < FontWeightChoice.values.length) {
      _fontWeightChoice = FontWeightChoice.values[weightIndex];
    }

    // Theme Engine v2.
    final bgOverride = prefs.getInt(_backgroundOverrideKey);
    if (bgOverride != null) _backgroundOverride = Color(bgOverride);
    final surfOverride = prefs.getInt(_surfaceOverrideKey);
    if (surfOverride != null) _surfaceOverride = Color(surfOverride);
    final appBarOverride = prefs.getInt(_appBarOverrideKey);
    if (appBarOverride != null) _appBarOverride = Color(appBarOverride);
    _tonalSaturationBoost = prefs.getDouble(_saturationBoostKey) ?? 1.0;

    // Theme Engine v3.
    _auroraBackdropEnabled = prefs.getBool(_auroraEnabledKey) ?? false;
    _auroraIntensity = prefs.getDouble(_auroraIntensityKey) ?? 0.85;

    // Theme Engine v3 -- local branding assets.
    _customBackgroundImagePath = prefs.getString(_customBackgroundPathKey);
    _customLogoPath = prefs.getString(_customLogoPathKey);
    final logoPosIndex = prefs.getInt(_logoPositionKey);
    if (logoPosIndex != null && logoPosIndex < LogoPosition.values.length) {
      _logoPosition = LogoPosition.values[logoPosIndex];
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

  Future<void> setSuccessColor(Color c) async {
    _successColor = c;
    notifyListeners();
    (await SharedPreferences.getInstance()).setInt(_successKey, c.value);
  }

  Future<void> setWarningColor(Color c) async {
    _warningColor = c;
    notifyListeners();
    (await SharedPreferences.getInstance()).setInt(_warningKey, c.value);
  }

  Future<void> setDangerColor(Color c) async {
    _dangerColor = c;
    notifyListeners();
    (await SharedPreferences.getInstance()).setInt(_dangerKey, c.value);
  }

  Future<void> setMutedColor(Color c) async {
    _mutedColor = c;
    notifyListeners();
    (await SharedPreferences.getInstance()).setInt(_mutedKey, c.value);
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

  // Batch 1 setters -- same pattern as every setter above: update the
  // in-memory value and notify first (so UI feels instant), persist after.
  Future<void> setPrimaryGradientEnabled(bool v) async {
    _primaryGradientEnabled = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_primaryGradientEnabledKey, v);
  }

  Future<void> setPrimaryGradientEnd(Color? v) async {
    _primaryGradientEnd = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (v == null) {
      await prefs.remove(_primaryGradientEndKey);
    } else {
      await prefs.setInt(_primaryGradientEndKey, v.value);
    }
  }

  Future<void> setAccentGradientEnabled(bool v) async {
    _accentGradientEnabled = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_accentGradientEnabledKey, v);
  }

  Future<void> setAccentGradientEnd(Color? v) async {
    _accentGradientEnd = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (v == null) {
      await prefs.remove(_accentGradientEndKey);
    } else {
      await prefs.setInt(_accentGradientEndKey, v.value);
    }
  }

  Future<void> setShadowElevation(double v) async {
    _shadowElevation = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setDouble(_shadowElevationKey, v);
  }

  Future<void> setCardDensityScale(double v) async {
    _cardDensityScale = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setDouble(_cardDensityScaleKey, v);
  }

  Future<void> setPageTransitionStyle(PageTransitionStyle v) async {
    _pageTransitionStyle = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setInt(_pageTransitionKey, v.index);
  }

  Future<void> setReduceMotion(bool v) async {
    _reduceMotion = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_reduceMotionKey, v);
  }

  Future<void> setBackdropBlurIntensity(double v) async {
    _backdropBlurIntensity = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setDouble(_backdropBlurIntensityKey, v);
  }

  Future<void> setCardLayoutStyle(CardLayoutStyle v) async {
    _cardLayoutStyle = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setInt(_cardLayoutStyleKey, v.index);
  }

  Future<void> setAutoDarkMode(bool v) async {
    _autoDarkMode = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_autoDarkModeKey, v);
  }

  Future<void> setAccessibilityFontScale(double v) async {
    _accessibilityFontScale = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setDouble(_accessibilityFontScaleKey, v);
  }

  Future<void> setHighContrastMode(bool v) async {
    _highContrastMode = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_highContrastModeKey, v);
  }

  Future<void> setLetterSpacing(double v) async {
    _letterSpacing = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setDouble(_letterSpacingKey, v);
  }

  Future<void> setFontWeightChoice(FontWeightChoice v) async {
    _fontWeightChoice = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setInt(_fontWeightChoiceKey, v.index);
  }

  // Theme Engine v2 setters. All three overrides accept null to clear
  // back to "auto-derive from primaryColor" -- clearing is a real,
  // supported action, not just an unreachable default.
  Future<void> setBackgroundOverride(Color? v) async {
    _backgroundOverride = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (v == null) {
      await prefs.remove(_backgroundOverrideKey);
    } else {
      await prefs.setInt(_backgroundOverrideKey, v.value);
    }
  }

  Future<void> setSurfaceOverride(Color? v) async {
    _surfaceOverride = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (v == null) {
      await prefs.remove(_surfaceOverrideKey);
    } else {
      await prefs.setInt(_surfaceOverrideKey, v.value);
    }
  }

  Future<void> setAppBarOverride(Color? v) async {
    _appBarOverride = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (v == null) {
      await prefs.remove(_appBarOverrideKey);
    } else {
      await prefs.setInt(_appBarOverrideKey, v.value);
    }
  }

  Future<void> setTonalSaturationBoost(double v) async {
    _tonalSaturationBoost = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setDouble(_saturationBoostKey, v);
  }

  /// Applies every value from a curated preset at once — the "quick pick"
  /// path, still fully overridable afterward via the individual controls.
  // setGlassBlur is optional (nullable) so existing call sites don't
  // break; when provided, this is the fix for a real bug found in
  // review: backdropBlur was being stored on a preset and persisted,
  // but nothing in the actual render tree (GlassContainer/GlassButton)
  // ever read it -- they only read GlassSettings.blur, a separate,
  // pre-existing field. A template claiming "backdropBlur: 0.8" rendered
  // ZERO visible blur. This wires the preset's stated intent to the
  // mechanism that actually paints pixels, instead of leaving it as a
  // persisted number nothing consumes.
  Future<void> applyPreset(ThemePreset preset, GlassSetter setGlassEnabled, [Future<void> Function(double)? setGlassBlur]) async {
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
    // Batch 2: the first real consumer of Batch 1's gradient/backdrop-blur
    // fields. A preset with no gradientEnd explicitly turns gradient OFF
    // (not left alone) so switching from a gradient template to a flat
    // one doesn't leave a stale gradient behind.
    _primaryGradientEnabled = preset.gradientEnd != null;
    _primaryGradientEnd = preset.gradientEnd;
    _backdropBlurIntensity = preset.backdropBlur;
    _tonalSaturationBoost = preset.tonalSaturationBoost;
    _borderThickness = preset.borderThickness;
    // Applying a curated template is a "start fresh" action -- any
    // manual background/surface/appbar override from a previous custom
    // tweak session would otherwise silently fight the new template's
    // own tonal design, which defeats the point of picking a template.
    _backgroundOverride = null;
    _surfaceOverride = null;
    _appBarOverride = null;
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
      prefs.setBool(_primaryGradientEnabledKey, preset.gradientEnd != null),
      if (preset.gradientEnd != null) prefs.setInt(_primaryGradientEndKey, preset.gradientEnd!.value)
      else prefs.remove(_primaryGradientEndKey),
      prefs.setDouble(_backdropBlurIntensityKey, preset.backdropBlur),
      prefs.setDouble(_saturationBoostKey, preset.tonalSaturationBoost),
      prefs.setDouble(_borderThicknessKey, preset.borderThickness),
      prefs.remove(_backgroundOverrideKey),
      prefs.remove(_surfaceOverrideKey),
      prefs.remove(_appBarOverrideKey),
    ]);
    setGlassEnabled(preset.styleMode == UIStyleMode.glass || preset.styleMode == UIStyleMode.liquid);
    // The actual fix: map backdropBlur's 0.0-1.0 scale onto
    // GlassSettings' real 4-30 pixel blur range (matching the existing
    // "Blur Intensity" slider's own range) and apply it for real.
    if (setGlassBlur != null && preset.backdropBlur > 0) {
      await setGlassBlur(4.0 + preset.backdropBlur * 26.0);
    }
  }

  /// Applies a theme generated by the AI Design Engine (backend
  /// POST /ai/generate-theme) -- same effect as applyPreset, but built
  /// from a runtime JSON map instead of a compile-time ThemePreset.
  Future<void> applyGeneratedTheme(Map<String, dynamic> theme, GlassSetter setGlassEnabled, [Future<void> Function(double)? setGlassBlur]) async {
    Color parseHex(String? hex, Color fallback) {
      if (hex == null) return fallback;
      try {
        final clean = hex.replaceFirst('#', '');
        return Color(int.parse('FF$clean', radix: 16));
      } catch (_) {
        return fallback;
      }
    }

    _primaryColor = parseHex(theme['primary'] as String?, _primaryColor);
    _accentColor = parseHex(theme['accent'] as String?, _accentColor);
    // Optional in the AI payload — a generated theme that only sets
    // primary/accent leaves the semantic colours untouched rather than
    // resetting them to defaults.
    _successColor = parseHex(theme['success'] as String?, _successColor);
    _warningColor = parseHex(theme['warning'] as String?, _warningColor);
    _dangerColor = parseHex(theme['danger'] as String?, _dangerColor);
    _mutedColor = parseHex(theme['muted'] as String?, _mutedColor);
    _fontPairing = FontPairing.values.firstWhere(
      (f) => f.name == theme['font'],
      orElse: () => FontPairing.spaceGroteskInter,
    );
    _cornerRadius = ((theme['radius'] as num?)?.toDouble() ?? _cornerRadius).clamp(0.0, 32.0);
    _darkMode = theme['dark'] as bool? ?? _darkMode;
    _styleMode = UIStyleMode.values.firstWhere(
      (m) => m.name == theme['styleMode'],
      orElse: () => UIStyleMode.solid,
    );
    _glowEnabled = theme['glow'] as bool? ?? false;
    if (theme['glowColor'] != null) {
      _glowColor = parseHex(theme['glowColor'] as String?, _glowColor);
    }
    _floatingEnabled = theme['floating'] as bool? ?? false;
    _textureEnabled = theme['texture'] as bool? ?? false;
    // Batch 5: AI-generated themes can now use a primary-color gradient
    // and backdrop blur for glass/liquid moods, same fields a static
    // preset can set (see ThemePreset.gradientEnd/backdropBlur).
    _primaryGradientEnabled = theme['gradientEnd'] != null;
    _primaryGradientEnd = theme['gradientEnd'] != null ? parseHex(theme['gradientEnd'] as String?, _primaryColor) : null;
    _backdropBlurIntensity = ((theme['backdropBlur'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 1.0);
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setInt(_primaryKey, _primaryColor.value),
      prefs.setInt(_accentKey, _accentColor.value),
      prefs.setInt(_fontKey, _fontPairing.index),
      prefs.setDouble(_radiusKey, _cornerRadius),
      prefs.setBool(_darkModeKey, _darkMode),
      prefs.setInt(_styleModeKey, _styleMode.index),
      prefs.setBool(_glowEnabledKey, _glowEnabled),
      prefs.setBool(_floatingEnabledKey, _floatingEnabled),
      prefs.setBool(_textureKey, _textureEnabled),
      prefs.setInt(_glowColorKey, _glowColor.value),
      prefs.setInt(_successKey, _successColor.value),
      prefs.setInt(_warningKey, _warningColor.value),
      prefs.setInt(_dangerKey, _dangerColor.value),
      prefs.setInt(_mutedKey, _mutedColor.value),
      prefs.setBool(_primaryGradientEnabledKey, _primaryGradientEnabled),
      if (_primaryGradientEnd != null) prefs.setInt(_primaryGradientEndKey, _primaryGradientEnd!.value)
      else prefs.remove(_primaryGradientEndKey),
      prefs.setDouble(_backdropBlurIntensityKey, _backdropBlurIntensity),
    ]);
    setGlassEnabled(_styleMode == UIStyleMode.glass || _styleMode == UIStyleMode.liquid);
    if (setGlassBlur != null && _backdropBlurIntensity > 0) {
      await setGlassBlur(4.0 + _backdropBlurIntensity * 26.0);
    }
  }

  Future<void> resetToDefaults() async {
    _primaryColor = const Color(0xFF1B2A4A);
    _accentColor = const Color(0xFFE8A33D);
    _successColor = const Color(0xFF2E9E6D);
    _warningColor = const Color(0xFFE8A33D);
    _dangerColor = const Color(0xFFE85D4E);
    _mutedColor = const Color(0xFF5B6478);
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
    // Batch 1 additions.
    _primaryGradientEnabled = false;
    _primaryGradientEnd = null;
    _accentGradientEnabled = false;
    _accentGradientEnd = null;
    _shadowElevation = 0.0;
    _cardDensityScale = 1.0;
    _pageTransitionStyle = PageTransitionStyle.slide;
    _reduceMotion = false;
    _backdropBlurIntensity = 0.0;
    _cardLayoutStyle = CardLayoutStyle.list;
    _autoDarkMode = false;
    _accessibilityFontScale = 1.0;
    _highContrastMode = false;
    _letterSpacing = 0.0;
    _fontWeightChoice = FontWeightChoice.regular;
    // Theme Engine v2.
    _backgroundOverride = null;
    _surfaceOverride = null;
    _appBarOverride = null;
    _tonalSaturationBoost = 1.0;
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
      prefs.remove(_successKey),
      prefs.remove(_warningKey),
      prefs.remove(_dangerKey),
      prefs.remove(_mutedKey),
      // Batch 1 additions.
      prefs.remove(_primaryGradientEnabledKey),
      prefs.remove(_primaryGradientEndKey),
      prefs.remove(_accentGradientEnabledKey),
      prefs.remove(_accentGradientEndKey),
      prefs.remove(_shadowElevationKey),
      prefs.remove(_cardDensityScaleKey),
      prefs.remove(_pageTransitionKey),
      prefs.remove(_reduceMotionKey),
      prefs.remove(_backdropBlurIntensityKey),
      prefs.remove(_cardLayoutStyleKey),
      prefs.remove(_autoDarkModeKey),
      prefs.remove(_accessibilityFontScaleKey),
      prefs.remove(_highContrastModeKey),
      prefs.remove(_letterSpacingKey),
      prefs.remove(_fontWeightChoiceKey),
      // Theme Engine v2.
      prefs.remove(_backgroundOverrideKey),
      prefs.remove(_surfaceOverrideKey),
      prefs.remove(_appBarOverrideKey),
      prefs.remove(_saturationBoostKey),
    ]);
  }
}
