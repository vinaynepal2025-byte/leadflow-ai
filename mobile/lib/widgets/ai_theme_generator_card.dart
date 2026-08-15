import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../theme/appearance_settings.dart';
import '../theme/glass_settings.dart';

/// A self-contained "describe the look you want, AI builds it" card.
/// Portable by design: only depends on AppearanceSettings/GlassSettings
/// (provider-scoped above it) and ApiService.generateAiTheme -- drop this
/// single file into any other Flutter project that has a matching
/// theme/ folder and a POST /ai/generate-theme backend endpoint.
class AiThemeGeneratorCard extends StatefulWidget {
  const AiThemeGeneratorCard({super.key});

  @override
  State<AiThemeGeneratorCard> createState() => _AiThemeGeneratorCardState();
}

class _AiThemeGeneratorCardState extends State<AiThemeGeneratorCard> {
  final ApiService _api = ApiService();
  final TextEditingController _controller = TextEditingController();
  bool _generating = false;
  String? _error;
  String? _lastAppliedName;

  Future<void> _generate() async {
    final prompt = _controller.text.trim();
    if (prompt.isEmpty) {
      setState(() => _error = 'Describe the look you want first — e.g. "premium and trustworthy for a medical admissions consultancy".');
      return;
    }
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final theme = await _api.generateAiTheme(prompt);
      final appearance = context.read<AppearanceSettings>();
      final glass = context.read<GlassSettings>();
      await appearance.applyGeneratedTheme(theme, glass.setEnabled, glass.setBlur);
      if (mounted) {
        setState(() {
          final fontMatch = FontPairing.values.where((f) => f.name == theme['font']);
          final fontLabel = fontMatch.isNotEmpty ? fontMatch.first.label.split(' (').first : 'Custom';
          _lastAppliedName = '${theme['name'] as String? ?? 'AI Theme'} · $fontLabel';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF6D28D9), Color(0xFF1D4ED8)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('AI Design Engine', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Describe the look you want — colors, mood, and fonts are generated and applied instantly.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 2),
          const Text(
            'Every result is contrast-checked for readability before it\'s applied.',
            style: TextStyle(color: Colors.white54, fontSize: 10.5, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            enabled: !_generating,
            maxLines: 2,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'e.g. "premium and trustworthy for a medical consultancy"',
              hintStyle: const TextStyle(color: Colors.white54, fontSize: 12),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _generating ? null : _generate,
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF1D4ED8)),
              child: _generating
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Generate'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
          if (_lastAppliedName != null) ...[
            const SizedBox(height: 8),
            Text('Applied: $_lastAppliedName ✓', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }
}
