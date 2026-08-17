import 'package:flutter/material.dart';
import '../screens/customize_registry.dart';
import '../services/api_service.dart';
import 'color_picker_dialog.dart';
import 'launcher_tile.dart';
import 'styled_icon_badge.dart' show kStyleVariantLabels;

Color _hexToColor(String hex) {
  var h = hex.replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  return Color(int.parse(h, radix: 16));
}

String _colorToHex(Color c) {
  final v = c.value & 0xFFFFFF;
  return '#${v.toRadixString(16).padLeft(6, '0')}';
}

/// The live design-mode editor: opened by tapping any tile while Edit
/// Mode is on, right where that tile already lives (More screen, and
/// wherever else opts in), instead of navigating to a separate
/// "Customize X" screen. Same colour/style-variant/gradient fields
/// every Customize* screen's own per-item editor already persists --
/// this is a second, in-place entry point onto the exact same backend
/// data, not a parallel styling system.
///
/// Beyond the 4 style_variant presets, this now exposes the independent
/// fine-grained controls backed by style_json (corner radius, border,
/// glow, blur, content scale/"resize", texture) -- a real "customizable
/// studio" set of knobs rather than a fixed handful of combos, per
/// direct feedback that 4 presets weren't enough control.
///
/// Returns the applied style map on save (null on cancel) so the caller
/// can update its own local tile state immediately, without waiting on
/// a re-fetch, for a genuinely "live" feel.
class QuickStyleEditorSheet extends StatefulWidget {
  final CustomizeRegistryItem item;
  final String currentColorHex;
  final String currentStyleVariant;
  final String? currentGradientEndHex;
  final Map<String, dynamic>? currentStyleJson;

  const QuickStyleEditorSheet({
    super.key,
    required this.item,
    required this.currentColorHex,
    this.currentStyleVariant = 'flat',
    this.currentGradientEndHex,
    this.currentStyleJson,
  });

  @override
  State<QuickStyleEditorSheet> createState() => _QuickStyleEditorSheetState();
}

class _QuickStyleEditorSheetState extends State<QuickStyleEditorSheet> {
  final _api = ApiService();
  late Color _color;
  late String _styleVariant;
  Color? _gradientEnd;
  bool _saving = false;
  String? _error;

  // Fine-grained style_json controls.
  late double _cornerRadius;
  late double _contentScale;
  late double _blurAmount;
  late String _textureId;
  bool _borderEnabled = false;
  late Color _borderColor;
  late double _borderWidth;
  bool _glowEnabled = false;
  late Color _glowColor;
  late double _glowIntensity;

  @override
  void initState() {
    super.initState();
    _color = _hexToColor(widget.currentColorHex);
    _styleVariant = widget.currentStyleVariant;
    _gradientEnd = widget.currentGradientEndHex != null ? _hexToColor(widget.currentGradientEndHex!) : null;

    final sj = widget.currentStyleJson ?? const {};
    _cornerRadius = ((sj['cornerRadius'] as num?)?.toDouble() ?? 16).clamp(0, 40);
    _contentScale = ((sj['contentScale'] as num?)?.toDouble() ?? 1.0).clamp(0.7, 1.6);
    _blurAmount = ((sj['blurAmount'] as num?)?.toDouble() ?? 0).clamp(0, 20);
    _textureId = (sj['textureId'] as String?) ?? 'none';
    final borderHex = sj['borderColor'] as String?;
    _borderEnabled = borderHex != null;
    _borderColor = borderHex != null ? _hexToColor(borderHex) : _color;
    _borderWidth = ((sj['borderWidth'] as num?)?.toDouble() ?? 1.5).clamp(0.5, 6);
    final glowHex = sj['glowColor'] as String?;
    _glowEnabled = glowHex != null;
    _glowColor = glowHex != null ? _hexToColor(glowHex) : _color;
    _glowIntensity = ((sj['glowIntensity'] as num?)?.toDouble() ?? 0.5).clamp(0, 1);
  }

  Map<String, dynamic> get _styleJson => {
        'cornerRadius': _cornerRadius,
        'contentScale': _contentScale,
        'blurAmount': _blurAmount,
        'textureId': _textureId,
        if (_borderEnabled) 'borderColor': _colorToHex(_borderColor),
        if (_borderEnabled) 'borderWidth': _borderWidth,
        if (_glowEnabled) 'glowColor': _colorToHex(_glowColor),
        if (_glowEnabled) 'glowIntensity': _glowIntensity,
      };

