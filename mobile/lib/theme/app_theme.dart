import 'package:flutter/material.dart';
import 'appearance_settings.dart';
import 'tonal_palette.dart';

/// Original LeadFlow AI identity colors — used as sensible defaults and
/// wherever a fixed semantic color (success/alert) still makes sense
/// regardless of the user's custom primary/accent choice.
class AppColors {
  static const inkNavy = Color(0xFF1B2A4A);
  static const inkNavyLight = Color(0xFF2E4270);
  static const signalAmber = Color(0xFFE8A33D);
  static const paper = Color(0xFFF7F8FA);
  static const slate = Color(0xFF5B6478);
  static const successGreen = Color(0xFF2E9E6D);
  static const coralAlert = Color(0xFFE85D4E);
  static const cardWhite = Color(0xFFFFFFFF);
}

Color stageColorFor(String stage) {
  final lower = stage.toLowerCase();
  if (lower.contains('admission') || lower.contains('accept')) return AppColors.successGreen;
  if (lower.contains('lost') || lower.contains('reject')) return AppColors.coralAlert;
  if (lower.contains('closed')) return const Color(0xFF6B7FA8);
  if (lower.contains('counsel')) return AppColors.signalAmber;
  if (lower.contains('contact')) return const Color(0xFF4C7A9E);
  return AppColors.slate;
}

class _FontPair {
  final TextTheme Function() display;
  final TextTheme Function() body;
  final TextStyle Function({double? fontSize, FontWeight? fontWeight, Color? color}) headingStyle;
  const _FontPair(this.display, this.body, this.headingStyle);
}

// Bundled TTF assets (assets/fonts/, declared in pubspec.yaml) — real,
// distinct, premium typefaces instead of generic Android system fonts.
// Still zero network dependency (fonts ship inside the APK), so this
// keeps the earlier crash-fix property: no dependency on fonts.gstatic.com
// or any host being reachable at startup.
TextTheme _themeWithFamily(String family) => Typography.material2021(platform: TargetPlatform.android)
    .black
    .apply(fontFamily: family);

// Batch 4: applies letterSpacing + a font-weight nudge across every slot
// in a TextTheme. Deliberately plain .copyWith() calls (TextTheme/
// TextStyle.copyWith is long-standing, stable API already used elsewhere
// in this file) rather than TextTheme.apply(), since apply()'s parameter
// list doesn't include letterSpacing/fontWeight and guessing at an API
// this sandbox has no compiler to check against isn't worth the risk.
// letterSpacing:0.0 and FontWeightChoice.regular are Batch 1's defaults,
// and both are no-ops here, so this is invisible until someone actually
// touches the new controls.
TextTheme _tuneTextTheme(TextTheme t, double letterSpacing, FontWeightChoice weightChoice) {
  TextStyle? tune(TextStyle? s) {
    if (s == null) return s;
    return s.copyWith(
      letterSpacing: letterSpacing,
      fontWeight: weightChoice == FontWeightChoice.regular ? s.fontWeight : weightChoice.weight,
    );
  }

  return t.copyWith(
    displayLarge: tune(t.displayLarge), displayMedium: tune(t.displayMedium), displaySmall: tune(t.displaySmall),
    headlineLarge: tune(t.headlineLarge), headlineMedium: tune(t.headlineMedium), headlineSmall: tune(t.headlineSmall),
    titleLarge: tune(t.titleLarge), titleMedium: tune(t.titleMedium), titleSmall: tune(t.titleSmall),
    bodyLarge: tune(t.bodyLarge), bodyMedium: tune(t.bodyMedium), bodySmall: tune(t.bodySmall),
    labelLarge: tune(t.labelLarge), labelMedium: tune(t.labelMedium), labelSmall: tune(t.labelSmall),
  );
}

