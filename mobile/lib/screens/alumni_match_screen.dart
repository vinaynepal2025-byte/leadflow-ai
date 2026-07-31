import 'package:flutter/material.dart';
import '../services/api_service.dart';

class AlumniMatchScreen extends StatefulWidget {
  final String leadId;
  const AlumniMatchScreen({super.key, required this.leadId});

  @override
  State<AlumniMatchScreen> createState() => _AlumniMatchScreenState();
}

class _AlumniMatchScreenState extends State<AlumniMatchScreen> {
  final _api = ApiService();
  late Future<Map<String, dynamic>> _future;
  final Set<String> _requested = {};

  @override
  void initState() {
    super.initState();
    _future = _api.getAlumniMatches(widget.leadId);
  }

  Future<void> _connect(String studentId) async {
    await _api.requestAlumniConnection(leadId: widget.leadId, studentId: studentId);
    setState(() => _requested.add(studentId));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connection requested — the alumnus will be notified')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alumni Network')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          final matches = (data['matches'] as List? ?? []).cast<Map<String, dynamic>>();
          final note = data['note'] as String?;

          if (note != null) {
            return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(note, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey))));
          }
          if (matches.isEmpty) {
            return const Center(child: Text('No available alumni at this institution yet', style: TextStyle(color: Colors.grey)));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: matches.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final m = matches[i];
              final requested = _requested.contains(m['student_id']);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(child: Text(m['full_name'][0])),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(m['full_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                Text('${m['course_name'] ?? ''} • Semester ${m['current_semester']} • ${m['status']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (m['bio'] != null) ...[
                        const SizedBox(height: 8),
                        Text(m['bio'], style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
                      ],
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: Icon(requested ? Icons.check : Icons.connect_without_contact, size: 18),
                          label: Text(requested ? 'Requested' : 'Request Connection'),
                          onPressed: requested ? null : () => _connect(m['student_id']),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