  Future<void> _pickColor({required String target}) async {
    final current = switch (target) {
      'gradient' => _gradientEnd ?? _color,
      'border' => _borderColor,
      'glow' => _glowColor,
      _ => _color,
    };
    final title = switch (target) {
      'gradient' => 'Gradient end colour',
      'border' => 'Border colour',
      'glow' => 'Glow colour',
      _ => 'Colour',
    };
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => ColorPickerDialog(initial: current, title: title),
    );
    if (picked == null) return;
    setState(() {
      switch (target) {
        case 'gradient':
          _gradientEnd = picked;
          break;
        case 'border':
          _borderColor = picked;
          break;
        case 'glow':
          _glowColor = picked;
          break;
        default:
          _color = picked;
      }
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final colorHex = _colorToHex(_color);
    final gradientHex = _styleVariant == 'gradient_badge' ? _colorToHex(_gradientEnd ?? _color) : null;
    final styleJson = _styleJson;
    try {
      await widget.item.applyStyle(
        _api,
        colorHex: colorHex,
        styleVariant: _styleVariant,
        gradientEndHex: gradientHex,
        styleJson: styleJson,
      );
      if (mounted) {
        Navigator.pop(context, {
          'color': colorHex,
          'styleVariant': _styleVariant,
          'gradientEnd': gradientHex,
          'styleJson': styleJson,
        });
      }
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Could not save: $e';
      });
    }
  }

  Widget _sectionLabel(String text) =>
      Padding(padding: const EdgeInsets.only(top: 16, bottom: 8), child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)));

  Widget _sliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    String Function(double)? format,
  }) {
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 12))),
        Expanded(child: Slider(value: value, min: min, max: max, onChanged: onChanged)),
        SizedBox(
          width: 36,
          child: Text(format != null ? format(value) : value.toStringAsFixed(0),
              style: const TextStyle(fontSize: 11, color: Colors.grey), textAlign: TextAlign.right),
        ),
      ],
    );
  }

  Widget _colorSwatchTap(Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade300)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.edit, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(widget.item.label, style: Theme.of(context).textTheme.titleMedium, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            Text(widget.item.category, style: TextStyle(fontSize: 11, color: widget.item.categoryColor)),
            const SizedBox(height: 16),
            // Live preview -- a real LauncherTile with the exact in-progress
            // style, not a simplified stand-in, so what's previewed here is
            // exactly what the actual tile will look like.
            Center(
              child: SizedBox(
                width: 140,
                height: 120,
                child: LauncherTile(
                  label: widget.item.label,
                  icon: widget.item.icon,
                  color: _color,
                  gradientEnd: _gradientEnd,
                  styleVariant: _styleVariant,
                  styleJson: _styleJson,
                  onTap: () {},
                ),
              ),
            ),
            _sectionLabel('Style'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kStyleVariantLabels.entries.map((e) {
                final selected = e.key == _styleVariant;
                return ChoiceChip(
                  label: Text(e.value),
                  selected: selected,
                  onSelected: (_) => setState(() => _styleVariant = e.key),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Colour', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const Spacer(),
                _colorSwatchTap(_color, () => _pickColor(target: 'color')),
              ],
            ),
            if (_styleVariant == 'gradient_badge') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Gradient end', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const Spacer(),
                  _colorSwatchTap(_gradientEnd ?? _color, () => _pickColor(target: 'gradient')),
                ],
              ),
            ],

            _sectionLabel('Corner sharpness'),
            _sliderRow(
              label: 'Radius',
              value: _cornerRadius,
              min: 0,
              max: 40,
              onChanged: (v) => setState(() => _cornerRadius = v),
            ),

            _sectionLabel('Size'),
            _sliderRow(
              label: 'Scale',
              value: _contentScale,
              min: 0.7,
              max: 1.6,
              format: (v) => '${(v * 100).round()}%',
              onChanged: (v) => setState(() => _contentScale = v),
            ),

            _sectionLabel('Edge / border'),
            Row(
              children: [
                Switch(value: _borderEnabled, onChanged: (v) => setState(() => _borderEnabled = v)),
                const Text('Custom border', style: TextStyle(fontSize: 12)),
                const Spacer(),
                if (_borderEnabled) _colorSwatchTap(_borderColor, () => _pickColor(target: 'border')),
              ],
            ),
            if (_borderEnabled)
              _sliderRow(
                label: 'Width',
                value: _borderWidth,
                min: 0.5,
                max: 6,
                format: (v) => v.toStringAsFixed(1),
                onChanged: (v) => setState(() => _borderWidth = v),
              ),

            _sectionLabel('Glow'),
            Row(
              children: [
                Switch(value: _glowEnabled, onChanged: (v) => setState(() => _glowEnabled = v)),
                const Text('Custom glow', style: TextStyle(fontSize: 12)),
                const Spacer(),
                if (_glowEnabled) _colorSwatchTap(_glowColor, () => _pickColor(target: 'glow')),
              ],
            ),
            if (_glowEnabled)
              _sliderRow(
                label: 'Intensity',
                value: _glowIntensity,
                min: 0,
                max: 1,
                format: (v) => '${(v * 100).round()}%',
                onChanged: (v) => setState(() => _glowIntensity = v),
              ),

            _sectionLabel('Blur (glass effect)'),
            _sliderRow(
              label: 'Amount',
              value: _blurAmount,
              min: 0,
              max: 20,
              onChanged: (v) => setState(() => _blurAmount = v),
            ),

            _sectionLabel('Texture'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kTileTextureLabels.entries.map((e) {
                final selected = e.key == _textureId;
                return ChoiceChip(
                  label: Text(e.value),
                  selected: selected,
                  onSelected: (_) => setState(() => _textureId = e.key),
                );
              }).toList(),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel'))),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
