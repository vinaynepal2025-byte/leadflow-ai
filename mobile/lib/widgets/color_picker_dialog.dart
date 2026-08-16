import 'package:flutter/material.dart';
import '../theme/contrast_utils.dart';

/// A curated set of swatches (quick picks) plus a genuinely free RGB
/// picker for "apni marzi se" (any color the person wants) — not limited
/// to presets.
///
/// Theme Engine v2: expanded from a flat 14-color wrap to ~36 swatches
/// organized into labeled families, closer to how Figma/Stripe-style
/// color tools actually present choice -- grouped by mood, not just a
/// scroll of dots with no organizing principle.
class ColorPickerDialog extends StatefulWidget {
  final Color initial;
  final String title;
  const ColorPickerDialog({super.key, required this.initial, required this.title});

  static const Map<String, List<Color>> swatchFamilies = {
    'Blues': [
      Color(0xFF1D4ED8), Color(0xFF0EA5E9), Color(0xFF4F46E5),
      Color(0xFF1B2A4A), Color(0xFF06B6D4), Color(0xFF2563EB),
    ],
    'Greens & Teals': [
      Color(0xFF10B981), Color(0xFF0E7490), Color(0xFF15803D),
      Color(0xFF34D399), Color(0xFF059669), Color(0xFF0D9488),
    ],
    'Purples & Violets': [
      Color(0xFF6D28D9), Color(0xFF7C3AED), Color(0xFF86198F),
      Color(0xFFA78BFA), Color(0xFFC026D3), Color(0xFF4338CA),
    ],
    'Warm & Coral': [
      Color(0xFFE8A33D), Color(0xFFE85D4E), Color(0xFFB45309),
      Color(0xFFBE185D), Color(0xFFDC2626), Color(0xFFEAB308),
    ],
    'Neutrals & Slate': [
      Color(0xFF334155), Color(0xFF18181B), Color(0xFF57534E),
      Color(0xFF3F3F46), Color(0xFF71717A), Color(0xFF0F172A),
    ],
    'Neon & Bold': [
      Color(0xFF00E5FF), Color(0xFFFF00E5), Color(0xFF39FF14),
      Color(0xFFFF3131), Color(0xFFFFD400), Color(0xFFEC4899),
    ],
  };

  /// Flattened, for the "is this a curated color or a custom one"
  /// contains-check that decides which mode the dialog opens in.
  static List<Color> get swatches => swatchFamilies.values.expand((c) => c).toList();

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late int _r, _g, _b;
  bool _customMode = false;
  late final TextEditingController _hexController;

  @override
  void initState() {
    super.initState();
    _r = ((widget.initial.r * 255.0).round()) & 0xff;
    _g = ((widget.initial.g * 255.0).round()) & 0xff;
    _b = ((widget.initial.b * 255.0).round()) & 0xff;
    _customMode = !ColorPickerDialog.swatches.contains(widget.initial);
    _hexController = TextEditingController(text: _toHex(_current));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  String _toHex(Color c) {
    String ch(int v) => v.toRadixString(16).padLeft(2, '0');
    final r = (c.r * 255.0).round() & 0xff;
    final g = (c.g * 255.0).round() & 0xff;
    final b = (c.b * 255.0).round() & 0xff;
    return '#${ch(r)}${ch(g)}${ch(b)}'.toUpperCase();
  }

  void _applyHex(String raw) {
    final hex = raw.trim().replaceAll('#', '');
    if (hex.length != 6) return;
    final value = int.tryParse(hex, radix: 16);
    if (value == null) return;
    setState(() {
      _r = (value >> 16) & 0xff;
      _g = (value >> 8) & 0xff;
      _b = value & 0xff;
      _customMode = true;
    });
  }

  Color get _current => Color.fromARGB(255, _r, _g, _b);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...ColorPickerDialog.swatchFamilies.entries.map((family) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(family.key, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey, letterSpacing: 0.4)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: family.value.map((c) => GestureDetector(
                              onTap: () => setState(() {
                                _r = ((c.r * 255.0).round()) & 0xff;
                                _g = ((c.g * 255.0).round()) & 0xff;
                                _b = ((c.b * 255.0).round()) & 0xff;
                                _customMode = false;
                              }),
                              child: Container(
                                width: 34, height: 34,
                                decoration: BoxDecoration(
                                  color: c,
                                  shape: BoxShape.circle,
                                  border: !_customMode && c.value == _current.value
                                      ? Border.all(color: Colors.black, width: 2.5)
                                      : null,
                                ),
                              ),
                            )).toList(),
                      ),
                    ],
                  ),
                )),
            Row(
              children: [
                GestureDetector(
                  onTap: () => setState(() => _customMode = true),
                  child: Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _customMode ? Colors.black : Colors.grey, width: _customMode ? 2.5 : 1),
                    ),
                    child: const Icon(Icons.colorize, size: 16),
                  ),
                ),
                const SizedBox(width: 10),
                const Text('Custom (any color)', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            if (_customMode) ...[
              const SizedBox(height: 20),
              Container(height: 44, decoration: BoxDecoration(color: _current, borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 12),
              _slider('R', _r, Colors.red, (v) => setState(() { _r = v; _hexController.text = _toHex(_current); })),
              _slider('G', _g, Colors.green, (v) => setState(() { _g = v; _hexController.text = _toHex(_current); })),
              _slider('B', _b, Colors.blue, (v) => setState(() { _b = v; _hexController.text = _toHex(_current); })),
            ],
            const SizedBox(height: 12),
              TextField(
                controller: _hexController,
                maxLength: 7,
                decoration: const InputDecoration(
                  labelText: 'Hex code',
                  prefixIcon: Icon(Icons.tag, size: 18),
                  border: OutlineInputBorder(),
                  counterText: '',
                  isDense: true,
                ),
                textCapitalization: TextCapitalization.characters,
                onChanged: _applyHex,
              ),
              // Batch 3: real-time WCAG badge, shown for every color (not
            // just custom-mode) since a curated swatch can be a poor
            // choice too -- premium apps don't get an accessibility pass
            // just because the color came from a preset list.
            const SizedBox(height: 16),
            _contrastRow(),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _current), child: const Text('Apply')),
      ],
    );
  }

  Widget _slider(String label, int value, Color trackColor, ValueChanged<int> onChanged) {
    return Row(
      children: [
        SizedBox(width: 16, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 0, max: 255,
            activeColor: trackColor,
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        SizedBox(width: 32, child: Text('$value')),
      ],
    );
  }

  /// Two badges, not one -- a color usually gets used both as text-on-
  /// white (e.g. an outlined chip) and as a fill with white text on top
  /// (e.g. a filled button), so both directions matter and neither one
  /// alone tells the whole story.
  Widget _contrastRow() {
    final vsWhite = ContrastUtils.contrastRatio(_current, Colors.white);
    final vsBlack = ContrastUtils.contrastRatio(_current, Colors.black);
    return Row(
      children: [
        Expanded(child: _contrastBadge('vs White', vsWhite)),
        const SizedBox(width: 8),
        Expanded(child: _contrastBadge('vs Black', vsBlack)),
      ],
    );
  }

  Widget _contrastBadge(String label, double ratio) {
    final level = ContrastUtils.levelFor(ratio);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: level.badgeColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: level.badgeColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: level.badgeColor.withValues(alpha: 0.85))),
          Text(
            '${ratio.toStringAsFixed(1)}:1 · ${level.label}',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: level.badgeColor),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
