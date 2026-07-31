import 'package:flutter/material.dart';
import '../services/api_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final ApiService _api = ApiService();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.getNotifications();
  }

  void _refresh() => setState(() => _future = _api.getNotifications());

  IconData _iconFor(String? linkType) {
    switch (linkType) {
      case 'lead':
        return Icons.person;
      case 'document':
        return Icons.description;
      case 'fee':
        return Icons.payments;
      default:
        return Icons.notifications;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () async {
              await _api.markAllNotificationsRead();
              _refresh();
            },
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = snapshot.data ?? [];
            if (items.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 100),
                  Center(child: Text('No notifications', style: TextStyle(color: Colors.grey))),
                ],
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final n = items[i];
                final unread = n['read'] == 0;
                return ListTile(
                  leading: Icon(_iconFor(n['link_type']), color: unread ? Colors.blue : Colors.grey),
                  title: Text(n['title'], style: TextStyle(fontWeight: unread ? FontWeight.bold : FontWeight.normal)),
                  subtitle: Text(n['body'] ?? ''),
                  trailing: unread ? const Icon(Icons.circle, size: 10, color: Colors.blue) : null,
                );
              },
            );
          },
        ),
      ),
    );
  }
}
