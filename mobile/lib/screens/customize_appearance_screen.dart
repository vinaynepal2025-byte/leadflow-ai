import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/appearance_settings.dart';
import '../theme/glass_settings.dart';
import '../theme/locale_settings.dart';
import '../widgets/color_picker_dialog.dart';
import '../widgets/live_preview_panel.dart';
import '../widgets/ai_theme_generator_card.dart';

class CustomizeAppearanceScreen extends StatelessWidget {
  const CustomizeAppearanceScreen({super.key});

  Future<void> _pickColor(BuildContext context, {required Color initial, required String title, required ValueChanged<Color> onPicked}) async {
    final result = await showDialog<Color>(
      context: context,
      builder: (_) => ColorPickerDialog(initial: initial, title: title),
    );
    if (result != null) onPicked(result);
  }

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<AppearanceSettings>();
    final glass = context.watch<GlassSettings>();
    final locale = context.watch<LocaleSettings>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customize App Look'),
        actions: [
          TextButton(onPressed: () => appearance.resetToDefaults(), child: const Text('Reset')),
        ],
      ),
      body: Column(
        children: [
          // Pinned at the top — stays visible while every control below is
          // scrolled and adjusted, so the person always sees the effect of
          // their last change without switching screens.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: const LivePreviewPanel(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'This is a personal preference for this device — it doesn\'t change what other counselors see.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 16),
                const AiThemeGeneratorCard(),
                const SizedBox(height: 20),

                _sectionTitle('Language'),
                const SizedBox(height: 8),
                SegmentedButton<AppLanguage>(
                  segments: AppLanguage.values.map((l) => ButtonSegment(value: l, label: Text(l.label))).toList(),
                  selected: {locale.language},
                  onSelectionChanged: (s) => locale.setLanguage(s.first),
                ),

                const SizedBox(height: 20),

                _sectionTitle('Look'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: UIStyleMode.values.map((mode) {
                    final selected = appearance.styleMode == mode;
                    return GestureDetector(
                      onTap: () => appearance.setStyleMode(mode, glass.setEnabled),
                      child: Container(
                        width: 96,
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                        decoration: BoxDecoration(
                          color: selected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1) : null,
                          border: Border.all(
                            color: selected ? Theme.of(context).colorScheme.primary : Colors.grey.withValues(alpha: 0.3),
                            width: selected ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Icon(mode.icon, color: selected ? Theme.of(context).colorScheme.primary : Colors.grey.shade700),
                            const SizedBox(height: 6),
                            Text(mode.label, style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(appearance.styleMode.description, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ),

                const SizedBox(height: 24),
                _sectionTitle('Quick Looks'),
                const SizedBox(height: 10),
                SizedBox(
                  height: 96,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: themePresets.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      final p = themePresets[i];
                      return GestureDetector(
                        onTap: () => appearance.applyPreset(p, glass.setEnabled),
                        child: Container(
                          width: 108,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [p.primary, p.accent]),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                              Text(p.tagline, style: const TextStyle(color: Colors.white70, fontSize: 9), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),

                _sectionTitle('Colors'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _colorTile(
                        label: 'Primary',
                        color: appearance.primaryColor,
                        onTap: () => _pickColor(context, initial: appearance.primaryColor, title: 'Primary Color', onPicked: appearance.setPrimaryColor),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _colorTile(
                        label: 'Accent',
                        color: appearance.accentColor,
                        onTap: () => _pickColor(context, initial: appearance.accentColor, title: 'Accent Color', onPicked: appearance.setAccentColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _colorTile(
                        label: appearance.outlineColor == null ? 'Outline: Auto' : 'Outline',
                        color: appearance.outlineColor ?? appearance.primaryColor,
                        onTap: () => _pickColor(context,
                            initial: appearance.outlineColor ?? appearance.primaryColor,
                            title: 'Outline Color',
                            onPicked: appearance.setOutlineColor),
                      ),
                    ),
                    if (appearance.outlineColor != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Reset to auto',
                        onPressed: () => appearance.setOutlineColor(null),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 24),
                _sectionTitle('Typography'),
                const SizedBox(height: 10),
                ...FontPairing.values.map((f) => RadioListTile<FontPairing>(
                      contentPadding: EdgeInsets.zero,
                      title: Text(f.label),
                      value: f,
                      groupValue: appearance.fontPairing,
                      onChanged: (v) {
                        if (v != null) appearance.setFontPairing(v);
                      },
                    )),
                const SizedBox(height: 8),
                const Text('Text size', style: TextStyle(fontSize: 13)),
                Slider(
                  value: appearance.fontScale, min: 0.85, max: 1.3, divisions: 9,
                  label: '${(appearance.fontScale * 100).round()}%',
                  onChanged: appearance.setFontScale,
                ),

                const SizedBox(height: 16),
                _sectionTitle('Shape & Structure'),
                const SizedBox(height: 10),
                const Text('Corner roundness', style: TextStyle(fontSize: 13)),
                Slider(
                  value: appearance.cornerRadius, min: 0, max: 28, divisions: 14,
                  label: appearance.cornerRadius.round().toString(),
                  onChanged: appearance.setCornerRadius,
                ),
                const Text('Border thickness', style: TextStyle(fontSize: 13)),
                Slider(
                  value: appearance.borderThickness, min: 0, max: 4, divisions: 8,
                  label: appearance.borderThickness.toStringAsFixed(1),
                  onChanged: appearance.setBorderThickness,
                ),
                const Text('Transparency', style: TextStyle(fontSize: 13)),
                Slider(
                  value: appearance.componentOpacity, min: 0.3, max: 1.0, divisions: 7,
                  label: '${(appearance.componentOpacity * 100).round()}%',
                  onChanged: appearance.setComponentOpacity,
                ),
                const Text('Button & card size', style: TextStyle(fontSize: 13)),
                Slider(
                  value: appearance.componentScale, min: 0.8, max: 1.4, divisions: 6,
                  label: '${(appearance.componentScale * 100).round()}%',
                  onChanged: appearance.setComponentScale,
                ),
                const Text('Edge blur (soft-focus edges)', style: TextStyle(fontSize: 13)),
                Slider(
                  value: appearance.edgeBlur, min: 0, max: 14, divisions: 14,
                  label: appearance.edgeBlur.round().toString(),
                  onChanged: appearance.setEdgeBlur,
                ),

                const SizedBox(height: 16),
                _sectionTitle('Neon Glow'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Glow Effect'),
                  subtitle: const Text('A colored light around buttons and cards'),
                  value: appearance.glowEnabled,
                  onChanged: appearance.setGlowEnabled,
                ),
                if (appearance.glowEnabled) ...[
                  const SizedBox(height: 8),
                  _colorTile(
                    label: 'Glow Color',
                    color: appearance.glowColor,
                    onTap: () => _pickColor(context, initial: appearance.glowColor, title: 'Glow Color', onPicked: appearance.setGlowColor),
                  ),
                  const SizedBox(height: 8),
                  const Text('Intensity', style: TextStyle(fontSize: 13)),
                  Slider(
                    value: appearance.glowIntensity, min: 0.1, max: 1.0, divisions: 9,
                    label: '${(appearance.glowIntensity * 100).round()}%',
                    onChanged: appearance.setGlowIntensity,
                  ),
                ],

                const SizedBox(height: 16),
                _sectionTitle('Spacing'),
                const SizedBox(height: 8),
                SegmentedButton<SpacingDensity>(
                  segments: SpacingDensity.values.map((d) => ButtonSegment(value: d, label: Text(d.label))).toList(),
                  selected: {appearance.density},
                  onSelectionChanged: (s) => appearance.setDensity(s.first),
                ),

                const SizedBox(height: 16),
                _sectionTitle('Floating'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Floating Elements'),
                  subtitle: const Text('Extra lift/shadow, like cards hovering above the page'),
                  value: appearance.floatingEnabled,
                  onChanged: appearance.setFloatingEnabled,
                ),
                if (appearance.floatingEnabled) ...[
                  const Text('Lift amount', style: TextStyle(fontSize: 13)),
                  Slider(
                    value: appearance.floatingIntensity, min: 0.1, max: 1.0, divisions: 9,
                    label: '${(appearance.floatingIntensity * 100).round()}%',
                    onChanged: appearance.setFloatingIntensity,
                  ),
                ],

                const SizedBox(height: 16),
                _sectionTitle('Touch Feedback'),
                const SizedBox(height: 8),
                SegmentedButton<TouchFeedback>(
                  segments: TouchFeedback.values.map((t) => ButtonSegment(value: t, label: Text(t.label))).toList(),
                  selected: {appearance.touchFeedback},
                  onSelectionChanged: (s) => appearance.setTouchFeedback(s.first),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('What buttons do the instant you press them', style: TextStyle(color: Colors.grey, fontSize: 11)),
                ),

                const SizedBox(height: 16),
                _sectionTitle('Gestures'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Swipe Actions'),
                  subtitle: const Text('Swipe a lead left to reveal Delete'),
                  value: appearance.swipeActionsEnabled,
                  onChanged: appearance.setSwipeActionsEnabled,
                ),

                const SizedBox(height: 16),
                _sectionTitle('Navigation Position'),
                const SizedBox(height: 8),
                SegmentedButton<NavPosition>(
                  segments: NavPosition.values.map((n) => ButtonSegment(value: n, label: Text(n.label))).toList(),
                  selected: {appearance.navPosition},
                  onSelectionChanged: (s) => appearance.setNavPosition(s.first),
                ),

                const SizedBox(height: 16),
                _sectionTitle('Mode'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Dark Mode'),
                  value: appearance.darkMode,
                  onChanged: appearance.setDarkMode,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Rough Texture'),
                  subtitle: const Text('Subtle grain overlay on every screen'),
                  value: appearance.textureEnabled,
                  onChanged: appearance.setTextureEnabled,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Haptic Feedback'),
                  subtitle: const Text('Light vibration on taps'),
                  value: appearance.haptics,
                  onChanged: appearance.setHaptics,
                ),

                if (glass.enabled) ...[
                  const SizedBox(height: 16),
                  _sectionTitle('Blur Intensity'),
                  Slider(
                    value: glass.blur, min: 4, max: 30, divisions: 13,
                    label: glass.blur.toStringAsFixed(0),
                    onChanged: glass.setBlur,
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16));

  Widget _colorTile({required String label, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(width: 28, height: 28, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Text(label),
          ],
        ),
      ),
    );
  }
}
