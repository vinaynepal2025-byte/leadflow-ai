import 'package:flutter/material.dart';
import '../services/api_service.dart';

class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  final _api = ApiService();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.getTeam();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Team')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final team = snapshot.data ?? [];
          if (team.isEmpty) {
            return const Center(child: Text('No team members yet', style: TextStyle(color: Colors.grey)));
          }
          return ListView.separated(
            itemCount: team.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final m = team[i];
              return ListTile(
                leading: CircleAvatar(child: Text(m['full_name'][0].toUpperCase())),
                title: Text(m['full_name']),
                subtitle: Text(m['email']),
                trailing: Chip(label: Text(m['role'], style: const TextStyle(fontSize: 11))),
              );
            },
          );
        },
      ),
    );
  }
}
