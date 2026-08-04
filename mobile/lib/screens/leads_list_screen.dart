import 'package:flutter/material.dart';
import '../models/lead.dart';
import '../services/api_service.dart';
import '../widgets/stage_chip.dart';
import '../widgets/swipeable_card.dart';
import '../l10n/app_strings.dart';
import 'lead_detail_screen.dart';
import 'add_lead_screen.dart';
import 'import_contacts_screen.dart';
import 'excel_import_export_screen.dart';

class LeadsListScreen extends StatefulWidget {
  const LeadsListScreen({super.key});

  @override
  State<LeadsListScreen> createState() => _LeadsListScreenState();
}

class _LeadsListScreenState extends State<LeadsListScreen> {
  final ApiService _api = ApiService();
  late Future<List<Lead>> _leadsFuture;
  List<Map<String, dynamic>> _stages = [];
  String? _stageFilter;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _leadsFuture = _api.getLeads();
    _loadStages();
  }

  Future<void> _loadStages() async {
    final stages = await _api.getPipelineStages();
    if (mounted) setState(() => _stages = stages);
  }

  void _refresh() {
    setState(() {
      _leadsFuture = _api.getLeads(stage: _stageFilter);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LeadFlow AI', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'Import CSV',
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const ImportContactsScreen()));
              _refresh();
            },
          ),
          IconButton(
            icon: const Icon(Icons.table_view),
            tooltip: 'Custom Import / Export',
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const ExcelImportExportScreen()));
              _refresh();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: context.tr('search_leads'),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _filterChip(null, 'All'),
                for (final s in _stages) _filterChip(s['name'] as String, s['name'] as String),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _refresh(),
              child: FutureBuilder<List<Lead>>(
                future: _leadsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _errorState(snapshot.error.toString());
                  }
                  final leads = (snapshot.data ?? [])
                      .where((l) => l.fullName.toLowerCase().contains(_searchQuery))
                      .toList();
                  if (leads.isEmpty) {
                    return _emptyState();
                  }
                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: leads.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) => _leadTile(leads[i]),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(context.tr('add_lead')),
        onPressed: () async {
          final created = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const AddLeadScreen()),
          );
          if (created == true) _refresh();
        },
      ),
    );
  }

  Widget _filterChip(String? stage, String label) {
    final selected = _stageFilter == stage;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() => _stageFilter = stage);
          _refresh();
        },
      ),
    );
  }

  Widget _leadTile(Lead lead) {
    return SwipeableCard(
      dismissKey: lead.id,
      onSwipeAction: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete lead?'),
            content: Text('Delete ${lead.fullName}? This cannot be undone.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
            ],
          ),
        );
        if (confirmed == true) {
          await _api.deleteLead(lead.id);
          _refresh();
        }
      },
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: stageColor(lead.stage).withValues(alpha: 0.15),
          child: Text(
            lead.fullName.isNotEmpty ? lead.fullName[0].toUpperCase() : '?',
            style: TextStyle(color: stageColor(lead.stage), fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(lead.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(lead.source ?? lead.phone ?? 'No source'),
        trailing: StageChip(stage: lead.stage),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => LeadDetailScreen(leadId: lead.id)),
          );
          _refresh(); // stage may have changed in detail screen
        },
      ),
    );
  }

  Widget _emptyState() {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: constraints.maxHeight,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline, size: 56, color: Colors.grey),
                SizedBox(height: 12),
                Text(context.tr('no_leads_yet'), style: const TextStyle(color: Colors.grey, fontSize: 16)),
                SizedBox(height: 4),
                Text('Tap "Add Lead" to create your first one',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorState(String error) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: constraints.maxHeight,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_off, size: 48, color: Colors.redAccent),
                  const SizedBox(height: 12),
                  const Text('Could not reach the backend', textAlign: TextAlign.center),
                  const SizedBox(height: 6),
                  Text(error, style: const TextStyle(fontSize: 12, color: Colors.grey),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: _refresh, child: const Text('Retry')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
