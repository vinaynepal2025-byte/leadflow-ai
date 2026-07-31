import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'lead_detail_screen.dart';

class ParentCrmScreen extends StatefulWidget {
  const ParentCrmScreen({super.key});

  @override
  State<ParentCrmScreen> createState() => _ParentCrmScreenState();
}

class _ParentCrmScreenState extends State<ParentCrmScreen> {
  final _api = ApiService();
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.getLeads(hasParent: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Parent CRM')),
      body: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final leads = snapshot.data ?? [];
          if (leads.isEmpty) {
            return const Center(
              child: Text('No leads with guardian info on file yet', style: TextStyle(color: Colors.grey)),
            );
          }
          return ListView.separated(
            itemCount: leads.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final l = leads[i];
              return ListTile(
                leading: const Icon(Icons.family_restroom_outlined),
                title: Text(l.fullName),
                subtitle: const Text('Tap to view guardian contact'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LeadDetailScreen(leadId: l.id))),
              );
            },
          );
        },
      ),
    );
  }
}
