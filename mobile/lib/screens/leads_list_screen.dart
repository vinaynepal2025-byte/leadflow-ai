import 'package:flutter/material.dart';
import '../models/lead.dart';
import '../services/api_service.dart';
import '../widgets/stage_chip.dart';
import '../widgets/swipeable_card.dart';
import '../widgets/score_badge.dart';
import '../l10n/app_strings.dart';
import 'lead_detail_screen.dart';
import 'add_lead_screen.dart';
import 'import_contacts_screen.dart';
import 'excel_import_export_screen.dart';
import 'lead_folders_screen.dart';
import 'pipeline_board_screen.dart';
import 'customize_leads_list_screen.dart';

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
  // The most recently rendered (filtered + searched) lead list -- kept so
  // "select all" can select exactly what's currently on screen, not every
  // lead in the tenant regardless of the active stage filter/search.
  List<Lead> _visibleLeads = [];

  // lead_id -> {score, temperature, ...} from /scoring/ranked, fetched
  // once per screen load (not per row) to avoid an N+1 call storm.
  Map<String, Map<String, dynamic>> _scores = {};

  // The row's optional-field config -- see CustomizeLeadsListScreen. Falls
  // back to this fixed default (matching the backend's own DEFAULTS and
  // the row's original fixed layout) if the config can't be loaded, so a
  // network hiccup only costs the ability to customize, not the list itself.
  static const List<Map<String, Object>> _defaultFields = [
    {'field_key': 'field_phone', 'enabled': false, 'sort_order': 0},
    {'field_key': 'field_email', 'enabled': false, 'sort_order': 1},
    {'field_key': 'field_source', 'enabled': true, 'sort_order': 2},
    {'field_key': 'field_assigned_to', 'enabled': false, 'sort_order': 3},
    {'field_key': 'field_created_date', 'enabled': false, 'sort_order': 4},
    {'field_key': 'badge_stage', 'enabled': true, 'sort_order': 5},
    {'field_key': 'badge_score', 'enabled': true, 'sort_order': 6},
  ];
  List<Map<String, dynamic>> _listFields = _defaultFields;

  @override
  void initState() {
    super.initState();
    _leadsFuture = _api.getLeads();
    _loadStages();
    _loadScores();
    _loadListFields();
  }

  Future<void> _loadListFields() async {
    try {
      final fields = await _api.getLeadListFields();
      if (mounted) setState(() => _listFields = fields);
    } catch (_) {
      // Non-critical -- keep the default field set above.
    }
  }

  Future<void> _loadScores() async {
    try {
      final ranked = await _api.getRankedLeads();
      if (!mounted) return;
      setState(() => _scores = {for (final s in ranked) s['lead_id'] as String: s});
    } catch (_) {
      // Non-critical — list still works without score badges.
    }
  }

  Future<void> _loadStages() async {
    final stages = await _api.getPipelineStages();
    if (mounted) setState(() => _stages = stages);
  }

  void _refresh() {
    setState(() {
      _leadsFuture = _isTrashView ? _api.getTrashedLeads() : _api.getLeads(stage: _stageFilter);
    });
    _loadScores();
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

  void _toggleSelectAll() {
    setState(() {
      final visibleIds = _visibleLeads.map((l) => l.id).toSet();
      final allSelected = visibleIds.isNotEmpty && visibleIds.every(_selectedIds.contains);
      if (allSelected) {
        _selectedIds.removeAll(visibleIds);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.addAll(visibleIds);
        _selectionMode = true;
      }
    });
  }

  Future<void> _bulkMove() async {
    if (_selectedIds.isEmpty || _stages.isEmpty) return;
    final target = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Move ${_selectedIds.length} lead(s) to...', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            for (final s in _stages)
              ListTile(
                leading: Icon(Icons.circle, size: 14, color: stageColor(s['name'] as String)),
                title: Text(s['name'] as String),
                onTap: () => Navigator.pop(context, s['name'] as String),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (target == null) return;

    final ids = _selectedIds.toList();
    try {
      await Future.wait(ids.map((id) => _api.updateLeadStage(id, target)));
      setState(() {
        _selectionMode = false;
        _selectedIds.clear();
      });
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${ids.length} lead(s) moved to $target')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Move failed: $e')));
    }
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
          // Search + stage filter chips stay visible in selection mode too
          // (previously hidden the moment you long-pressed a lead) --
          // narrowing down by stage while selecting is exactly the
          // "filter" half of "select, then filter/move/delete in one go".
          if (!_selectionMode)
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
                  _visibleLeads = leads;
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
          icon: const Icon(Icons.tune),
          tooltip: 'Customize Leads List',
          onPressed: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomizeLeadsListScreen()));
            _loadListFields();
          },
        ),
        IconButton(
          icon: const Icon(Icons.view_column_outlined),
          tooltip: 'Pipeline Board',
          onPressed: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const PipelineBoardScreen()));
            _refresh();
          },
        ),
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
    final visibleIds = _visibleLeads.map((l) => l.id).toSet();
    final allSelected = visibleIds.isNotEmpty && visibleIds.every(_selectedIds.contains);
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Cancel selection',
        onPressed: () => setState(_exitSelectionMode),
      ),
      title: Text('${_selectedIds.length} selected'),
      actions: [
        IconButton(
          icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
          tooltip: allSelected ? 'Deselect all' : 'Select all',
          onPressed: _toggleSelectAll,
        ),
        if (!_isTrashView)
          IconButton(
            icon: const Icon(Icons.drive_file_move_outline),
            tooltip: 'Move to stage',
            onPressed: _stages.isEmpty ? null : _bulkMove,
          ),
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

  List<Map<String, dynamic>> get _sortedListFields {
    final list = List<Map<String, dynamic>>.from(_listFields)
      ..sort((a, b) => ((a['sort_order'] as num?) ?? 0).compareTo((b['sort_order'] as num?) ?? 0));
    return list;
  }

  String? _fieldValue(Lead lead, String key) {
    switch (key) {
      case 'field_phone':
        return lead.phone;
      case 'field_email':
        return lead.email;
      case 'field_source':
        return lead.source;
      case 'field_assigned_to':
        return lead.assignedTo;
      case 'field_created_date':
        return _formatDate(lead.createdAt);
      default:
        return null;
    }
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return iso;
    }
  }

  /// Joins every enabled "field_*" entry (in the user's chosen order) into
  /// one subtitle line. Falls back to the row's original source/phone
  /// chain when nothing is enabled or every enabled field is empty for
  /// this particular lead, so a lead missing its one customized field
  /// never shows a blank subtitle.
  String _subtitleFor(Lead lead) {
    final parts = <String>[];
    for (final f in _sortedListFields) {
      final key = f['field_key'] as String;
      if (f['enabled'] == false || isLeadListBadge(key)) continue;
      final value = _fieldValue(lead, key);
      if (value != null && value.isNotEmpty) parts.add(value);
    }
    if (parts.isEmpty) return lead.source ?? lead.phone ?? 'No source';
    return parts.join(' · ');
  }

  /// Every enabled "badge_*" entry (in order), each followed by a small
  /// gap -- badge_score is silently skipped for leads with no score yet
  /// (nothing to show) rather than leaving an empty slot.
  List<Widget> _trailingBadgesFor(Lead lead) {
    final widgets = <Widget>[];
    for (final f in _sortedListFields) {
      final key = f['field_key'] as String;
      if (f['enabled'] == false || !isLeadListBadge(key)) continue;
      if (key == 'badge_stage') {
        widgets.add(StageChip(
          stage: lead.stage,
          styleJson: (f['style_json'] as Map?)?.cast<String, dynamic>(),
        ));
        widgets.add(const SizedBox(height: 4));
      } else if (key == 'badge_score' && _scores[lead.id] != null) {
        widgets.add(ScoreBadgeCompact(
          score: _scores[lead.id]!['score'] as int,
          temperature: _scores[lead.id]!['temperature'] as String,
        ));
        widgets.add(const SizedBox(height: 4));
      }
    }
    if (widgets.isNotEmpty) widgets.removeLast();
    return widgets;
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
      subtitle: Text(_subtitleFor(lead)),
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
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: _trailingBadgesFor(lead),
            ),
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
