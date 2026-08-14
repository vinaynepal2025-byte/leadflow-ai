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
  // null = All types, matching the screen's original behavior exactly.
  String? _typeFilter;

  static const _typeLabels = {
    'communication': ('💬', 'Comms'),
    'document': ('📄', 'Docs'),
    'admission': ('🎓', 'Admissions'),
    'fee': ('💰', 'Fees'),
  };

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<Map<String, dynamic>>> _fetch() {
    return _api.getAuditTimeline(leadId: widget.leadId, types: _typeFilter != null ? [_typeFilter!] : null);
  }

  void _setFilter(String? type) => setState(() {
        _typeFilter = type;
        _future = _fetch();
      });

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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('All', style: TextStyle(fontSize: 12)),
                      selected: _typeFilter == null,
                      onSelected: (_) => _setFilter(null),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  ..._typeLabels.entries.map((e) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text('${e.value.$1} ${e.value.$2}', style: const TextStyle(fontSize: 12)),
                          selected: _typeFilter == e.key,
                          onSelected: (_) => _setFilter(e.key),
                          visualDensity: VisualDensity.compact,
                        ),
                      )),
                ],
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
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
          ),
        ],
      ),
    );
  }
}
