import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/styled_icon_badge.dart';
import 'customize_registry.dart';

/// "ya main ai se Kisi particular change ke liye command du to poora aap
/// na change hokar kewal wahi particular section ka look change hona
/// chahiye" -- type one instruction ("make the WhatsApp share button
/// glow green"), only that one button/section changes. Two steps, both
/// deterministic where they can be: (1) which item -- resolved on-device
/// via customize_registry.dart's label matching, no AI needed to find a
/// button by name; (2) what style -- sent to the real configured AI
/// provider (POST /ai/restyle-section) to interpret the colour/mood
/// language, same generateJson() layer as the existing AI Theme
/// Generator and AI-suggested emoji.
class AiRestyleScreen extends StatefulWidget {
  const AiRestyleScreen({super.key});

  @override
  State<AiRestyleScreen> createState() => _AiRestyleScreenState();
}

class _AiRestyleScreenState extends State<AiRestyleScreen> {
  final _api = ApiService();
  final _ctrl = TextEditingController();
  late final List<CustomizeRegistryItem> _registry = buildCustomizeRegistry();

  bool _busy = false;
  String? _error;
  CustomizeRegistryItem? _lastAppliedItem;
  Color? _lastAppliedColor;
  String? _lastAppliedVariant;
  Color? _lastAppliedGradientEnd;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color _hexToColor(String hex) {
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.parse(h, radix: 16));
  }

  Future<void> _apply() async {
    final instruction = _ctrl.text.trim();
    if (instruction.isEmpty) return;

    final match = findBestMatch(_registry, instruction);
    if (match == null) {
      setState(() {
        _error = 'Could not tell which button you mean -- try including its name, e.g. "make the WhatsApp button glow green".';
        _lastAppliedItem = null;
      });
      return;
    }

    if (match.source == CustomizeSource.dashboard || match.source == CustomizeSource.leadsList) {
      setState(() {
        _error = '"${match.label}" (${match.category}) doesn\'t support colour/style changes yet -- only show/hide/reorder. Opening it now.';
        _lastAppliedItem = null;
      });
      Navigator.push(context, MaterialPageRoute(builder: (_) => match.screenBuilder()));
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _api.aiRestyleSection(instruction, itemLabel: match.label);
      final color = _hexToColor(result['color'] as String);
      final variant = result['styleVariant'] as String;
      final gradientEnd = result['gradientEnd'] != null ? _hexToColor(result['gradientEnd'] as String) : null;

      await match.applyStyle(
        _api,
        colorHex: result['color'] as String,
        styleVariant: variant,
        gradientEndHex: result['gradientEnd'] as String?,
      );

      if (!mounted) return;
      setState(() {
        _busy = false;
        _lastAppliedItem = match;
        _lastAppliedColor = color;
        _lastAppliedVariant = variant;
        _lastAppliedGradientEnd = gradientEnd;
      });
      _ctrl.clear();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Quick Restyle')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Describe a look for one specific button or section by name -- only that one thing changes, the rest of the app stays exactly as it is.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'e.g. "make the WhatsApp share button glow green"',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _apply(),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome),
              label: Text(_busy ? 'Applying...' : 'Apply'),
              onPressed: _busy ? null : _apply,
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ],
            if (_lastAppliedItem != null) ...[
              const SizedBox(height: 24),
              Card(
                child: ListTile(
                  leading: styledIconBadge(
                    icon: _lastAppliedItem!.icon,
                    color: _lastAppliedColor!,
                    gradientEnd: _lastAppliedGradientEnd,
                    styleVariant: _lastAppliedVariant!,
                  ),
                  title: Text('${_lastAppliedItem!.label} updated'),
                  subtitle: Text('${_lastAppliedItem!.category} -- only this section changed'),
                  trailing: TextButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _lastAppliedItem!.screenBuilder())),
                    child: const Text('View'),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            const Text('Try:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                'make Flyer Studio a purple gradient',
                'give WhatsApp a glow effect in green',
                'make the Automation Hub icon gold',
                'turn Documents into a glass style',
              ].map((s) => ActionChip(label: Text(s, style: const TextStyle(fontSize: 11)), onPressed: null)).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
