import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../theme/glass_settings.dart';
import '../theme/appearance_settings.dart';

/// A genuine hard-edged "sticker" shadow — a solid offset shape behind the
/// content, zero blur — for Cartoon mode. Flutter's built-in Card/Button
/// elevation is always a soft, blurred shadow (a physical-light-source
/// simulation), which can't produce this crisp comic look no matter how
/// high the elevation is set. Used only in Cartoon mode.
Widget wrapWithHardShadow({required Widget child, required BorderRadius radius, required Color color, double offset = 5}) {
  return Stack(
    clipBehavior: Clip.none,
    children: [
      Positioned(
        top: offset, left: offset,
        right: -offset, bottom: -offset,
        child: DecoratedBox(decoration: BoxDecoration(color: color, borderRadius: radius)),
      ),
      child,
    ],
  );
}

/// A single directional shadow suitable for a bottom nav bar (glow above
/// it, or a neutral lift) — the nav-bar equivalent of the isotropic ring
/// used on cards/buttons, since a bar only has one edge that faces the
/// content above it.
BoxShadow? navBarGlowShadow(AppearanceSettings appearance) {
  if (appearance.glowEnabled) {
    final i = appearance.glowIntensity;
    return BoxShadow(color: appearance.glowColor.withValues(alpha: 0.35 * i), blurRadius: 14 + 16 * i, offset: Offset(0, -(2 + 4 * i)));
  }
  if (appearance.floatingEnabled) {
    final f = appearance.floatingIntensity;
    return BoxShadow(color: Colors.black.withValues(alpha: 0.15 * f), blurRadius: 8 + 12 * f, offset: Offset(0, -(1 + 3 * f)));
  }
  return null;
}

/// True isotropic glow — several layered shadows, all offset zero, growing
/// blur/shrinking opacity — reads as a genuine neon ring around the shape,
/// unlike Flutter's built-in elevation shadow (which is always directional).
List<BoxShadow> _neonGlowShadows(AppearanceSettings appearance) {
  final shadows = <BoxShadow>[];
  if (appearance.glowEnabled) {
    final c = appearance.glowColor;
    final i = appearance.glowIntensity; // 0..1
    shadows.addAll([
      BoxShadow(color: c.withValues(alpha: 0.55 * i), blurRadius: 6 + 6 * i, spreadRadius: 0.5),
      BoxShadow(color: c.withValues(alpha: 0.35 * i), blurRadius: 16 + 14 * i, spreadRadius: 1),
      BoxShadow(color: c.withValues(alpha: 0.18 * i), blurRadius: 30 + 26 * i, spreadRadius: 2),
    ]);
  }
  if (appearance.floatingEnabled) {
    // Neutral (non-colored) lift — additive to any glow, so Floating
    // works the same whether Glow is on or off, and in every style mode
    // including Glass/Liquid, not just the theme-level fallback.
    final f = appearance.floatingIntensity;
    shadows.add(BoxShadow(color: Colors.black.withValues(alpha: 0.18 * f), blurRadius: 10 + 18 * f, offset: Offset(0, 4 + 6 * f)));
  }
  return shadows;
}

/// A soft, diffused edge — a low-opacity shadow that traces the shape at
/// short range, giving the boundary itself a blurred/out-of-focus feel
/// distinct from corner rounding (which changes the shape, not the crispness
/// of its line).
List<BoxShadow> _edgeBlurShadows(AppearanceSettings appearance, Color borderColor) {
  if (appearance.edgeBlur <= 0) return const [];
  final b = appearance.edgeBlur; // 0..14
  return [
    BoxShadow(color: borderColor.withValues(alpha: 0.25), blurRadius: b, spreadRadius: -1),
  ];
}

/// A frosted-glass card: real backdrop blur over whatever sits behind it,
/// tinted with the user's chosen accent color, thin light border for the
/// "crystal edge" look. Falls back to a normal Card when Glass UI is off —
/// either way, Neon Glow and Edge Blur still apply, since those are
/// independent of the glass/liquid mode.
class GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;

  const GlassContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius,
    this.onTap,
  });

  Widget _wrapTappable(BuildContext context, Widget content, AppearanceSettings appearance, BorderRadius radius) {
    if (onTap == null) return content;
    final tappable = GestureDetector(
      onTap: () {
        if (appearance.haptics) HapticFeedback.selectionClick();
        onTap!();
      },
      child: content,
    );
    return TouchFeedbackWrapper(appearance: appearance, radius: radius, child: tappable);
  }

  @override
  Widget build(BuildContext context) {
    final glass = context.watch<GlassSettings>();
    final appearance = context.watch<AppearanceSettings>();
    final radius = borderRadius ?? BorderRadius.circular(appearance.cornerRadius);
    final glow = _neonGlowShadows(appearance);

    if (!glass.enabled) {
      final isCartoon = appearance.styleMode == UIStyleMode.cartoon;
      Widget card = Card(elevation: isCartoon ? 0 : null, child: Padding(padding: padding, child: child));
      if (isCartoon) {
        card = wrapWithHardShadow(child: card, radius: radius, color: appearance.primaryColor);
      }
      final wrapped = _wrapTappable(context, card, appearance, radius);
      if (glow.isEmpty) return wrapped;
      return Container(decoration: BoxDecoration(borderRadius: radius, boxShadow: glow), child: wrapped);
    }

    final tint = appearance.accentColor;
    final isLiquid = appearance.styleMode == UIStyleMode.liquid;
    final edgeColor = Colors.white;

    final glassCard = Container(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: [...glow, ..._edgeBlurShadows(appearance, edgeColor)]),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: glass.blur, sigmaY: glass.blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: isLiquid
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.45), // bright sheen top-left
                        Colors.white.withValues(alpha: 0.12),
                        tint.withValues(alpha: 0.1),
                      ],
                      stops: const [0.0, 0.4, 1.0],
                    )
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.22),
                        tint.withValues(alpha: 0.08),
                      ],
                    ),
              border: Border.all(color: Colors.white.withValues(alpha: isLiquid ? 0.55 : 0.35), width: 1.2),
              boxShadow: [
                BoxShadow(color: tint.withValues(alpha: isLiquid ? 0.18 : 0.12), blurRadius: isLiquid ? 32 : 24, offset: const Offset(0, 8)),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
    return _wrapTappable(context, glassCard, appearance, radius);
  }
}

