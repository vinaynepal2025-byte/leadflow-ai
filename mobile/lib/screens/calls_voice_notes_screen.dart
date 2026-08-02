import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';

class CallsVoiceNotesScreen extends StatelessWidget {
  final String leadId;
  const CallsVoiceNotesScreen({super.key, required this.leadId});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Calls & Voice Notes'),
          bottom: const TabBar(tabs: [Tab(text: 'Call Log'), Tab(text: 'Voice Notes')]),
        ),
        body: TabBarView(children: [_CallLogTab(leadId: leadId), _VoiceNotesTab(leadId: leadId)]),
      ),
    );
  }
}

class _CallLogTab extends StatefulWidget {
  final String leadId;
  const _CallLogTab({required this.leadId});

  @override
  State<_CallLogTab> createState() => _CallLogTabState();
}

class _CallLogTabState extends State<_CallLogTab> {
  final _api = ApiService();
  late Future<List<Map<String, dynamic>>> _future;
  static const outcomes = ['connected', 'no-answer', 'busy', 'wrong-number', 'voicemail', 'call-back-requested', 'switched-off', 'not-reachable', 'converted', 'not-interested'];

  @override
  void initState() {
    super.initState();
    _future = _api.getCalls(widget.leadId);
  }

  void _refresh() => setState(() => _future = _api.getCalls(widget.leadId));

  Future<void> _logDialog() async {
    String outcome = outcomes.first;
    final notesCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Log Call'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: outcome,
                items: outcomes.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
                onChanged: (v) => setDialogState(() => outcome = v ?? outcome),
                decoration: const InputDecoration(labelText: 'Outcome'),
              ),
              TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes (optional)')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved == true) {
      await _api.logCall(leadId: widget.leadId, outcome: outcome, notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(), calledBy: 'Counselor');
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final calls = snapshot.data ?? [];
          if (calls.isEmpty) return const Center(child: Text('No calls logged yet', style: TextStyle(color: Colors.grey)));
          return ListView.separated(
            itemCount: calls.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final c = calls[i];
              return ListTile(
                leading: Icon(c['outcome'] == 'connected' ? Icons.call : Icons.call_missed, color: c['outcome'] == 'connected' ? Colors.green : Colors.orange),
                title: Text(c['outcome']),
                subtitle: Text(c['notes'] ?? c['created_at']),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(onPressed: _logDialog, child: const Icon(Icons.add_call)),
    );
  }
}

class _VoiceNotesTab extends StatefulWidget {
  final String leadId;
  const _VoiceNotesTab({required this.leadId});

  @override
  State<_VoiceNotesTab> createState() => _VoiceNotesTabState();
}

class _VoiceNotesTabState extends State<_VoiceNotesTab> {
  final _api = ApiService();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.getVoiceNotes(widget.leadId);
  }

  void _refresh() => setState(() => _future = _api.getVoiceNotes(widget.leadId));

  Future<void> _upload() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (result == null || result.files.single.path == null) return;
    await _api.uploadVoiceNote(leadId: widget.leadId, filePath: result.files.single.path!, fileName: result.files.single.name, recordedBy: 'Counselor');
    _refresh();
  }

  Future<void> _openNote(Map<String, dynamic> note) async {
    final transcriptCtrl = TextEditingController(text: note['transcript'] ?? '');
    String? summary = note['ai_summary'];
    String? error;
    bool summarizing = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(note['file_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(
                  controller: transcriptCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Transcript (type or paste)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () async {
                    await _api.attachTranscript(note['id'], transcriptCtrl.text.trim());
                    _refresh();
                  },
                  child: const Text('Save Transcript'),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: Text(summarizing ? 'Summarizing...' : 'AI Summarize'),
                  onPressed: summarizing
                      ? null
                      : () async {
                          setSheetState(() {
                            summarizing = true;
                            error = null;
                          });
                          try {
                            final s = await _api.summarizeVoiceNote(note['id']);
                            setSheetState(() => summary = s);
                          } catch (e) {
                            setSheetState(() => error = e.toString().replaceFirst('Exception: ', ''));
                          } finally {
                            setSheetState(() => summarizing = false);
                          }
                        },
                ),
                if (error != null) Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!, style: const TextStyle(color: Colors.redAccent)),
                ),
                if (summary != null) Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(summary!),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final notes = snapshot.data ?? [];
          if (notes.isEmpty) return const Center(child: Text('No voice notes yet', style: TextStyle(color: Colors.grey)));
          return ListView.separated(
            itemCount: notes.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final n = notes[i];
              return ListTile(
                leading: const Icon(Icons.mic_outlined),
                title: Text(n['file_name']),
                subtitle: Text(n['ai_summary'] != null ? 'Summarized' : (n['transcript'] != null ? 'Transcript added' : 'No transcript yet')),
                onTap: () => _openNote(n),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(onPressed: _upload, child: const Icon(Icons.upload_file)),
    );
  }
}
