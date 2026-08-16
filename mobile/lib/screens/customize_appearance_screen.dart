import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/appearance_settings.dart';
import '../theme/tonal_palette.dart';
import '../theme/glass_settings.dart';
import '../theme/locale_settings.dart';
import '../widgets/color_picker_dialog.dart';
import '../widgets/live_preview_panel.dart';
import 'dart:io';
import '../theme/label_overrides.dart';
import '../l10n/app_strings.dart';
import '../services/local_branding_assets.dart';
import '../widgets/ai_theme_generator_card.dart';

class CustomizeAppearanceScreen extends StatefulWidget {
  const CustomizeAppearanceScreen({super.key});

  @override
  State<CustomizeAppearanceScreen> createState() => _CustomizeAppearanceScreenState();
}

class _CustomizeAppearanceScreenState extends State<CustomizeAppearanceScreen> {
  List<ThemePreset> _customPresets = [];
  // Batch 5: 'All', a TemplateCategory's .name, or 'Custom' -- screen-
  // local UI state (not persisted), same as any tab selection the person
  // can freely change without it being "a setting."
  String _activeFilter = 'All';

  // Batch 5: category chips filter the static gallery; custom (saved)
  // presets don't carry a meaningful category (saveCurrentAsPreset
  // defaults them neutrally), so they only appear under 'All' or their
  // own 'Custom' chip, never under a specific category filter.
  List<ThemePreset> get _visibleStaticPresets {
    if (_activeFilter == 'Custom') return [];
    if (_activeFilter == 'All') return themePresets;
    return themePresets.where((p) => p.category.name == _activeFilter).toList();
  }

  List<ThemePreset> get _visibleCustomPresets {
    if (_activeFilter == 'All' || _activeFilter == 'Custom') return _customPresets;
    return [];
  }

  @override
  void initState() {
    super.initState();
    _loadCustomPresets();
  }

  Future<void> _loadCustomPresets() async {
    final appearance = context.read<AppearanceSettings>();
    final presets = await appearance.getCustomPresets();
    if (!mounted) return;
    setState(() => _customPresets = presets);
  }

  Future<void> _pickColor(BuildContext context, {required Color initial, required String title, required ValueChanged<Color> onPicked}) async {
    final result = await showDialog<Color>(
      context: context,
      builder: (_) => ColorPickerDialog(initial: initial, title: title),
    );
    if (result != null) onPicked(result);
  }

  Future<void> _pickWallpaper(AppearanceSettings appearance) async {
    final path = await LocalBrandingAssets.pickAndSaveBackground();
    if (path != null) await appearance.setCustomBackgroundImagePath(path);
  }

  Future<void> _removeWallpaper(AppearanceSettings appearance) async {
    await LocalBrandingAssets.deleteBackground();
    await appearance.setCustomBackgroundImagePath(null);
  }

  Future<void> _pickLogo(AppearanceSettings appearance) async {
    final path = await LocalBrandingAssets.pickAndSaveLogo();
    if (path != null) await appearance.setCustomLogoPath(path);
  }

  Future<void> _removeLogo(AppearanceSettings appearance) async {
    await LocalBrandingAssets.deleteLogo();
    await appearance.setCustomLogoPath(null);
  }

