import 'package:flutter/material.dart';
import '../services/api_service.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _api = ApiService();
  late Future<List<Map<String, dynamic>>> _future;
  // 'next30' matches the screen's original default exactly (today ->
  // +30 days), so nothing changes for anyone until they actually touch
  // the new filter row.
  String _range = 'next30';

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
        // Monday of this week through Sunday.
        final monday = now.subtract(Duration(days: now.weekday - 1));
        return _api.getCalendar(from: iso(monday), to: iso(monday.add(const Duration(days: 6))));
      case 'month':
        final firstOfMonth = DateTime(now.year, now.month, 1);
        final firstOfNextMonth = DateTime(now.year, now.month + 1, 1);
        return _api.getCalendar(from: iso(firstOfMonth), to: iso(firstOfNextMonth.subtract(const Duration(days: 1))));
      case 'overdue':
        // From far enough back to catch any stale pending item, through
        // today -- the point of this view is "what did we already miss."
        return _api.getCalendar(from: iso(now.subtract(const Duration(days: 90))), to: iso(now));
      case 'next30':
      default:
        return _api.getCalendar(); // no params -- exact original behavior
    }
  }

  void _setRange(String r) => setState(() {
        _range = r;
        _future = _fetchForRange();
      });

  Map<String, List<Map<String, dynamic>>> _groupByDate(List<Map<String, dynamic>> items) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final item in items) {
      final date = (item['due_at'] as String).split('T').first;
      grouped.putIfAbsent(date, () => []).add(item);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Calendar')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  ('next30', 'Next 30 Days'),
                  ('week', 'This Week'),
                  ('month', 'This Month'),
                  ('overdue', 'Overdue'),
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
                final items = snapshot.data ?? [];
                if (items.isEmpty) {
                  return const Center(child: Text('Nothing scheduled in this range', style: TextStyle(color: Colors.grey)));
                }
                final grouped = _groupByDate(items);
                final dates = grouped.keys.toList()..sort();

                return ListView.builder(
                  itemCount: dates.length,
                  itemBuilder: (context, i) {
                    final date = dates[i];
                    final dayItems = grouped[date]!;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                          child: Text(date, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                        ),
                        ...dayItems.map((item) => ListTile(
                              leading: Icon(item['type'] == 'task' ? Icons.checklist : Icons.alarm,
                                  color: item['type'] == 'task' ? Colors.blue : Colors.deepOrange),
                              title: Text(item['title']),
                              subtitle: Text((item['due_at'] as String).split('T').last),
                            )),
                        const Divider(height: 1),
                      ],
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
