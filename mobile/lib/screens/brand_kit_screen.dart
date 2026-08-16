import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/appearance_settings.dart';
import '../services/api_service.dart';
import '../widgets/color_picker_dialog.dart';
import 'flyer_studio/logo_library_screen.dart';
import 'flyer_studio/generate_logo_screen.dart';

/// A single, centralized view of everything that makes up this tenant's
/// brand identity -- colours, typography, and logos, all in one place.
/// Colours and typography already live in AppearanceSettings (the
/// Customize App Look screen edits them); logos already live in
/// tenant_logos (Brand Logos screen manages them). This screen doesn't
/// duplicate either system -- it's a consolidated overview that reads
/// from both and deep-links to the existing management screens, per
/// the Logo/Brand Identity Engine spec's "ONE centralized Brand Kit,
/// not a separate system per module" requirement.
class BrandKitScreen extends StatefulWidget {
  const BrandKitScreen({super.key});

  @override
  State<BrandKitScreen> createState() => _BrandKitScreenState();
}

class _BrandKitScreenState extends State<BrandKitScreen> {
  final _api = ApiService();
  List<Map<String, dynamic>> _logos = [];
  bool _loadingLogos = true;

  @override
  void initState() {
    super.initState();
    _loadLogos();
  }

  Future<void> _loadLogos() async {
    try {
      final logos = await _api.getTenantLogos();
      if (mounted) setState(() {
        _logos = logos;
        _loadingLogos = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingLogos = false);
    }
  }

  Future<void> _pickColor(AppearanceSettings appearance, {
    required String label,
    required Color current,
    required Future<void> Function(Color) onPicked,
  }) async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => ColorPickerDialog(initial: current, title: label),
    );
    if (picked != null) await onPicked(picked);
  }

  Widget _sectionHeader(String title, {Widget? action}) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          if (action != null) action,
        ],
      ),
    );
  }

  Widget _colorSwatch(String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade300)),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(label)),
            Text('#${(color.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
                style: const TextStyle(color: Colors.grey, fontFamily: 'monospace', fontSize: 12)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<AppearanceSettings>();

    return Scaffold(
      appBar: AppBar(title: const Text('Brand Kit')),
      body: RefreshIndicator(
        onRefresh: _loadLogos,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'Your consultancy\'s brand identity, all in one place -- colours, typography, and logos used across the app, flyers, and future branded documents.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
            _sectionHeader('Brand Colors'),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: [
                    _colorSwatch('Primary', appearance.primaryColor,
                        () => _pickColor(appearance, label: 'Primary color', current: appearance.primaryColor, onPicked: appearance.setPrimaryColor)),
                    const Divider(height: 1),
                    _colorSwatch('Accent', appearance.accentColor,
                        () => _pickColor(appearance, label: 'Accent color', current: appearance.accentColor, onPicked: appearance.setAccentColor)),
                    const Divider(height: 1),
                    _colorSwatch('Success', appearance.successColor,
                        () => _pickColor(appearance, label: 'Success color', current: appearance.successColor, onPicked: appearance.setSuccessColor)),
                    const Divider(height: 1),
                    _colorSwatch('Warning', appearance.warningColor,
                        () => _pickColor(appearance, label: 'Warning color', current: appearance.warningColor, onPicked: appearance.setWarningColor)),
                    const Divider(height: 1),
                    _colorSwatch('Danger', appearance.dangerColor,
                        () => _pickColor(appearance, label: 'Danger color', current: appearance.dangerColor, onPicked: appearance.setDangerColor)),
                    const Divider(height: 1),
                    _colorSwatch('Muted', appearance.mutedColor,
                        () => _pickColor(appearance, label: 'Muted color', current: appearance.mutedColor, onPicked: appearance.setMutedColor)),
                  ],
                ),
              ),
            ),
            _sectionHeader('Typography'),
            Card(
              child: ListTile(
                leading: const Icon(Icons.text_fields),
                title: Text(appearance.fontPairing.label),
                subtitle: const Text('Change in Customize App Look'),
              ),
            ),
            _sectionHeader(
              'Logos',
              action: TextButton.icon(
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: const Text('Generate'),
                onPressed: () async {
                  final saved = await Navigator.push(context, MaterialPageRoute(builder: (_) => const GenerateLogoScreen()));
                  if (saved == true) _loadLogos();
                },
              ),
            ),
            _loadingLogos
                ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
                : _logos.isEmpty
                    ? Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              const Text('No logos yet', style: TextStyle(color: Colors.grey)),
                              const SizedBox(height: 12),
                              OutlinedButton(
                                onPressed: () async {
                                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const LogoLibraryScreen()));
                                  _loadLogos();
                                },
                                child: const Text('Manage Logos'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            SizedBox(
                              height: 90,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.all(10),
                                itemCount: _logos.length,
                                itemBuilder: (ctx, i) {
                                  final logo = _logos[i];
                                  final url = logo['image_url']?.toString();
                                  final isDefault = logo['is_default'] == true;
                                  return Container(
                                    width: 70,
                                    margin: const EdgeInsets.only(right: 10),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: isDefault ? Theme.of(context).colorScheme.primary : Colors.grey.shade300, width: isDefault ? 2 : 1),
                                      borderRadius: BorderRadius.circular(10),
                                      color: Colors.grey.shade50,
                                    ),
                                    child: url == null
                                        ? const Icon(Icons.broken_image, color: Colors.grey)
                                        : Padding(
                                            padding: const EdgeInsets.all(6),
                                            child: Image.network(url, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey)),
                                          ),
                                  );
                                },
                              ),
                            ),
                            const Divider(height: 1),
                            TextButton(
                              onPressed: () async {
                                await Navigator.push(context, MaterialPageRoute(builder: (_) => const LogoLibraryScreen()));
                                _loadLogos();
                              },
                              child: const Text('Manage All Logos'),
                            ),
                          ],
                        ),
                      ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
