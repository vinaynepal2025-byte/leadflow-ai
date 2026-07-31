import 'package:flutter/material.dart';
import '../services/api_service.dart';

class AuditScreen extends StatefulWidget {
  final String? leadId;
  const AuditScreen({super.key, this.leadId});

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  final _api = ApiService();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.getAuditTimeline(leadId: widget.leadId);
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'communication':
        return Icons.chat_bubble_outline;
      case 'document':
        return Icons.description_outlined;
      case 'admission':
        return Icons.school_outlined;
      case 'fee':
        return Icons.payments_outlined;
      default:
        return Icons.circle;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Audit Timeline')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final events = snapshot.data ?? [];
          if (events.isEmpty) {
            return const Center(child: Text('No activity yet', style: TextStyle(color: Colors.grey)));
          }
          return ListView.separated(
            itemCount: events.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final e = events[i];
              return ListTile(
                leading: Icon(_iconFor(e['type'])),
                title: Text(e['summary']),
                subtitle: Text(e['at']),
              );
            },
          );
        },
      ),
    );
  }
}
