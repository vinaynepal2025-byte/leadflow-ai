import 'package:flutter/material.dart';
import '../models/reminder.dart';
import '../services/api_service.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  final ApiService _api = ApiService();
  late Future<List<ReminderItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.getReminders(status: 'pending');
  }

  void _refresh() => setState(() => _future = _api.getReminders(status: 'pending'));

  Future<void> _markDone(ReminderItem r) async {
    await _api.markReminderDone(r.id);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Follow-ups')),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<ReminderItem>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final reminders = snapshot.data ?? [];
            if (reminders.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 100),
                  Center(child: Text('No pending follow-ups 🎉', style: TextStyle(color: Colors.grey))),
                ],
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: reminders.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final r = reminders[i];
                return ListTile(
                  leading: const Icon(Icons.alarm, color: Colors.deepOrange),
                  title: Text(r.title),
                  subtitle: Text('Due: ${r.dueAt}${r.assignedTo != null ? " • ${r.assignedTo}" : ""}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.check_circle_outline, color: Colors.green),
                    onPressed: () => _markDone(r),
                    tooltip: 'Mark done',
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
