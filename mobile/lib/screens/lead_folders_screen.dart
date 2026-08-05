// lib/screens/lead_folders_screen.dart
//
// Lead Folders — granular source-category browsing, built with the app's
// existing premium glass design system (GlassContainer/GlassButton/
// GlassBackdrop from glass_widgets.dart) rather than plain Material
// widgets, to match the rest of the app's visual language.

import 'package:flutter/material.dart';
import '../widgets/glass_widgets.dart';
import '../services/api_service.dart';
import 'lead_detail_screen.dart';

IconData _iconFor(String hint) {
  switch (hint) {
    case 'person':
      return Icons.person;
    case 'business':
      return Icons.business;
    case 'contacts':
      return Icons.contacts;
    case 'language':
      return Icons.language;
    case 'campaign':
      return Icons.campaign;
    case 'handshake':
      return Icons.handshake;
    case 'group':
      return Icons.group;
    case 'family_restroom':
      return Icons.family_restroom;
    case 'school':
      return Icons.school;
    case 'share':
      return Icons.share;
    case 'help_outline':
      return Icons.help_outline;
    default:
      return Icons.folder;
  }
}

class LeadFoldersScreen extends StatefulWidget {
  const LeadFoldersScreen({super.key});

  @override
  State<LeadFoldersScreen> createState() => _LeadFoldersScreenState();
}

class _LeadFoldersScreenState extends State<LeadFoldersScreen> {
  final ApiService _api = ApiService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _folders = [];

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
      final folders = await _api.getLeadFolders();
      setState(() {
        _folders = folders;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lead Folders')),
      body: GlassBackdrop(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text('Could not load: $_error'))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        childAspectRatio: 1.15,
                      ),
                      itemCount: _folders.length,
                      itemBuilder: (context, i) {
                        final folder = _folders[i];
                        final count = folder['count'] as int;
                        return GlassContainer(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => _FolderLeadsScreen(
                                categoryId: folder['id'],
                                categoryLabel: folder['label'],
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Icon(_iconFor(folder['icon']), size: 30),
                              const SizedBox(height: 8),
                              Text(
                                folder['label'],
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text('$count lead${count == 1 ? '' : 's'}', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
      ),
    );
  }
}

class _FolderLeadsScreen extends StatefulWidget {
  final String categoryId;
  final String categoryLabel;
  const _FolderLeadsScreen({required this.categoryId, required this.categoryLabel});

  @override
  State<_FolderLeadsScreen> createState() => _FolderLeadsScreenState();
}

class _FolderLeadsScreenState extends State<_FolderLeadsScreen> {
  final ApiService _api = ApiService();
  bool _loading = true;
  List<Map<String, dynamic>> _leads = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final leads = await _api.getLeadsInFolder(widget.categoryId);
    if (mounted) setState(() {
      _leads = leads;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.categoryLabel)),
      body: GlassBackdrop(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _leads.isEmpty
                ? const Center(child: Text('No leads in this folder yet'))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _leads.length,
                    itemBuilder: (context, i) {
                      final lead = _leads[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: GlassContainer(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => LeadDetailScreen(leadId: lead['id'])),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(lead['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                                    if (lead['phone'] != null) Text(lead['phone'], style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                                  ],
                                ),
                              ),
                              Chip(label: Text(lead['stage'] ?? '')),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
