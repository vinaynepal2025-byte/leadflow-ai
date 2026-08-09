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
import 'lead_folders_screen.dart';

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
  bool _isTrashView = false;

  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

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
      _leadsFuture = _isTrashView ? _api.getTrashedLeads() : _api.getLeads(stage: _stageFilter);
    });
  }

  void _selectTrashView() {
    setState(() {
      _isTrashView = true;
      _stageFilter = null;
      _exitSelectionMode(clearOnly: true);
    });
    _refresh();
  }

  void _selectStageFilter(String? stage) {
    setState(() {
      _isTrashView = false;
      _stageFilter = stage;
      _exitSelectionMode(clearOnly: true);
    });
    _refresh();
  }

  void _enterSelectionMode(String firstId) {
    setState(() {
      _selectionMode = true;
      _selectedIds..clear()..add(firstId);
    });
  }

  void _exitSelectionMode({bool clearOnly = false}) {
    if (!clearOnly) setState(() {});
    _selectionMode = false;
    _selectedIds.clear();
  }

  void _toggleSelected(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _bulkAction() async {
    if (_selectedIds.isEmpty) return;
    final ids = _selectedIds.toList();
    final isRestore = _isTrashView;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isRestore ? 'Restore leads?' : 'Delete leads?'),
        content: Text(isRestore
            ? 'Restore ${ids.length} lead(s) from Trash?'
            : 'Move ${ids.length} lead(s) to Trash? You can restore them later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(isRestore ? 'Restore' : 'Delete')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final count = isRestore ? await _api.bulkRestoreLeads(ids) : await _api.bulkDeleteLeads(ids);
      setState(() {
        _selectionMode = false;
        _selectedIds.clear();
      });
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isRestore ? '$count lead(s) restored' : '$count lead(s) moved to Trash')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Action failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _selectionMode ? _selectionAppBar() : _normalAppBar(),
      body: Column(
        children: [
          if (!_selectionMode) ...[
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
                  _filterChip(null, 'All', selected: !_isTrashView && _stageFilter == null),
                  for (final s in _stages)
                    _filterChip(s['name'] as String, s['name'] as String, selected: !_isTrashView && _stageFilter == s['name']),
                  const SizedBox(width: 4),
                  const VerticalDivider(width: 1, indent: 8, endIndent: 8),
                  const SizedBox(width: 4),
                  ChoiceChip(
                    avatar: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Trash'),
                    selected: _isTrashView,
                    onSelected: (_) => _selectTrashView(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
          ],
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
                    return _isTrashView ? _emptyTrashState() : _emptyState();
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
      floatingActionButton: (_selectionMode || _isTrashView)
          ? null
          : FloatingActionButton.extended(
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

  PreferredSizeWidget _normalAppBar() {
    return AppBar(
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
        IconButton(
          icon: const Icon(Icons.folder_special),
          tooltip: 'Lead Folders',
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LeadFoldersScreen())),
        ),
      ],
    );
  }

  PreferredSizeWidget _selectionAppBar() {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => setState(_exitSelectionMode),
      ),
      title: Text('${_selectedIds.length} selected'),
      actions: [
        IconButton(
          icon: Icon(_isTrashView ? Icons.restore : Icons.delete_outline),
          tooltip: _isTrashView ? 'Restore selected' : 'Delete selected',
          onPressed: _bulkAction,
        ),
      ],
    );
  }

  Widget _filterChip(String? stage, String label, {required bool selected}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => _selectStageFilter(stage),
      ),
    );
  }

  Widget _leadTile(Lead lead) {
    final selected = _selectedIds.contains(lead.id);

    final tile = ListTile(
      leading: _selectionMode
          ? Checkbox(value: selected, onChanged: (_) => _toggleSelected(lead.id))
          : CircleAvatar(
              backgroundColor: stageColor(lead.stage).withValues(alpha: 0.15),
              child: Text(
                lead.fullName.isNotEmpty ? lead.fullName[0].toUpperCase() : '?',
                style: TextStyle(color: stageColor(lead.stage), fontWeight: FontWeight.bold),
              ),
            ),
      title: Text(lead.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(lead.source ?? lead.phone ?? 'No source'),
      trailing: _isTrashView
          ? IconButton(
              icon: const Icon(Icons.restore),
              tooltip: 'Restore',
              onPressed: () async {
                await _api.restoreLead(lead.id);
                _refresh();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${lead.fullName} restored')));
                }
              },
            )
          : StageChip(stage: lead.stage),
      onTap: () async {
        if (_selectionMode) {
          _toggleSelected(lead.id);
          return;
        }
        if (_isTrashView) return; // no detail-view for trashed leads
        await Navigator.push(context, MaterialPageRoute(builder: (_) => LeadDetailScreen(leadId: lead.id)));
        _refresh();
      },
      onLongPress: _isTrashView ? null : () => _enterSelectionMode(lead.id),
      selected: selected,
      selectedTileColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
    );

    // Trash view and selection-mode both disable the swipe-to-delete
    // gesture — swiping a lead you're about to bulk-act on, or one
    // that's already in Trash, would be confusing/redundant.
    if (_isTrashView || _selectionMode) return tile;

    return SwipeableCard(
      dismissKey: lead.id,
      onSwipeAction: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete lead?'),
            content: Text('Move ${lead.fullName} to Trash? You can restore it later.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
            ],
          ),
        );
        if (confirmed == true) {
          await _api.deleteLead(lead.id);
          _refresh();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${lead.fullName} moved to Trash'),
                action: SnackBarAction(
                  label: 'UNDO',
                  onPressed: () async {
                    await _api.restoreLead(lead.id);
                    _refresh();
                  },
                ),
              ),
            );
          }
        }
      },
      child: tile,
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

  Widget _emptyTrashState() {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: constraints.maxHeight,
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.delete_outline, size: 56, color: Colors.grey),
                SizedBox(height: 12),
                Text('Trash is empty', style: TextStyle(color: Colors.grey, fontSize: 16)),
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
