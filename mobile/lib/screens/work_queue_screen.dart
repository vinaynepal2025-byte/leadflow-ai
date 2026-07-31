import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'lead_detail_screen.dart';

class WorkQueueScreen extends StatefulWidget {
  const WorkQueueScreen({super.key});

  @override
  State<WorkQueueScreen> createState() => _WorkQueueScreenState();
}

class _WorkQueueScreenState extends State<WorkQueueScreen> {
  final _api = ApiService();
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.getScoringToday();
  }

  void _refresh() => setState(() => _future = _api.getScoringToday());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Today's Work Queue")),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final d = snapshot.data ?? {};
            final summary = d['summary'] as Map<String, dynamic>? ?? {};
            final priority = (d['priority_calls'] as List? ?? []).cast<Map<String, dynamic>>();
            final atRisk = (d['at_risk'] as List? ?? []).cast<Map<String, dynamic>>();
            final untouched = (d['never_contacted'] as List? ?? []).cast<Map<String, dynamic>>();

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    _summaryChip('🔥 ${summary['hot'] ?? 0}', 'Hot', Colors.red),
                    const SizedBox(width: 8),
                    _summaryChip('🌤 ${summary['warm'] ?? 0}', 'Warm', Colors.orange),
                    const SizedBox(width: 8),
                    _summaryChip('❄ ${summary['cold'] ?? 0}', 'Cold', Colors.blueGrey),
                  ],
                ),
                const SizedBox(height: 20),
                if (priority.isNotEmpty) ...[
                  const Text('🔥 Priority Calls', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  ...priority.map((l) => _leadTile(l, Colors.red)),
                  const SizedBox(height: 20),
                ],
                if (atRisk.isNotEmpty) ...[
                  const Text('⚠️ At Risk', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  ...atRisk.map((l) => _leadTile(l, Colors.orange)),
                  const SizedBox(height: 20),
                ],
                if (untouched.isNotEmpty) ...[
                  const Text('👻 Never Contacted', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  ...untouched.map((l) => ListTile(
                        leading: const Icon(Icons.person_off_outlined, color: Colors.grey),
                        title: Text(l['full_name']),
                        subtitle: Text('Added ${l['created_at']}'),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LeadDetailScreen(leadId: l['id']))),
                      )),
                ],
                if (priority.isEmpty && atRisk.isEmpty && untouched.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: Center(child: Text('All caught up! 🎉', style: TextStyle(color: Colors.grey))),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _summaryChip(String count, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Text(count, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _leadTile(Map<String, dynamic> l, Color accent) {
    final topReason = (l['signals'] as List?)?.isNotEmpty == true ? l['signals'][0]['reason'] : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: accent.withValues(alpha: 0.15),
          child: Text('${l['score']}', style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
        title: Text(l['full_name']),
        subtitle: topReason != null ? Text(topReason, style: const TextStyle(fontSize: 12)) : null,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LeadDetailScreen(leadId: l['lead_id']))),
      ),
    );
  }
}
