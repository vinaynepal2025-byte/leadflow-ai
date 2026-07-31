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
