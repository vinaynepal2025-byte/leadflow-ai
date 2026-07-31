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

  @override
  void initState() {
    super.initState();
    _future = _api.getCalendar();
  }

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
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return const Center(child: Text('Nothing scheduled in the next 30 days', style: TextStyle(color: Colors.grey)));
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
    );
  }
}
