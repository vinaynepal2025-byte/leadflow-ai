import 'package:flutter/material.dart';
import '../services/api_service.dart';

class TriageTestScreen extends StatefulWidget {
  const TriageTestScreen({super.key});

  @override
  State<TriageTestScreen> createState() => _TriageTestScreenState();
}

class _TriageTestScreenState extends State<TriageTestScreen> {
  final _api = ApiService();
  final _messageCtrl = TextEditingController();
  bool _testing = false;
  Map<String, dynamic>? _result;

  Future<void> _test() async {
    if (_messageCtrl.text.trim().isEmpty) return;
    setState(() {
      _testing = true;
      _result = null;
    });
    try {
      final result = await _api.testTriage(_messageCtrl.text.trim());
      setState(() => _result = result);
    } finally {
      setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Smart Triage — Test')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Type a message like a lead would send on WhatsApp, and see whether the app would auto-reply from your Knowledge Base, or escalate to a counselor. Nothing is actually sent.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _messageCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Test message', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _testing ? null : _test,
              child: _testing ? const CircularProgressIndicator(color: Colors.white) : const Text('Run Triage Test'),
            ),
            const SizedBox(height: 20),
            if (_result != null) _buildResult(),
          ],
        ),
      ),
    );
  }

  Widget _buildResult() {
    final r = _result!;
    final isAutoReply = r['action'] == 'auto_reply';
    return Card(
      color: isAutoReply ? Colors.green.withValues(alpha: 0.06) : Colors.orange.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isAutoReply ? Icons.smart_toy_outlined : Icons.person_outline, color: isAutoReply ? Colors.green : Colors.orange),
                const SizedBox(width: 8),
                Text(isAutoReply ? 'Would Auto-Reply' : 'Would Escalate to Human', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            if (isAutoReply) ...[
              Text('Reply: "${r['reply']}"'),
              const SizedBox(height: 6),
              Text('Source: ${r['source_article']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ] else ...[
              Text('Reason: ${r['reason']}'),
              if (r['best_guess_article'] != null)
                Text('Closest article: ${r['best_guess_article']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ],
        ),
      ),
    );
  }
}
