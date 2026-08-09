import 'package:flutter/material.dart';
import '../services/api_service.dart';

class LeadNotesScreen extends StatefulWidget {
  final String leadId;
  final String leadName;
  const LeadNotesScreen({super.key, required this.leadId, required this.leadName});

  @override
  State<LeadNotesScreen> createState() => _LeadNotesScreenState();
}

class _LeadNotesScreenState extends State<LeadNotesScreen> {
  final _api = ApiService();
  final _noteCtrl = TextEditingController();
  List<Map<String, dynamic>> _notes = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final notes = await _api.getLeadNotes(widget.leadId);
    if (!mounted) return;
    setState(() {
      _notes = notes;
      _loading = false;
    });
  }

  Future<void> _send() async {
    final text = _noteCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await _api.createLeadNote(leadId: widget.leadId, noteText: text, authorName: null);
      _noteCtrl.clear();
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not add note: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _togglePin(Map<String, dynamic> note) async {
    try {
      await _api.updateLeadNote(note['id'], pinned: !(note['pinned'] == true));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update: $e')));
    }
  }

  Future<void> _delete(Map<String, dynamic> note) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete note?'),
        content: const Text('This cannot be undone.'),
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
      await _api.deleteLeadNote(note['id']);
      _load();
    }
  }

  String _timeAgo(String isoOrText) {
    DateTime? dt;
    try {
      dt = DateTime.parse(isoOrText.contains('T') ? isoOrText : '${isoOrText.replaceFirst(' ', 'T')}Z');
    } catch (_) {
      return isoOrText;
    }
    final diff = DateTime.now().toUtc().difference(dt.toUtc());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Notes — ${widget.leadName}')),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _notes.isEmpty
                    ? const Center(
                        child: Text('No notes yet — add context for the next follow-up', style: TextStyle(color: Colors.grey)),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _notes.length,
                          itemBuilder: (context, i) {
                            final note = _notes[i];
                            final pinned = note['pinned'] == true;
                            return Card(
                              color: pinned ? Colors.amber.withValues(alpha: 0.08) : null,
                              margin: const EdgeInsets.only(bottom: 8),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(note['note_text'] ?? ''),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Text(
                                          '${note['author_name'] ?? 'Someone'} • ${_timeAgo(note['created_at'] ?? '')}',
                                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                                        ),
                                        const Spacer(),
                                        IconButton(
                                          icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined, size: 18),
                                          tooltip: pinned ? 'Unpin' : 'Pin',
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () => _togglePin(note),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                          tooltip: 'Delete',
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () => _delete(note),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _noteCtrl,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Add a note — e.g. follow-up context, budget concerns...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: _sending
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send),
                    onPressed: _sending ? null : _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
