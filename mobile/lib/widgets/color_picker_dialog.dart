import 'package:flutter/material.dart';

/// A curated set of swatches (quick picks) plus a genuinely free RGB
/// picker for "apni marzi se" (any color the person wants) — not limited
/// to presets.
class ColorPickerDialog extends StatefulWidget {
  final Color initial;
  final String title;
  const ColorPickerDialog({super.key, required this.initial, required this.title});

  static const List<Color> swatches = [
    Color(0xFF1B2A4A), // Ink Navy
    Color(0xFFE8A33D), // Signal Amber
    Color(0xFF2E9E6D), // Success Green
    Color(0xFFE85D4E), // Coral
    Color(0xFF6D28D9), // Violet
    Color(0xFF0E7490), // Teal
    Color(0xFFBE185D), // Rose
    Color(0xFF334155), // Slate Dark
    Color(0xFFB45309), // Bronze
    Color(0xFF1D4ED8), // Royal Blue
    Color(0xFF00E5FF), // Neon Cyan
    Color(0xFFFF00E5), // Neon Magenta
    Color(0xFF39FF14), // Neon Lime
    Color(0xFFFF3131), // Neon Red
  ];

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late int _r, _g, _b;
  bool _customMode = false;

  @override
  void initState() {
    super.initState();
    _r = ((widget.initial.r * 255.0).round()) & 0xff;
    _g = ((widget.initial.g * 255.0).round()) & 0xff;
    _b = ((widget.initial.b * 255.0).round()) & 0xff;
    _customMode = !ColorPickerDialog.swatches.contains(widget.initial);
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
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ...ColorPickerDialog.swatches.map((c) => GestureDetector(
                      onTap: () => setState(() {
                        _r = ((c.r * 255.0).round()) & 0xff;
                        _g = ((c.g * 255.0).round()) & 0xff;
                        _b = ((c.b * 255.0).round()) & 0xff;
                        _customMode = false;
                      }),
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: !_customMode && c.value == _current.value
                              ? Border.all(color: Colors.black, width: 2.5)
                              : null,
                        ),
                      ),
                    )),
                GestureDetector(
                  onTap: () => setState(() => _customMode = true),
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _customMode ? Colors.black : Colors.grey, width: _customMode ? 2.5 : 1),
                    ),
                    child: const Icon(Icons.colorize, size: 18),
                  ),
                ),
              ],
            ),
            if (_customMode) ...[
              const SizedBox(height: 20),
              Container(height: 44, decoration: BoxDecoration(color: _current, borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 12),
              _slider('R', _r, Colors.red, (v) => setState(() => _r = v)),
              _slider('G', _g, Colors.green, (v) => setState(() => _g = v)),
              _slider('B', _b, Colors.blue, (v) => setState(() => _b = v)),
            ],
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
}