_FontPair _resolveFontPair(FontPairing pairing) {
  switch (pairing) {
    case FontPairing.playfairLato:
      return _FontPair(
        () => _themeWithFamily('PlayfairDisplay'),
        () => _themeWithFamily('Lato'),
        ({fontSize, fontWeight, color}) => TextStyle(fontFamily: 'PlayfairDisplay', fontSize: fontSize, fontWeight: fontWeight, color: color),
      );
    case FontPairing.poppinsRoboto:
      return _FontPair(
        () => _themeWithFamily('Poppins'),
        () => _themeWithFamily('Roboto'),
        ({fontSize, fontWeight, color}) => TextStyle(fontFamily: 'Poppins', fontSize: fontSize, fontWeight: fontWeight, color: color),
      );
    case FontPairing.montserratOpenSans:
      return _FontPair(
        () => _themeWithFamily('Montserrat'),
        () => _themeWithFamily('OpenSans'),
        ({fontSize, fontWeight, color}) => TextStyle(fontFamily: 'Montserrat', fontSize: fontSize, fontWeight: fontWeight, color: color),
      );
    case FontPairing.spaceGroteskInter:
      return _FontPair(
        () => _themeWithFamily('SpaceGrotesk'),
        () => _themeWithFamily('Inter'),
        ({fontSize, fontWeight, color}) => TextStyle(fontFamily: 'SpaceGrotesk', fontSize: fontSize, fontWeight: fontWeight, color: color),
      );
    // Batch 4 additions -- same recombination approach as the enum
    // comment explains: existing bundled families only.
    case FontPairing.interRoboto:
      return _FontPair(
        () => _themeWithFamily('Inter'),
        () => _themeWithFamily('Roboto'),
        ({fontSize, fontWeight, color}) => TextStyle(fontFamily: 'Inter', fontSize: fontSize, fontWeight: fontWeight, color: color),
      );
    case FontPairing.playfairOpenSans:
      return _FontPair(
        () => _themeWithFamily('PlayfairDisplay'),
        () => _themeWithFamily('OpenSans'),
        ({fontSize, fontWeight, color}) => TextStyle(fontFamily: 'PlayfairDisplay', fontSize: fontSize, fontWeight: fontWeight, color: color),
      );
    case FontPairing.spaceGroteskLato:
      return _FontPair(
        () => _themeWithFamily('SpaceGrotesk'),
        () => _themeWithFamily('Lato'),
        ({fontSize, fontWeight, color}) => TextStyle(fontFamily: 'SpaceGrotesk', fontSize: fontSize, fontWeight: fontWeight, color: color),
      );
    case FontPairing.montserratInter:
      return _FontPair(
        () => _themeWithFamily('Montserrat'),
        () => _themeWithFamily('Inter'),
        ({fontSize, fontWeight, color}) => TextStyle(fontFamily: 'Montserrat', fontSize: fontSize, fontWeight: fontWeight, color: color),
      );
    case FontPairing.poppinsOpenSans:
      return _FontPair(
        () => _themeWithFamily('Poppins'),
        () => _themeWithFamily('OpenSans'),
        ({fontSize, fontWeight, color}) => TextStyle(fontFamily: 'Poppins', fontSize: fontSize, fontWeight: fontWeight, color: color),
      );
    case FontPairing.interLato:
      return _FontPair(
        () => _themeWithFamily('Inter'),
        () => _themeWithFamily('Lato'),
        ({fontSize, fontWeight, color}) => TextStyle(fontFamily: 'Inter', fontSize: fontSize, fontWeight: fontWeight, color: color),
      );
  }
}

/// The per-mode "recipe" — how opaque the fill is, how strong the border
/// is, and how much shadow to use. Every mode is then further modulated
/// by the user's own borderThickness/componentOpacity sliders, so this is
/// a starting point, not a fixed look.
class _ModeRecipe {
  final double fillAlpha;      // 0 = invisible fill, 1 = fully opaque
  final double borderAlpha;
  final double borderWidthBase;
  final double elevation;
  final bool whiteTint;        // true = frosted-white fill (glass/liquid), false = brand-colored fill
  final bool hardBorder;       // true = solid dark/primary border (cartoon), not a soft tint
  const _ModeRecipe(this.fillAlpha, this.borderAlpha, this.borderWidthBase, this.elevation, this.whiteTint, this.hardBorder);
}

_ModeRecipe _recipeFor(UIStyleMode mode) {
  switch (mode) {
    case UIStyleMode.solid:
      return const _ModeRecipe(1.0, 0.06, 1.0, 2, false, false);
    case UIStyleMode.glass:
      return const _ModeRecipe(0.5, 0.6, 1.1, 0, true, false);
    case UIStyleMode.liquid:
      return const _ModeRecipe(0.45, 0.7, 1.0, 0, true, false);
    case UIStyleMode.transparent:
      return const _ModeRecipe(0.05, 0.5, 1.2, 0, false, false);
    case UIStyleMode.basic:
      return const _ModeRecipe(1.0, 0.0, 0.0, 0, false, false);
    case UIStyleMode.cartoon:
      return const _ModeRecipe(1.0, 1.0, 2.2, 6, false, true);
    case UIStyleMode.corporate:
      return const _ModeRecipe(1.0, 0.18, 0.8, 1, false, false);
  }
}

