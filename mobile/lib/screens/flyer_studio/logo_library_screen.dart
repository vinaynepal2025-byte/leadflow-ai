// LogoLibraryScreen — replaces the old single-logo Settings upload flow.
//
// Why this replaces (not coexists with) the old `tenants.logo_url` system:
// that field pointed at a file on Render's local disk, which is ephemeral
// on the free tier — confirmed dead (404) as of 2026-08-10, same failure
// class as the pre-migration documents/voice-notes bug. The new
// `tenant_logos` table uses signed Supabase Storage URLs (same secure
// pattern as documents/voice-notes/flyer-elements) and supports multiple
// logos with one marked default — strictly more capable, so there's no
// reason to keep both systems running in parallel.

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../theme/appearance_settings.dart';
import '../../widgets/share_targets_sheet.dart';
import 'generate_logo_screen.dart';

class LogoLibraryScreen extends StatefulWidget {
  const LogoLibraryScreen({super.key});

  @override
  State<LogoLibraryScreen> createState() => _LogoLibraryScreenState();
}

class _LogoLibraryScreenState extends State<LogoLibraryScreen> {
  final ApiService _api = ApiService();
  final ImagePicker _picker = ImagePicker();

  List<Map<String, dynamic>> _logos = [];
  bool _loading = true;
  bool _uploading = false;
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
      final logos = await _api.getTenantLogos();
      setState(() => _logos = logos);
    } catch (e) {
      setState(() => _error = 'Could not load logos: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _uploadNewLogo() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return;

    final labelController = TextEditingController();
    final makeDefault = _logos.isEmpty; // first logo auto-becomes default
    bool setAsDefault = makeDefault;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Logo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelController,
                decoration: const InputDecoration(
                  labelText: 'Label (optional)',
                  hintText: 'e.g. "Main Logo", "White Version"',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              if (!makeDefault)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: setAsDefault,
                  title: const Text('Set as default'),
                  onChanged: (v) => setDialogState(() => setAsDefault = v ?? false),
                )
              else
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('This will be your default logo',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Upload')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    setState(() => _uploading = true);
    try {
      await _api.uploadTenantLogo(
        filePath: picked.path,
        label: labelController.text.trim().isEmpty ? null : labelController.text.trim(),
        isDefault: setAsDefault,
      );
      await _load();
      _showSnack('Logo added');
    } catch (e) {
      _showSnack('Upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _shareLogo(Map<String, dynamic> logo) async {
    final url = logo['image_url']?.toString();
    if (url == null) {
      _showSnack('This logo has no downloadable image yet');
      return;
    }
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) throw Exception('Download failed (${res.statusCode})');
      final dir = await getTemporaryDirectory();
      final label = (logo['label']?.toString() ?? 'logo').replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
      final tempPath = '${dir.path}/${label}_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(tempPath).writeAsBytes(res.bodyBytes);
      if (!mounted) return;
      await showShareTargetsSheet(context, files: [XFile(tempPath)]);
    } catch (e) {
      _showSnack('Share failed: $e');
    }
  }

  Future<void> _setDefault(String id) async {
    try {
      await _api.updateTenantLogo(id, isDefault: true);
      await _load();
    } catch (e) {
      _showSnack('Could not set default: $e');
    }
  }

  Future<void> _rename(String id, String currentLabel) async {
    final controller = TextEditingController(text: currentLabel);
    final newLabel = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Logo'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newLabel == null || newLabel.isEmpty) return;
    try {
      await _api.updateTenantLogo(id, label: newLabel);
      await _load();
    } catch (e) {
      _showSnack('Rename failed: $e');
    }
  }

  Future<void> _delete(String id, bool isDefault) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete logo?'),
        content: Text(isDefault
            ? 'This is your default logo. Deleting it means no logo will be pre-selected for new flyers until you set another default.'
            : 'This will remove the logo permanently.'),
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
      await _api.deleteTenantLogo(id);
      await _load();
    } catch (e) {
      _showSnack('Delete failed: $e');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Brand Logos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'Generate Logo',
            onPressed: () async {
              final saved = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GenerateLogoScreen()),
              );
              if (saved == true) _load();
            },
          ),
          IconButton(
            icon: _uploading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add_a_photo_outlined),
            onPressed: _uploading ? null : _uploadNewLogo,
            tooltip: 'Add Logo',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : _logos.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.85,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: _logos.length,
                        itemBuilder: (ctx, i) => _buildLogoCard(_logos[i]),
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
            Icon(Icons.workspace_premium_outlined, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text('No logos yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              'Add your consultancy\'s logo here to use it across flyers and future branded documents.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _uploading ? null : _uploadNewLogo,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Add Your First Logo'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoCard(Map<String, dynamic> logo) {
    final id = logo['id']?.toString() ?? '';
    final label = logo['label']?.toString() ?? 'Untitled';
    final imageUrl = logo['image_url']?.toString();
    final isDefault = logo['is_default'] == true;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Container(
                  width: double.infinity,
                  color: Colors.grey.shade100,
                  child: imageUrl == null
                      ? const Center(child: Icon(Icons.broken_image, color: Colors.grey))
                      : Image.network(
                          imageUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) =>
                              const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                        ),
                ),
                if (isDefault)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: context.watch<AppearanceSettings>().primaryColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('Default',
                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 18),
                    onSelected: (action) {
                      if (action == 'default') _setDefault(id);
                      if (action == 'rename') _rename(id, label);
                      if (action == 'delete') _delete(id, isDefault);
                    if (action == 'share') _shareLogo(logo);
                    },
                    itemBuilder: (ctx) => [
                      if (!isDefault)
                        const PopupMenuItem(value: 'default', child: Text('Set as Default')),
                      const PopupMenuItem(value: 'rename', child: Text('Rename')),
                      const PopupMenuItem(value: 'share', child: Text('Share')),
                      const PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}
