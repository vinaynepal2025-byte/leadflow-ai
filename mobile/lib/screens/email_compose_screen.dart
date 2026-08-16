import 'dart:async';
import 'package:flutter/material.dart';
import '../models/lead.dart';
import '../services/api_service.dart';

class EmailComposeScreen extends StatefulWidget {
  final Lead lead;
  const EmailComposeScreen({super.key, required this.lead});

  @override
  State<EmailComposeScreen> createState() => _EmailComposeScreenState();
}

class _EmailComposeScreenState extends State<EmailComposeScreen> {
  final _api = ApiService();
  final _subjectCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  bool _sending = false;
  String? _error;

  // AI Suggest Emojis -- debounced so we don't fire a request on every
  // keystroke (expensive and noisy); the request only goes out once
  // typing pauses for 600ms, and any in-flight request from a stale
  // debounce window is simply ignored when it resolves (the _requestId
  // guard below), rather than racing an older response against a newer
  // one and flickering the wrong suggestions onto the screen.
  Timer? _debounce;
  int _requestId = 0;
  List<String> _suggestedEmojis = [];
  bool _suggesting = false;

  @override
  void initState() {
    super.initState();
    _messageCtrl.addListener(_onMessageChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _messageCtrl.removeListener(_onMessageChanged);
    _subjectCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  void _onMessageChanged() {
    _debounce?.cancel();
    final text = _messageCtrl.text.trim();
    if (text.length < 12) {
      // Too short to suggest anything meaningful yet -- clear any
      // stale suggestions from a previous, longer draft rather than
      // leaving them looking attached to the new (very short) text.
      if (_suggestedEmojis.isNotEmpty) setState(() => _suggestedEmojis = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 600), () => _fetchSuggestions(text));
  }

  Future<void> _fetchSuggestions(String text) async {
    final myRequestId = ++_requestId;
    setState(() => _suggesting = true);
    try {
      final emojis = await _api.suggestEmojis(text);
      if (!mounted || myRequestId != _requestId) return; // a newer request has since started
      setState(() {
        _suggestedEmojis = emojis;
        _suggesting = false;
      });
    } catch (_) {
      // Suggestions are a nice-to-have, never worth surfacing an error
      // over -- silently give up for this debounce window.
      if (mounted && myRequestId == _requestId) setState(() => _suggesting = false);
    }
  }

  void _insertEmoji(String emoji) {
    final text = _messageCtrl.text;
    final selection = _messageCtrl.selection;
    final insertAt = selection.isValid ? selection.start : text.length;
    final newText = text.replaceRange(insertAt, insertAt, emoji);
    _messageCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: insertAt + emoji.length),
    );
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await _api.sendEmail(
        leadId: widget.lead.id,
        subject: _subjectCtrl.text.trim(),
        message: _messageCtrl.text.trim(),
        createdBy: 'Counselor',
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// A single suggestion chip with a staggered fade+scale entrance --
  /// each chip's animation is delayed by its own index, so the row
  /// reads as a confident cascade rather than everything popping in at
  /// once. Pure Flutter core (TweenAnimationBuilder), no new package.
  Widget _emojiChip(String emoji, int index) {
    return TweenAnimationBuilder<double>(
      key: ValueKey('$emoji-$index-${_suggestedEmojis.length}'),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      builder: (context, t, child) {
        final delayedT = (t - index * 0.08).clamp(0.0, 1.0);
        return Opacity(
          opacity: delayedT,
          child: Transform.scale(scale: 0.6 + 0.4 * delayedT, child: child),
        );
      },
      child: InkWell(
        onTap: () => _insertEmoji(emoji),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)),
          ),
          child: Text(emoji, style: const TextStyle(fontSize: 20)),
        ),
      ),
    );
  }

  Widget _suggestionRow() {
    if (!_suggesting && _suggestedEmojis.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 15, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6)),
          const SizedBox(width: 6),
          Expanded(
            child: _suggesting
                ? SizedBox(
                    height: 20,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
                      ),
                    ),
                  )
                : Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _suggestedEmojis.asMap().entries.map((e) => _emojiChip(e.value, e.key)).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Email ${widget.lead.fullName}')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('To: ${widget.lead.email ?? "no email on file"}', style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(controller: _subjectCtrl, decoration: const InputDecoration(labelText: 'Subject', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
              controller: _messageCtrl,
              maxLines: 8,
              decoration: const InputDecoration(labelText: 'Message', border: OutlineInputBorder(), alignLabelWithHint: true),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: _suggestionRow(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: (_sending || widget.lead.email == null) ? null : _send,
              child: _sending ? const CircularProgressIndicator(color: Colors.white) : const Text('Send Email'),
            ),
          ],
        ),
      ),
    );
  }
}