/// Wraps any tappable widget with a felt press response — fade, a glow
/// pulse, or a scale-down — without interfering with the child's own tap
/// handling (Listener observes pointer events, it doesn't consume them).
class TouchFeedbackWrapper extends StatefulWidget {
  final Widget child;
  final AppearanceSettings appearance;
  final BorderRadius radius;
  const TouchFeedbackWrapper({super.key, required this.child, required this.appearance, required this.radius});

  @override
  State<TouchFeedbackWrapper> createState() => _TouchFeedbackWrapperState();
}

class _TouchFeedbackWrapperState extends State<TouchFeedbackWrapper> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final feedback = widget.appearance.touchFeedback;

    Widget content = widget.child;
    switch (feedback) {
      case TouchFeedback.none:
        break;
      case TouchFeedback.fade:
        content = AnimatedOpacity(
          opacity: _pressed ? 0.6 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: content,
        );
        break;
      case TouchFeedback.scale:
        content = AnimatedScale(
          scale: _pressed ? 0.96 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: content,
        );
        break;
      case TouchFeedback.glow:
        content = AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: widget.radius,
            boxShadow: _pressed
                ? [
                    BoxShadow(color: widget.appearance.glowColor.withValues(alpha: 0.6), blurRadius: 20, spreadRadius: 2),
                    BoxShadow(color: widget.appearance.glowColor.withValues(alpha: 0.3), blurRadius: 36, spreadRadius: 4),
                  ]
                : const [],
          ),
          child: content,
        );
        break;
    }

    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: content,
    );
  }
}

/// A "crystal" button — transparent, blurred, bordered. The premium glass
/// equivalent of FilledButton. Falls back to a normal FilledButton when
/// Glass UI is off, so callers don't need their own branching.
class GlassButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final IconData? icon;

  const GlassButton({super.key, required this.child, required this.onPressed, this.icon});

  @override
  Widget build(BuildContext context) {
    final glass = context.watch<GlassSettings>();
    final appearance = context.watch<AppearanceSettings>();
    final radius = BorderRadius.circular(appearance.cornerRadius * 0.85);
    final glow = _neonGlowShadows(appearance);

    if (!glass.enabled) {
      final wrappedOnPressed = onPressed == null
          ? null
          : () {
              if (appearance.haptics) HapticFeedback.lightImpact();
              onPressed!();
            };
      Widget button = icon != null
          ? FilledButton.icon(onPressed: wrappedOnPressed, icon: Icon(icon), label: child, style: appearance.styleMode == UIStyleMode.cartoon ? FilledButton.styleFrom(elevation: 0) : null)
          : FilledButton(onPressed: wrappedOnPressed, style: appearance.styleMode == UIStyleMode.cartoon ? FilledButton.styleFrom(elevation: 0) : null, child: child);
      if (appearance.styleMode == UIStyleMode.cartoon) {
        button = wrapWithHardShadow(child: button, radius: radius, color: appearance.accentColor, offset: 4);
      }
      final withGlow = glow.isEmpty
          ? button
          : Container(decoration: BoxDecoration(borderRadius: radius, boxShadow: glow), child: button);
      return TouchFeedbackWrapper(appearance: appearance, radius: radius, child: withGlow);
    }

    final primary = appearance.primaryColor;
    final disabled = onPressed == null;

    return TouchFeedbackWrapper(
      appearance: appearance,
      radius: radius,
      child: Container(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: [...glow, ..._edgeBlurShadows(appearance, Colors.white)]),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: glass.blur * 0.6, sigmaY: glass.blur * 0.6),
          child: Material(
            color: Colors.white.withValues(alpha: disabled ? 0.08 : 0.18),
            child: InkWell(
              onTap: onPressed == null
                  ? null
                  : () {
                      if (appearance.haptics) HapticFeedback.lightImpact();
                      onPressed!();
                    },
              splashColor: primary.withValues(alpha: 0.15),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 22),
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(color: Colors.white.withValues(alpha: disabled ? 0.15 : 0.4), width: 1.2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 18, color: disabled ? Colors.grey : primary),
                      const SizedBox(width: 8),
                    ],
                    DefaultTextStyle(
                      style: TextStyle(color: disabled ? Colors.grey : primary, fontWeight: FontWeight.w600),
                      child: child,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}

/// The gradient backdrop glass surfaces look "frosted" against — built
/// from the user's own primary/accent colors, so it's not a fixed navy
/// gradient anymore. No-op passthrough when Glass UI is off.
class GlassBackdrop extends StatelessWidget {
  final Widget child;
  const GlassBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final glass = context.watch<GlassSettings>();
    final appearance = context.watch<AppearanceSettings>();
    if (!glass.enabled) return child;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            appearance.primaryColor,
            appearance.accentColor.withValues(alpha: 0.7),
            appearance.darkMode ? const Color(0xFF14171F) : const Color(0xFFF7F8FA),
          ],
          stops: const [0.0, 0.35, 1.0],
        ),
      ),
      child: child,
    );
  }
}
