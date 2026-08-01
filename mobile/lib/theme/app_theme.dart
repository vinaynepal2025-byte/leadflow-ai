import 'package:flutter/material.dart';
import 'appearance_settings.dart';

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

// Uses the device's own built-in system font families instead of
// downloading fonts over the network — this removes any dependency on
// internet access or a specific DNS/host being reachable at startup,
// which previously caused a hard crash whenever fonts.gstatic.com
// couldn't be resolved. Each pairing still reads as visually distinct
// via the different generic system families Android ships with.
TextTheme _themeWithFamily(String family) => Typography.material2021(platform: TargetPlatform.android)
    .black
    .apply(fontFamily: family);

_FontPair _resolveFontPair(FontPairing pairing) {
  switch (pairing) {
    case FontPairing.playfairLato:
      return _FontPair(
        () => _themeWithFamily('serif'),
        () => _themeWithFamily('serif'),
        ({fontSize, fontWeight, color}) => TextStyle(fontFamily: 'serif', fontSize: fontSize, fontWeight: fontWeight, color: color),
      );
    case FontPairing.poppinsRoboto:
      return _FontPair(
        () => _themeWithFamily('sans-serif-medium'),
        () => _themeWithFamily('sans-serif'),
        ({fontSize, fontWeight, color}) => TextStyle(fontFamily: 'sans-serif-medium', fontSize: fontSize, fontWeight: fontWeight, color: color),
      );
    case FontPairing.montserratOpenSans:
      return _FontPair(
        () => _themeWithFamily('sans-serif-condensed'),
        () => _themeWithFamily('sans-serif'),
        ({fontSize, fontWeight, color}) => TextStyle(fontFamily: 'sans-serif-condensed', fontSize: fontSize, fontWeight: fontWeight, color: color),
      );
    case FontPairing.spaceGroteskInter:
      return _FontPair(
        () => _themeWithFamily('sans-serif'),
        () => _themeWithFamily('sans-serif'),
        ({fontSize, fontWeight, color}) => TextStyle(fontFamily: 'sans-serif', fontSize: fontSize, fontWeight: fontWeight, color: color),
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
  static CardThemeData _cardThemeFrom(AppearanceSettings settings, BorderRadius radius, bool isDark) {
    final recipe = _recipeFor(settings.styleMode);
    final baseCardColor = isDark ? const Color(0xFF1E2230) : AppColors.cardWhite;
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
      scaffoldBackgroundColor: isGlassy ? Colors.transparent : (isDark ? const Color(0xFF14171F) : AppColors.paper),
    );

    final radius = BorderRadius.circular(settings.cornerRadius);
    final displayFont = pair.display();
    final bodyFont = pair.body();
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
        backgroundColor: isGlassy ? Colors.transparent : (isDark ? const Color(0xFF14171F) : AppColors.paper),
        foregroundColor: isGlassy ? onGlassColor : textColor,
        titleTextStyle: pair.headingStyle(fontSize: 20, fontWeight: FontWeight.w700, color: isGlassy ? onGlassColor : textColor),
      ),
      cardTheme: _cardThemeFrom(settings, radius, isDark),
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
        fillColor: isGlassy ? Colors.white.withValues(alpha: isDark ? 0.06 : 0.4) : (isDark ? const Color(0xFF1E2230) : AppColors.cardWhite),
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
        backgroundColor: isGlassy ? Colors.transparent : (isDark ? const Color(0xFF1E2230) : AppColors.cardWhite),
        indicatorColor: settings.accentColor.withValues(alpha: 0.25),
        labelTextStyle: WidgetStateProperty.all(
          TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isGlassy ? onGlassColor : textColor, fontFamily: bodyFont.bodyLarge?.fontFamily),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: isGlassy ? Colors.white.withValues(alpha: isDark ? 0.08 : 0.4) : (isDark ? const Color(0xFF1E2230) : AppColors.paper),
        side: BorderSide(color: isGlassy ? Colors.white.withValues(alpha: 0.4) : settings.primaryColor.withValues(alpha: 0.1)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isGlassy
            ? (isDark ? const Color(0xFF1E2230).withValues(alpha: 0.9) : Colors.white.withValues(alpha: 0.92))
            : (isDark ? const Color(0xFF1E2230) : AppColors.cardWhite),
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
        backgroundColor: isDark ? const Color(0xFF2E3546) : settings.primaryColor,
        contentTextStyle: bodyFont.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(settings.cornerRadius * 0.6)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
