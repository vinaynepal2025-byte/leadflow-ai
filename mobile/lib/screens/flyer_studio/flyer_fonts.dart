// flyer_fonts.dart — single source of truth for every font Flyer/Logo
// Studio can use, replacing two previously-separate, easily-drifting
// lists (kFlyerFontFamilies used to live in flyer_element.dart,
// kLogoFontOptions in generate_logo_screen.dart — see
// LOGO_STUDIO_ARCHITECTURE.md Phase 4).
//
// Two rendering pipelines need fonts here, and they don't speak the same
// family-name dialect, which is *why* there were two lists in the first
// place — this file doesn't pretend that difference away, it names it:
// - The freeform canvas (FlyerStudioScreen) renders text on-device via
//   Flutter's own font registration (pubspec.yaml `flutter.fonts`, e.g.
//   family "SpaceGrotesk", no space) and exports client-side, so every
//   bundled Flutter font works there.
// - GenerateLogoScreen's parametric templates render server-side
//   (backend/services/logoTemplates.js -> sharp/librsvg), which only
//   knows the fonts backend/services/fontSetup.js registered with
//   fontconfig under ITS OWN family strings (e.g. "Space Grotesk", with
//   a space) — a font missing from that registration silently falls
//   back to a system default there instead of erroring.
//
// backendFamily is null for a font that's canvas-only (Inter and Roboto
// are bundled in the app but not registered server-side).
class FlyerFontOption {
  final String flutterFamily;
  final String? backendFamily;
  final String label;

  const FlyerFontOption({
    required this.flutterFamily,
    required this.label,
    this.backendFamily,
  });
}

const List<FlyerFontOption> kFlyerFontOptions = [
  FlyerFontOption(
      flutterFamily: 'SpaceGrotesk', backendFamily: 'Space Grotesk', label: 'Space Grotesk'),
  FlyerFontOption(flutterFamily: 'Inter', label: 'Inter'),
  FlyerFontOption(
      flutterFamily: 'PlayfairDisplay', backendFamily: 'Playfair Display', label: 'Playfair Display'),
  FlyerFontOption(flutterFamily: 'Lato', backendFamily: 'Lato', label: 'Lato'),
  FlyerFontOption(flutterFamily: 'Poppins', backendFamily: 'Poppins', label: 'Poppins'),
  FlyerFontOption(flutterFamily: 'Roboto', label: 'Roboto'),
  FlyerFontOption(flutterFamily: 'Montserrat', backendFamily: 'Montserrat', label: 'Montserrat'),
  FlyerFontOption(flutterFamily: 'OpenSans', backendFamily: 'Open Sans', label: 'Open Sans'),
];

/// The subset usable by server-rendered templates (GenerateLogoScreen) —
/// anything with a null backendFamily would silently mis-render there.
List<FlyerFontOption> get kBackendFontOptions =>
    kFlyerFontOptions.where((f) => f.backendFamily != null).toList();

/// Plain Flutter-family-name list, for canvas code that just wants every
/// usable `fontFamily` string (e.g. the freeform-canvas text picker).
List<String> get kFlyerFontFamilies => kFlyerFontOptions.map((f) => f.flutterFamily).toList();
