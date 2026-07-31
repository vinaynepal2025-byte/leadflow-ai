import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'lead_detail_screen.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final _api = ApiService();
  late Future<List<Map<String, dynamic>>> _allFuture;
  late Future<List<Map<String, dynamic>>> _unrepliedFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _allFuture = _api.getInbox();
    _unrepliedFuture = _api.getUnrepliedInbox();
  }

  IconData _channelIcon(String channel) {
    switch (channel) {
      case 'whatsapp':
      case 'whatsapp-link':
        return Icons.chat;
      case 'email':
        return Icons.email_outlined;
      case 'call':
        return Icons.phone;
      default:
        return Icons.notes;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Inbox'),
          bottom: const TabBar(tabs: [Tab(text: 'Needs Reply'), Tab(text: 'All Activity')]),
        ),
        body: TabBarView(
          children: [
            RefreshIndicator(
              onRefresh: () async => setState(_load),
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _unrepliedFuture,
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
                        Center(child: Text('All caught up! No pending replies. 🎉', style: TextStyle(color: Colors.grey))),
                      ],
                    );
                  }
                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final m = items[i];
                      return ListTile(
                        leading: Icon(_channelIcon(m['channel']), color: Colors.orange),
                        title: Text(m['lead_name'] ?? 'Unknown'),
                        subtitle: Text(m['body'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: Text(m['created_at'].toString().substring(5, 16), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LeadDetailScreen(leadId: m['lead_id']))),
                      );
                    },
                  );
                },
              ),
            ),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _allFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snapshot.data ?? [];
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final m = items[i];
                    final inbound = m['direction'] == 'inbound';
                    return ListTile(
                      leading: Icon(_channelIcon(m['channel']), color: inbound ? Colors.green : Colors.blue),
                      title: Text(m['lead_name'] ?? 'Unknown'),
                      subtitle: Text('${inbound ? "←" : "→"} ${m['body'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Text(m['created_at'].toString().substring(5, 16), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LeadDetailScreen(leadId: m['lead_id']))),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