  Future<void> _saveAsPresetDialog(AppearanceSettings appearance) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Save current look'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Preset name', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await appearance.saveCurrentAsPreset(name);
      await _loadCustomPresets();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved "$name" to Quick Looks')));
      }
    }
  }

  Future<void> _confirmDeletePreset(AppearanceSettings appearance, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete preset?'),
        content: Text('"$name" will be removed. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await appearance.deleteCustomPreset(name);
      await _loadCustomPresets();
    }
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
          TextButton(onPressed: () => appearance.resetToDefaults(), child: const Text('Reset All')),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: const LivePreviewPanel(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'This is a personal preference for this device — it doesn\'t change what other counselors see.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 12),

                _category(
                  icon: Icons.dashboard_customize_outlined,
                  title: 'Look',
                  initiallyExpanded: true,
                  children: [
                    _sectionTitle('Language'),
                    const SizedBox(height: 8),
                    SegmentedButton<AppLanguage>(
                      segments: AppLanguage.values.map((l) => ButtonSegment(value: l, label: Text(l.label))).toList(),
                      selected: {locale.language},
                      onSelectionChanged: (s) => locale.setLanguage(s.first),
                    ),
                    const SizedBox(height: 20),
                    const AiThemeGeneratorCard(),
                    const SizedBox(height: 20),
                    _sectionTitle('Style Mode'),
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
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        _sectionTitle('Quick Looks'),
                        const Spacer(),
                        TextButton.icon(
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Save current'),
                          onPressed: () => _saveAsPresetDialog(appearance),
                          style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Batch 5: category tabs -- with 19 static templates,
                    // a single flat scroll was getting long to browse.
                    // Each TemplateCategory (Batch 2) plus 'Custom' for
                    // saved presets, plus 'All' as the original behavior.
                    SizedBox(
                      height: 32,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          'All',
                          ...TemplateCategory.values.map((c) => c.name),
                          if (_customPresets.isNotEmpty) 'Custom',
                        ].map((filter) {
                          final label = filter == 'All'
                              ? 'All'
                              : filter == 'Custom'
                                  ? 'My Custom'
                                  : TemplateCategory.values.firstWhere((c) => c.name == filter).label;
                          final selected = _activeFilter == filter;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(label, style: const TextStyle(fontSize: 12)),
                              selected: selected,
                              onSelected: (_) => setState(() => _activeFilter = filter),
                              visualDensity: VisualDensity.compact,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Builder(builder: (context) {
                      final staticList = _visibleStaticPresets;
                      final customList = _visibleCustomPresets;
                      final total = staticList.length + customList.length;
                      if (total == 0) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Text('No templates in this category yet.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        );
                      }
                      return SizedBox(
                        height: 96,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: total,
                          separatorBuilder: (_, __) => const SizedBox(width: 10),
                          itemBuilder: (context, i) {
                            final isCustom = i >= staticList.length;
                            final p = isCustom ? customList[i - staticList.length] : staticList[i];
                            return GestureDetector(
                              onTap: () => appearance.applyPreset(p, glass.setEnabled, glass.setBlur),
                              onLongPress: isCustom ? () => _confirmDeletePreset(appearance, p.name) : null,
                              child: Container(
                                width: 108,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  // Batch 5: use the template's own 2-stop
                                  // gradient (Batch 2's gradientEnd) when
                                  // it has one, instead of always showing
                                  // a flat primary->accent -- Holographic
                                  // Lens, iOS Liquid Glass etc. now
                                  // preview the way they'll actually look.
                                  gradient: LinearGradient(colors: [p.primary, p.gradientEnd ?? p.accent]),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Stack(
                                  children: [
                                    Column(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(p.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                                        Text(p.tagline, style: const TextStyle(color: Colors.white70, fontSize: 9), maxLines: 1, overflow: TextOverflow.ellipsis),
                                      ],
                                    ),
                                    if (isCustom)
                                      const Positioned(
                                        top: 0, right: 0,
                                        child: Icon(Icons.push_pin, color: Colors.white70, size: 14),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    }),
                    if (_customPresets.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text('Long-press one of your saved looks to delete it', style: TextStyle(color: Colors.grey, fontSize: 11)),
                      ),
                  ],
                ),

                _category(
                  icon: Icons.palette_outlined,
                  title: 'Colors',
                  initiallyExpanded: true,
                  onReset: () => appearance.resetColors(),
                  children: [
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
                    const SizedBox(height: 10),
                    // Batch 3: gradient toggles. Kept right under the
                    // base color rather than a separate section, since a
                    // gradient is a variant of that color, not a new
                    // concept -- matches how Glow Color sits under Glow
                    // Effect below.
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Primary Gradient'),
                      subtitle: const Text('2-stop gradient from Primary — for glass/liquid templates'),
                      value: appearance.primaryGradientEnabled,
                      onChanged: appearance.setPrimaryGradientEnabled,
                    ),
                    if (appearance.primaryGradientEnabled) ...[
                      const SizedBox(height: 8),
                      _colorTile(
                        label: 'Gradient End',
                        color: appearance.primaryGradientEnd ?? appearance.primaryColor,
                        onTap: () => _pickColor(context,
                            initial: appearance.primaryGradientEnd ?? appearance.primaryColor,
                            title: 'Primary Gradient End',
                            onPicked: appearance.setPrimaryGradientEnd),
                      ),
                      const SizedBox(height: 8),
                    ],
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Accent Gradient'),
                      subtitle: const Text('2-stop gradient from Accent'),
                      value: appearance.accentGradientEnabled,
                      onChanged: appearance.setAccentGradientEnabled,
                    ),
                    if (appearance.accentGradientEnabled) ...[
                      const SizedBox(height: 8),
                      _colorTile(
                        label: 'Gradient End',
                        color: appearance.accentGradientEnd ?? appearance.accentColor,
                        onTap: () => _pickColor(context,
                            initial: appearance.accentGradientEnd ?? appearance.accentColor,
                            title: 'Accent Gradient End',
                            onPicked: appearance.setAccentGradientEnd),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const Text(
                      'STATUS COLOURS',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Used by lead score badges, Lead 360 alerts, sentiment indicators and status chips across the app.',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _colorTile(
                            label: 'Success',
                            color: appearance.successColor,
                            onTap: () => _pickColor(context, initial: appearance.successColor, title: 'Success Colour', onPicked: appearance.setSuccessColor),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _colorTile(
                            label: 'Warning',
                            color: appearance.warningColor,
                            onTap: () => _pickColor(context, initial: appearance.warningColor, title: 'Warning Colour', onPicked: appearance.setWarningColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _colorTile(
                            label: 'Danger',
                            color: appearance.dangerColor,
                            onTap: () => _pickColor(context, initial: appearance.dangerColor, title: 'Danger Colour', onPicked: appearance.setDangerColor),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _colorTile(
                            label: 'Muted',
                            color: appearance.mutedColor,
                            onTap: () => _pickColor(context, initial: appearance.mutedColor, title: 'Muted Colour', onPicked: appearance.setMutedColor),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Theme Engine v2 -- this is the direct answer to
                // "background poori screen pe apply hota hai, section-
                // wise hona chahiye": Background, Surface (cards), and
                // AppBar are now three independently overridable zones
                // instead of one flat color flooding everything. Default
                // (all three "Auto") derives them from Primary via the
                // tonal engine, which is what actually fixes flat/cheap
                // dark themes -- these overrides are for when someone
                // wants to deliberately diverge from that.
                _category(
                  icon: Icons.layers_outlined,
                  title: 'Surfaces (Advanced)',
                  onReset: () async {
                    await appearance.setBackgroundOverride(null);
                    await appearance.setSurfaceOverride(null);
                    await appearance.setAppBarOverride(null);
                    await appearance.setTonalSaturationBoost(1.0);
                  },
                  children: [
                    const Text(
                      'By default these auto-derive from your Primary colour so every theme has its own tint instead of generic grey/white. Override any of the three below to take manual control of that zone.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    Builder(builder: (context) {
                      final tonal = deriveTonalPalette(appearance.primaryColor, appearance.darkMode, saturationBoost: appearance.tonalSaturationBoost);
                      return Column(
                        children: [
                          _surfaceOverrideTile(
                            label: 'Background',
                            autoColor: tonal.background,
                            override: appearance.backgroundOverride,
                            onPick: appearance.setBackgroundOverride,
                          ),
                          const SizedBox(height: 10),
                          _surfaceOverrideTile(
                            label: 'Surface (cards, nav bar)',
                            autoColor: tonal.surfaceLow,
                            override: appearance.surfaceOverride,
                            onPick: appearance.setSurfaceOverride,
                          ),
                          const SizedBox(height: 10),
                          _surfaceOverrideTile(
                            label: 'App Bar',
                            autoColor: tonal.background,
                            override: appearance.appBarOverride,
                            onPick: appearance.setAppBarOverride,
                          ),
                        ],
                      );
                    }),
                    const SizedBox(height: 14),
                    const Text('Tint strength', style: TextStyle(fontSize: 13)),
                    const Text(
                      'How strongly Background/Surface lean toward your Primary colour\'s hue, rather than reading as plain grey/white.',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    Slider(
                      value: appearance.tonalSaturationBoost, min: 0.0, max: 2.0, divisions: 20,
                      label: '${(appearance.tonalSaturationBoost * 100).round()}%',
                      onChanged: appearance.setTonalSaturationBoost,
                    ),
                  ],
                ),

                _category(
                  icon: Icons.text_fields_outlined,
                  title: 'Typography',
                  onReset: () => appearance.resetTypography(),
                  children: [
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
                    // Batch 4 additions.
                    const SizedBox(height: 4),
                    const Text('Font weight', style: TextStyle(fontSize: 13)),
                    Wrap(
                      spacing: 8,
                      children: FontWeightChoice.values
                          .map((w) => ChoiceChip(
                                label: Text(w.label),
                                selected: appearance.fontWeightChoice == w,
                                onSelected: (_) => appearance.setFontWeightChoice(w),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    const Text('Letter spacing', style: TextStyle(fontSize: 13)),
                    Slider(
                      value: appearance.letterSpacing, min: -0.5, max: 2.0, divisions: 10,
                      label: appearance.letterSpacing.toStringAsFixed(1),
                      onChanged: appearance.setLetterSpacing,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Accessibility text scale',
                      style: TextStyle(fontSize: 13),
                    ),
                    const Text(
                      'Separate from Text size above — stacks with it, for anyone who needs everything larger to read comfortably.',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    Slider(
                      value: appearance.accessibilityFontScale, min: 1.0, max: 1.5, divisions: 10,
                      label: '${(appearance.accessibilityFontScale * 100).round()}%',
                      onChanged: appearance.setAccessibilityFontScale,
                    ),
                  ],
                ),

                _category(
                  icon: Icons.crop_square_outlined,
                  title: 'Shape & Structure',
                  onReset: () => appearance.resetShape(),
                  children: [
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
                  ],
                ),

                _category(
                  icon: Icons.auto_fix_high_outlined,
                  title: 'Effects & Motion',
                  onReset: () => appearance.resetEffects(),
                  children: [
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
                    const SizedBox(height: 8),
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
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Rough Texture'),
                      subtitle: const Text('Subtle grain overlay on every screen'),
                      value: appearance.textureEnabled,
                      onChanged: appearance.setTextureEnabled,
                    ),
                    if (glass.enabled) ...[
                      const SizedBox(height: 8),
                      const Text('Blur Intensity', style: TextStyle(fontSize: 13)),
                      Slider(
                        value: glass.blur, min: 4, max: 30, divisions: 13,
                        label: glass.blur.toStringAsFixed(0),
                        onChanged: glass.setBlur,
                      ),
                    ],
                  ],
                ),

                _category(
                  icon: Icons.view_agenda_outlined,
                  title: 'Layout',
                  onReset: () => appearance.resetLayout(),
                  children: [
                    _sectionTitle('Spacing'),
                    const SizedBox(height: 8),
                    SegmentedButton<SpacingDensity>(
                      segments: SpacingDensity.values.map((d) => ButtonSegment(value: d, label: Text(d.label))).toList(),
                      selected: {appearance.density},
                      onSelectionChanged: (s) => appearance.setDensity(s.first),
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
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Swipe Actions'),
                      subtitle: const Text('Swipe a lead left to reveal Delete'),
                      value: appearance.swipeActionsEnabled,
                      onChanged: appearance.setSwipeActionsEnabled,
                    ),
                  ],
                ),

                _category(
                icon: Icons.edit_note,
                title: 'Custom Labels',
                onReset: () => context.read<LabelOverrides>().resetAll(),
                children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text('Rename navigation tabs to match your own terminology. Leave blank to keep the default.', style: TextStyle(color: Colors.grey, fontSize: 11)),
                    ),
                    ...['nav_dashboard', 'nav_leads', 'nav_followups', 'nav_tasks', 'nav_more'].map((navKey) {
                      final overrides = context.watch<LabelOverrides>();
                      final controller = TextEditingController(text: overrides[navKey] ?? '');
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: TextField(
                          controller: controller,
                          decoration: InputDecoration(
                            labelText: context.tr(navKey),
                            hintText: 'Custom label',
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (v) => context.read<LabelOverrides>().setOverride(navKey, v),
                        ),
                      );
                    }),
                ],
              ),

              _category(
                icon: Icons.auto_awesome,
                title: 'Backdrop & Branding',
                onReset: () => appearance.resetBranding(),
                initiallyExpanded: true,
                children: [
                    _sectionTitle('Ambient Glow (Glass/Liquid modes)'),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Aurora Backdrop'),
                      subtitle: const Text('Soft ambient colour blobs instead of a flat gradient'),
                      value: appearance.auroraBackdropEnabled,
                      onChanged: (v) => appearance.setAuroraBackdropEnabled(v),
                    ),
                    if (appearance.auroraBackdropEnabled) ...[
                      Row(
                        children: [
                          const Text('Intensity', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          Expanded(
                            child: Slider(
                              value: appearance.auroraIntensity,
                              min: 0.2,
                              max: 1.0,
                              onChanged: (v) => appearance.setAuroraIntensity(v),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const Divider(height: 24),
                    _sectionTitle('Custom Wallpaper'),
                    const SizedBox(height: 8),
                    if (appearance.customBackgroundImagePath != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(File(appearance.customBackgroundImagePath!), height: 120, width: double.infinity, fit: BoxFit.cover),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.image_outlined, size: 18),
                            label: Text(appearance.customBackgroundImagePath == null ? 'Upload Wallpaper' : 'Change Wallpaper'),
                            onPressed: () => _pickWallpaper(appearance),
                          ),
                        ),
                        if (appearance.customBackgroundImagePath != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Remove wallpaper',
                            onPressed: () => _removeWallpaper(appearance),
                          ),
                        ],
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('Overrides Aurora/gradient backdrop in every mode, including Solid and Basic.', style: TextStyle(color: Colors.grey, fontSize: 11)),
                    ),
                    const Divider(height: 24),
                    _sectionTitle('Custom Logo'),
                    const SizedBox(height: 8),
                    if (appearance.customLogoPath != null) ...[
                      Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(File(appearance.customLogoPath!), height: 56, fit: BoxFit.contain),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.badge_outlined, size: 18),
                            label: Text(appearance.customLogoPath == null ? 'Upload Logo' : 'Change Logo'),
                            onPressed: () => _pickLogo(appearance),
                          ),
                        ),
                        if (appearance.customLogoPath != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Remove logo',
                            onPressed: () => _removeLogo(appearance),
                          ),
                        ],
                      ],
                    ),
                    if (appearance.customLogoPath != null) ...[
                      const SizedBox(height: 8),
                      _sectionTitle('Logo Position'),
                      const SizedBox(height: 8),
                      SegmentedButton<LogoPosition>(
                        segments: LogoPosition.values.map((p) => ButtonSegment(value: p, label: Text(p.label))).toList(),
                        selected: {appearance.logoPosition},
                        onSelectionChanged: (s) => appearance.setLogoPosition(s.first),
                      ),
                    ],
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('App icon (home-screen icon) cannot change at runtime -- Android bakes it into the app at build time. This logo appears inside the app itself, on every screen.', style: TextStyle(color: Colors.grey, fontSize: 11)),
                    ),
                ],
              ),

              _category(
                  icon: Icons.tune,
                  title: 'Mode & Accessibility',
                  onReset: () => appearance.resetModeAndAccessibility(),
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Dark Mode'),
                      value: appearance.darkMode,
                      onChanged: appearance.setDarkMode,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Haptic Feedback'),
                      subtitle: const Text('Light vibration on taps'),
                      value: appearance.haptics,
                      onChanged: appearance.setHaptics,
                    ),
                    const SizedBox(height: 8),
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
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // A collapsible, icon-labeled category card with an optional per-section
  // reset button in its header. Replaces the old flat, undifferentiated
  // list of 15+ sections with grouped, scannable categories -- the kind
  // of hierarchy premium settings screens (Notion, Linear, iOS Settings)
  // use once there are more than a handful of controls.
  Widget _category({
    required IconData icon,
    required String title,
    required List<Widget> children,
    bool initiallyExpanded = false,
    VoidCallback? onReset,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          leading: Icon(icon),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          trailing: onReset == null
              ? const Icon(Icons.expand_more)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 18),
                      tooltip: 'Reset $title',
                      visualDensity: VisualDensity.compact,
                      onPressed: onReset,
                    ),
                    const Icon(Icons.expand_more),
                  ],
                ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: children,
        ),
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

  /// A row for one of the three Theme Engine v2 surface zones. Shows the
  /// live-derived "Auto" color when no override is set (so the swatch is
  /// always accurate, never a placeholder), and a small "Auto" pill to
  /// clear back to it once a manual override has been chosen.
  Widget _surfaceOverrideTile({
    required String label,
    required Color autoColor,
    required Color? override,
    required Future<void> Function(Color?) onPick,
  }) {
    final displayColor = override ?? autoColor;
    return InkWell(
      onTap: () => _pickColor(context, initial: displayColor, title: label, onPicked: onPick),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: displayColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.withValues(alpha: 0.4)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(label)),
            if (override != null)
              TextButton(
                onPressed: () => onPick(null),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact, minimumSize: const Size(0, 0)),
                child: const Text('Auto', style: TextStyle(fontSize: 12)),
              )
            else
              const Text('Auto', style: TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
