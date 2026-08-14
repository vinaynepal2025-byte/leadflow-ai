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
  // 'all' matches the screen's original behavior exactly (lifetime
  // counts, no params sent), so nothing changes until the filter is
  // actually touched.
  String _range = 'all';

  @override
  void initState() {
    super.initState();
    _future = _fetchForRange();
  }

  Future<List<Map<String, dynamic>>> _fetchForRange() {
    final now = DateTime.now();
    String iso(DateTime d) => d.toIso8601String().split('T').first;
    switch (_range) {
      case 'week':
        final monday = now.subtract(Duration(days: now.weekday - 1));
        return _api.getPerformance(from: iso(monday), to: iso(now));
      case 'month':
        final firstOfMonth = DateTime(now.year, now.month, 1);
        return _api.getPerformance(from: iso(firstOfMonth), to: iso(now));
      case 'all':
      default:
        return _api.getPerformance(); // no params -- exact original behavior
    }
  }

  void _setRange(String r) => setState(() {
        _range = r;
        _future = _fetchForRange();
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Performance')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  ('all', 'All Time'),
                  ('week', 'This Week'),
                  ('month', 'This Month'),
                ].map((r) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(r.$2, style: const TextStyle(fontSize: 12)),
                        selected: _range == r.$1,
                        onSelected: (_) => _setRange(r.$1),
                        visualDensity: VisualDensity.compact,
                      ),
                    )).toList(),
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
                final rows = snapshot.data ?? [];
                if (rows.isEmpty) {
                  return const Center(child: Text('No assigned leads in this range', style: TextStyle(color: Colors.grey)));
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
          ),
        ],
      ),
    );
  }
}