class AppTheme {
  static CardThemeData _cardThemeFrom(AppearanceSettings settings, BorderRadius radius, bool isDark, Color surfaceLowColor) {
    final recipe = _recipeFor(settings.styleMode);
    final baseCardColor = surfaceLowColor;
    final fillAlpha = (recipe.fillAlpha * settings.componentOpacity).clamp(0.0, 1.0);

    final fillColor = recipe.whiteTint
        ? Colors.white.withValues(alpha: fillAlpha)
        : (recipe.fillAlpha >= 0.99 ? baseCardColor : baseCardColor.withValues(alpha: fillAlpha));

    final borderColor = settings.outlineColor ??
        (recipe.hardBorder ? (isDark ? Colors.white : settings.primaryColor) : (recipe.whiteTint ? Colors.white : settings.primaryColor));

    final edgeSoftenFactor = (1 - (settings.edgeBlur / 14)).clamp(0.15, 1.0);
    final effectiveBorderAlpha = recipe.borderAlpha * edgeSoftenFactor;
    final effectiveBorderWidth = recipe.borderWidthBase * settings.borderThickness + settings.edgeBlur * 0.25;

    final glowShadow = settings.glowEnabled
        ? settings.glowColor
        : (recipe.hardBorder ? Colors.black.withValues(alpha: 0.4) : settings.primaryColor.withValues(alpha: 0.25));
    var glowElevation = settings.glowEnabled ? 4 + settings.glowIntensity * 14 : recipe.elevation;
    if (settings.floatingEnabled) glowElevation += 3 + settings.floatingIntensity * 10;

    return CardThemeData(
      elevation: glowElevation,
      shadowColor: glowShadow,
      color: fillColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: effectiveBorderAlpha <= 0.02
            ? BorderSide.none
            : BorderSide(
                color: borderColor.withValues(alpha: effectiveBorderAlpha),
                width: effectiveBorderWidth,
              ),
      ),
    );
  }

  static ButtonStyle _filledButtonStyleFrom(AppearanceSettings settings, _FontPair pair, TextTheme bodyFont, bool isDark) {
    final recipe = _recipeFor(settings.styleMode);
    final fillAlpha = (recipe.fillAlpha * settings.componentOpacity).clamp(0.0, 1.0);
    final fillColor = recipe.whiteTint
        ? Colors.white.withValues(alpha: fillAlpha)
        : settings.primaryColor.withValues(alpha: fillAlpha.clamp(0.15, 1.0));
    final foreground = recipe.whiteTint
        ? (isDark ? Colors.white : settings.primaryColor)
        : (recipe.fillAlpha >= 0.99 ? Colors.white : settings.primaryColor);
    final borderColor = settings.outlineColor ?? (recipe.hardBorder ? (isDark ? Colors.white : Colors.black) : (recipe.whiteTint ? Colors.white : settings.primaryColor));
    final glowColor = settings.glowEnabled ? settings.glowColor : null;
    double? glowElevation = settings.glowEnabled ? 3 + settings.glowIntensity * 12 : (recipe.elevation > 0 ? recipe.elevation : null);
    if (settings.floatingEnabled) glowElevation = (glowElevation ?? 0) + 2 + settings.floatingIntensity * 8;

    return FilledButton.styleFrom(
      backgroundColor: fillColor,
      foregroundColor: foreground,
      elevation: glowElevation,
      shadowColor: glowColor,
      side: recipe.borderAlpha == 0
          ? null
          : BorderSide(color: borderColor.withValues(alpha: recipe.borderAlpha), width: recipe.borderWidthBase * settings.borderThickness),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(settings.cornerRadius * 0.75)),
      padding: EdgeInsets.symmetric(vertical: 14 * settings.componentScale, horizontal: 20 * settings.componentScale),
      textStyle: TextStyle(fontFamily: bodyFont.bodyLarge?.fontFamily, fontWeight: FontWeight.w600),
    );
  }

  static ThemeData build(AppearanceSettings settings, {required Brightness brightness}) {
    final isDark = brightness == Brightness.dark;
    final pair = _resolveFontPair(settings.fontPairing);
    final isGlassy = settings.isGlassy;

    // Theme Engine v2 -- the actual fix for "every dark theme looks the
    // same flat grey app." tonal.background/surfaceLow/surfaceHigh are
    // derived FROM this theme's own primaryColor via HSL (see
    // tonal_palette.dart) instead of being the same hardcoded constant
    // for every theme regardless of its hue. Each of the three can still
    // be manually overridden independently (Vinay's "section-wise, not
    // one background flooding everything" ask) via
    // settings.backgroundOverride/surfaceOverride/appBarOverride; when
    // null (the default), it auto-derives.
    final tonal = deriveTonalPalette(settings.primaryColor, isDark, saturationBoost: settings.tonalSaturationBoost);
    final bgColor = settings.backgroundOverride ?? tonal.background;
    final surfaceLowColor = settings.surfaceOverride ?? tonal.surfaceLow;
    final surfaceHighColor = tonal.surfaceHigh;
    final appBarColor = settings.appBarOverride ?? bgColor;

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      visualDensity: VisualDensity(horizontal: settings.density.value, vertical: settings.density.value),
      colorScheme: ColorScheme.fromSeed(
        seedColor: settings.primaryColor,
        primary: settings.primaryColor,
        secondary: settings.accentColor,
        brightness: brightness,
      ),
      scaffoldBackgroundColor: isGlassy ? Colors.transparent : bgColor,
    );

    final radius = BorderRadius.circular(settings.cornerRadius);
    final displayFont = _tuneTextTheme(pair.display(), settings.letterSpacing, settings.fontWeightChoice);
    final bodyFont = _tuneTextTheme(pair.body(), settings.letterSpacing, settings.fontWeightChoice);
    final textColor = isDark ? Colors.white : settings.primaryColor;
    final onGlassColor = isDark ? Colors.white : settings.primaryColor;

    return base.copyWith(
      textTheme: bodyFont.copyWith(
        headlineLarge: displayFont.headlineLarge?.copyWith(fontWeight: FontWeight.w700, color: textColor),
        headlineMedium: displayFont.headlineMedium?.copyWith(fontWeight: FontWeight.w700, color: textColor),
        titleLarge: displayFont.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: textColor),
        titleMedium: displayFont.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: textColor),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: isGlassy ? Colors.transparent : appBarColor,
        foregroundColor: isGlassy ? onGlassColor : textColor,
        titleTextStyle: pair.headingStyle(fontSize: 20, fontWeight: FontWeight.w700, color: isGlassy ? onGlassColor : textColor),
      ),
      cardTheme: _cardThemeFrom(settings, radius, isDark, surfaceLowColor),
      filledButtonTheme: FilledButtonThemeData(style: _filledButtonStyleFrom(settings, pair, bodyFont, isDark)),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: settings.primaryColor,
          side: BorderSide(color: (settings.outlineColor ?? settings.primaryColor).withValues(alpha: settings.outlineColor != null ? 1.0 : 0.3), width: settings.borderThickness),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(settings.cornerRadius * 0.75)),
          padding: EdgeInsets.symmetric(vertical: 12 * settings.componentScale, horizontal: 18 * settings.componentScale),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isGlassy ? Colors.white.withValues(alpha: isDark ? 0.06 : 0.4) : surfaceLowColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(settings.cornerRadius * 0.75),
          borderSide: BorderSide(color: isGlassy ? Colors.white.withValues(alpha: 0.4) : settings.primaryColor.withValues(alpha: 0.12)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(settings.cornerRadius * 0.75),
          borderSide: BorderSide(color: isGlassy ? Colors.white.withValues(alpha: 0.4) : settings.primaryColor.withValues(alpha: 0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(settings.cornerRadius * 0.75),
          borderSide: BorderSide(color: settings.primaryColor, width: 1.5),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        // Genuinely distinct from cards now (surfaceHigh, not
        // surfaceLow) -- fixes review feedback that nav/tabs read as
        // generically identical to every other surface instead of their
        // own layered zone, the way premium apps (Instagram, X) keep
        // their bottom bar visually separated from card content.
        backgroundColor: isGlassy ? Colors.transparent : surfaceHighColor,
        indicatorColor: settings.accentColor.withValues(alpha: 0.25),
        labelTextStyle: WidgetStateProperty.all(
          TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isGlassy ? onGlassColor : textColor, fontFamily: bodyFont.bodyLarge?.fontFamily),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: isGlassy ? Colors.white.withValues(alpha: isDark ? 0.08 : 0.4) : surfaceLowColor,
        side: BorderSide(color: isGlassy ? Colors.white.withValues(alpha: 0.4) : settings.primaryColor.withValues(alpha: 0.1)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isGlassy
            ? surfaceLowColor.withValues(alpha: isDark ? 0.9 : 0.92)
            : surfaceLowColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(settings.cornerRadius)),
        titleTextStyle: pair.headingStyle(fontSize: 18, fontWeight: FontWeight.w700, color: textColor),
        contentTextStyle: bodyFont.bodyMedium,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: settings.primaryColor,
        foregroundColor: Colors.white,
        elevation: settings.floatingEnabled ? 6 + settings.floatingIntensity * 8 : 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(settings.cornerRadius * 0.85)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? surfaceHighColor : settings.primaryColor,
        contentTextStyle: bodyFont.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(settings.cornerRadius * 0.6)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
