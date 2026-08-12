// FlyerHistoryScreen — the entry point into Flyer Studio.
//
// This exists because the editor alone isn't a feature: a counselor makes
// the same flyer shape repeatedly (new batch, new college, new offer), so
// the highest-value action is usually "open the one I made last week and
// change two words" — not "start from scratch". Duplicate is therefore a
// first-class action here, not buried in a menu.
//
// New-flyer flow deliberately opens a starter-layout picker rather than
// dropping the user straight onto an empty white canvas — a blank canvas
// on a 6-inch screen is intimidating and gives no sense of what the tool
// can do. Every starter is fully editable once opened (see
// flyer_starter_layouts.dart).

import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import 'flyer_starter_layouts.dart';
import 'flyer_studio_screen.dart';

class FlyerHistoryScreen extends StatefulWidget {
  final String? leadId;

  const FlyerHistoryScreen({super.key, this.leadId});

  @override
  State<FlyerHistoryScreen> createState() => _FlyerHistoryScreenState();
}

class _FlyerHistoryScreenState extends State<FlyerHistoryScreen> {
  final ApiService _api = ApiService();

  List<Map<String, dynamic>> _projects = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final projects = await _api.getFlyerProjects(leadId: widget.leadId);
      setState(() => _projects = projects);
    } catch (e) {
      setState(() => _error = 'Could not load flyers: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _newFlyer() async {
    final layout = await showModalBottomSheet<FlyerStarterLayout>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Start with',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: kFlyerStarterLayouts.map((l) {
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _hexToColor(l.backgroundColor),
                      child: Icon(
                        l.id == 'blank' ? Icons.add : Icons.dashboard_customize_outlined,
                        size: 18,
                        color: l.backgroundColor.toUpperCase() == '#FFFFFF'
                            ? Colors.black54
                            : Colors.white,
                      ),
                    ),
                    title: Text(l.name),
                    subtitle: Text(l.description),
                    onTap: () => Navigator.pop(ctx, l),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (layout == null || !mounted) return;

    try {
      final created = await _api.createFlyerProject(
        title: layout.id == 'blank' ? 'Untitled Flyer' : layout.name,
        leadId: widget.leadId,
        canvasJson: layout.build(),
        backgroundColor: layout.backgroundColor,
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FlyerStudioScreen(projectId: created['id']?.toString()),
        ),
      );
      _load();
    } catch (e) {
      _showSnack('Could not create flyer: $e');
    }
  }

  Future<void> _duplicate(Map<String, dynamic> project) async {
    try {
      final rawElements = (project['canvas_json'] as List?) ?? [];
      final created = await _api.createFlyerProject(
        title: '${project['title'] ?? 'Flyer'} (copy)',
        leadId: widget.leadId,
        canvasJson: rawElements
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
        backgroundColor: project['background_color']?.toString(),
      );
      _showSnack('Duplicated');
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FlyerStudioScreen(projectId: created['id']?.toString()),
        ),
      );
      _load();
    } catch (e) {
      _showSnack('Duplicate failed: $e');
    }
  }

  Future<void> _delete(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete flyer?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _api.deleteFlyerProject(id);
      await _load();
    } catch (e) {
      _showSnack('Delete failed: $e');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Color _hexToColor(String hex) {
    var h = hex.replaceAll('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    final value = int.tryParse(h, radix: 16);
    return value == null ? Colors.grey : Color(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.leadId != null ? 'Flyers for this Lead' : 'Flyer Studio'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newFlyer,
        icon: const Icon(Icons.add),
        label: const Text('New Flyer'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : _projects.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.72,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: _projects.length,
                        itemBuilder: (ctx, i) => _buildProjectCard(_projects[i]),
                      ),
                    ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_mosaic_outlined, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text('No flyers yet',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              'Create a flyer from a starter layout, or describe what you want and let AI lay it out for you.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectCard(Map<String, dynamic> project) {
    final id = project['id']?.toString() ?? '';
    final title = project['title']?.toString() ?? 'Untitled';
    final renderUrl = project['rendered_image_url']?.toString();
    final bg = project['background_color']?.toString() ?? '#FFFFFF';
    final elementCount = ((project['canvas_json'] as List?) ?? []).length;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => FlyerStudioScreen(projectId: id)),
          );
          _load();
        },
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    color: _hexToColor(bg),
                    child: renderUrl == null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.edit_note,
                                    color: Colors.grey.shade500, size: 28),
                                const SizedBox(height: 4),
                                Text('$elementCount elements',
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.grey.shade600)),
                              ],
                            ),
                          )
                        : Image.network(
                            renderUrl,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Center(
                                child: Icon(Icons.broken_image, color: Colors.grey)),
                          ),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 18),
                      onSelected: (action) {
                        if (action == 'duplicate') _duplicate(project);
                        if (action == 'delete') _delete(id);
                      },
                      itemBuilder: (ctx) => const [
                        PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(title,
                  maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }
}
