import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';

class MeetingsScreen extends StatefulWidget {
  final String leadId;
  const MeetingsScreen({super.key, required this.leadId});

  @override
  State<MeetingsScreen> createState() => _MeetingsScreenState();
}

class _MeetingsScreenState extends State<MeetingsScreen> {
  final _api = ApiService();
  late Future<List<Map<String, dynamic>>> _future;

  static const types = ['Counseling', 'Virtual Campus Tour', 'Physical Campus Visit', 'Parent Meeting', 'Demo Class', 'Other'];
  static const statuses = ['scheduled', 'completed', 'no-show', 'cancelled', 'rescheduled'];

  @override
  void initState() {
    super.initState();
    _future = _api.getMeetings(leadId: widget.leadId);
  }

  void _refresh() => setState(() => _future = _api.getMeetings(leadId: widget.leadId));

  Future<void> _scheduleDialog() async {
    String type = types.first;
    final titleCtrl = TextEditingController();
    final dateCtrl = TextEditingController();
    final linkCtrl = TextEditingController();
    final campusCtrl = TextEditingController();
    DateTime? picked;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Schedule Meeting'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => setDialogState(() => type = v ?? type),
                ),
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title')),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(picked == null ? 'Pick date & time' : picked.toString().substring(0, 16)),
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context, initialDate: DateTime.now(),
                      firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date == null || !context.mounted) return;
                    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                    if (time == null) return;
                    setDialogState(() => picked = DateTime(date.year, date.month, date.day, time.hour, time.minute));
                  },
                ),
                if (type.contains('Campus'))
                  TextField(controller: campusCtrl, decoration: const InputDecoration(labelText: 'Campus name')),
                TextField(controller: linkCtrl, decoration: const InputDecoration(labelText: 'Meeting link (Zoom/Meet) — optional')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Schedule')),
          ],
        ),
      ),
    );

    if (saved == true && titleCtrl.text.trim().isNotEmpty && picked != null) {
      await _api.createMeeting(
        leadId: widget.leadId,
        meetingType: type,
        title: titleCtrl.text.trim(),
        scheduledAt: picked!.toIso8601String(),
        meetingLink: linkCtrl.text.trim().isEmpty ? null : linkCtrl.text.trim(),
        campusName: campusCtrl.text.trim().isEmpty ? null : campusCtrl.text.trim(),
        hostName: 'Counselor',
      );
      _refresh();
    }
  }

  Future<void> _recordOutcome(Map<String, dynamic> meeting) async {
    String status = 'completed';
    final notesCtrl = TextEditingController();
    String interest = 'warm';

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Record Outcome'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: statuses.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) => setDialogState(() => status = v ?? status),
              ),
              if (status == 'completed')
                DropdownButtonFormField<String>(
                  initialValue: interest,
                  decoration: const InputDecoration(labelText: 'Interest level'),
                  items: const ['hot', 'warm', 'cold'].map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
                  onChanged: (v) => setDialogState(() => interest = v ?? interest),
                ),
              TextField(controller: notesCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Outcome notes')),
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
      await _api.updateMeeting(meeting['id'], {
        'status': status,
        'outcome_notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
        if (status == 'completed') 'interest_level': interest,
      });
      _refresh();
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed': return Colors.green;
      case 'no-show': return Colors.red;
      case 'cancelled': return Colors.grey;
      default: return Colors.blue;
    }
  }

  IconData _typeIcon(String type) {
    if (type.contains('Campus')) return Icons.school;
    if (type == 'Parent Meeting') return Icons.family_restroom;
    if (type == 'Demo Class') return Icons.play_lesson;
    return Icons.groups;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meetings & Campus Tours')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final meetings = snapshot.data ?? [];
          if (meetings.isEmpty) {
            return const Center(child: Text('No meetings scheduled yet', style: TextStyle(color: Colors.grey)));
          }
          return ListView.separated(
            itemCount: meetings.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final m = meetings[i];
              return ListTile(
                leading: Icon(_typeIcon(m['meeting_type']), color: _statusColor(m['status'])),
                title: Text(m['title']),
                subtitle: Text('${m['meeting_type']} • ${m['scheduled_at']}\nStatus: ${m['status']}${m['interest_level'] != null ? ' • ${m['interest_level']}' : ''}'),
                isThreeLine: true,
                trailing: m['status'] == 'scheduled'
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (m['meeting_link'] != null)
                            IconButton(
                              icon: const Icon(Icons.videocam, size: 20),
                              onPressed: () => launchUrl(Uri.parse(m['meeting_link']), mode: LaunchMode.externalApplication),
                            ),
                          TextButton(onPressed: () => _recordOutcome(m), child: const Text('Outcome', style: TextStyle(fontSize: 11))),
                        ],
                      )
                    : null,
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scheduleDialog,
        icon: const Icon(Icons.add),
        label: const Text('Schedule'),
      ),
    );
  }
}
