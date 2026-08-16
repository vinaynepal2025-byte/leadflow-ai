import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

/// Standalone, discoverable Emoji Generator -- Phase 1 scope, stated
/// honestly: AI-suggested Unicode emoji combinations for a described
/// moment/message, reusing the existing /ai/suggest-emojis endpoint
/// (zero new backend, zero new AI cost). This is NOT custom visual
/// emoji/sticker image generation -- that needs a real image-gen
/// provider, deferred to Phase 2 per the same decision already made for
/// the Logo Generator. Previously this capability only existed buried
/// inside the email composer with no separate entry point; this screen
/// is the fix for that discoverability gap.
class EmojiGeneratorScreen extends StatefulWidget {
  const EmojiGeneratorScreen({super.key});

  @override
  State<EmojiGeneratorScreen> createState() => _EmojiGeneratorScreenState();
}

class _EmojiGeneratorScreenState extends State<EmojiGeneratorScreen> {
  static const _favoritesKey = 'emoji_generator_favorites';

  final _api = ApiService();
  final _descCtrl = TextEditingController();
  List<String> _generated = [];
  List<String> _favorites = [];
  bool _generating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _favorites = prefs.getStringList(_favoritesKey) ?? []);
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoritesKey, _favorites);
  }

  Future<void> _generate() async {
    final desc = _descCtrl.text.trim();
    if (desc.isEmpty) return;
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final emojis = await _api.suggestEmojis(desc);
      if (mounted) setState(() => _generated = emojis);
    } catch (e) {
      if (mounted) setState(() => _error = 'Generation failed: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _copyToClipboard(String emoji) {
    Clipboard.setData(ClipboardData(text: emoji));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied $emoji'), duration: const Duration(seconds: 1)),
    );
  }

  void _toggleFavorite(String emoji) {
    setState(() {
      if (_favorites.contains(emoji)) {
        _favorites.remove(emoji);
      } else {
        _favorites.add(emoji);
      }
    });
    _saveFavorites();
  }

  Widget _emojiTile(String emoji) {
    final isFav = _favorites.contains(emoji);
    return GestureDetector(
      onTap: () => _copyToClipboard(emoji),
      onLongPress: () => _toggleFavorite(emoji),
      child: Container(
        width: 60,
        height: 60,
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: isFav ? Border.all(color: Theme.of(context).colorScheme.primary, width: 1.5) : null,
        ),
        child: Stack(
          children: [
            Center(child: Text(emoji, style: const TextStyle(fontSize: 28))),
            if (isFav)
              const Positioned(top: 2, right: 2, child: Icon(Icons.star, size: 12, color: Colors.amber)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Emoji Generator')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Describe a moment or message and get AI-suggested emoji to go with it. Tap to copy, long-press to save as a favourite.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Describe the moment',
                hintText: 'e.g. "student got admission confirmed"',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _generate(),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: _generating
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome),
              label: const Text('Generate Emoji'),
              onPressed: _generating ? null : _generate,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
            if (_generated.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text('Suggestions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              Wrap(children: _generated.map(_emojiTile).toList()),
            ],
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(Icons.star, size: 16, color: Colors.amber),
                SizedBox(width: 6),
                Text('My Favourites', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _favorites.isEmpty
                  ? const Center(
                      child: Text(
                        'No favourites yet -- long-press any suggestion to save it',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : SingleChildScrollView(
                      child: Wrap(children: _favorites.map(_emojiTile).toList()),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
