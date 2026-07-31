import 'package:flutter/material.dart';
import '../services/api_service.dart';

class PerformanceScreen extends StatefulWidget {
  const PerformanceScreen({super.key});

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> {
  final _api = ApiService();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.getPerformance();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Performance')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data ?? [];
          if (rows.isEmpty) {
            return const Center(child: Text('No assigned leads yet', style: TextStyle(color: Colors.grey)));
          }
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final r = rows[i];
              return ListTile(
                leading: CircleAvatar(child: Text('${i + 1}')),
                title: Text(r['counselor']),
                subtitle: Text('${r['total_leads']} leads • ${r['admissions']} admissions • ${r['pending_reminders']} pending'),
                trailing: Text('${r['conversion_rate_percent']}%',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              );
            },
          );
        },
      ),
    );
  }
}
