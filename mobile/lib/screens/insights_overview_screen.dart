import 'package:flutter/material.dart';
import '../services/api_service.dart';

class InsightsOverviewScreen extends StatelessWidget {
  const InsightsOverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Insights & Records'),
          bottom: const TabBar(tabs: [Tab(text: 'Alumni Links'), Tab(text: 'Colleges'), Tab(text: 'Data Requests')]),
        ),
        body: const TabBarView(children: [_AlumniTab(), _CollegesTab(), _RequestsTab()]),
      ),
    );
  }
}

class _AlumniTab extends StatefulWidget {
  const _AlumniTab();
  @override
  State<_AlumniTab> createState() => _AlumniTabState();
}

class _AlumniTabState extends State<_AlumniTab> {
  final _api = ApiService();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.getAlumniConnections();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final rows = snapshot.data ?? [];
        if (rows.isEmpty) return const Center(child: Text('No alumni connections yet', style: TextStyle(color: Colors.grey)));
        return ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final r = rows[i];
            return ListTile(
              leading: const Icon(Icons.diversity_3_outlined),
              title: Text('${r['lead_name']} ↔ ${r['student_name']}'),
              subtitle: Text('${r['institution_name']} • ${r['status']}'),
            );
          },
        );
      },
    );
  }
}

class _CollegesTab extends StatefulWidget {
  const _CollegesTab();
  @override
  State<_CollegesTab> createState() => _CollegesTabState();
}

class _CollegesTabState extends State<_CollegesTab> {
  final _api = ApiService();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.getCollegeInsights();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final rows = snapshot.data ?? [];
        if (rows.isEmpty) return const Center(child: Text('Not enough application history yet', style: TextStyle(color: Colors.grey)));
        return ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final r = rows[i];
            return ListTile(
              title: Text(r['institution_name']),
              subtitle: Text('${r['total_applications']} applications • ${r['offers']} offers • ${r['rejections']} rejections'),
              trailing: r['offer_rate_percent'] != null ? Text('${r['offer_rate_percent']}%', style: const TextStyle(fontWeight: FontWeight.bold)) : null,
            );
          },
        );
      },
    );
  }
}

class _RequestsTab extends StatefulWidget {
  const _RequestsTab();
  @override
  State<_RequestsTab> createState() => _RequestsTabState();
}

class _RequestsTabState extends State<_RequestsTab> {
  final _api = ApiService();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.getDataRequests();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final rows = snapshot.data ?? [];
        if (rows.isEmpty) return const Center(child: Text('No data requests logged', style: TextStyle(color: Colors.grey)));
        return ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final r = rows[i];
            return ListTile(
              leading: Icon(r['request_type'] == 'delete' ? Icons.delete_outline : Icons.download_outlined),
              title: Text(r['full_name']),
              subtitle: Text('${r['request_type']} • ${r['status']} • ${r['requested_at']}'),
            );
          },
        );
      },
    );
  }
}
