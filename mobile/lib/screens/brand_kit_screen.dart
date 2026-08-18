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

// One entry per Brand Kit logo role (master spec §16). [urlKey]/[idKey]
// match the columns brand_kit.js's attachLogoUrls() produces
// (`<idKey>` and `<idKey>_url`).
class _BrandRole {
  final String idKey;
  final String label;
  final String hint;
  const _BrandRole(this.idKey, this.label, this.hint);
}

const List<_BrandRole> kBrandRoles = [
  _BrandRole('primary_logo_id', 'Primary Logo', 'Main mark, used everywhere by default'),
  _BrandRole('secondary_logo_id', 'Secondary Logo', 'An alternate lockup (e.g. horizontal)'),
  _BrandRole('mono_logo_id', 'Monochrome', 'Single-colour version'),
  _BrandRole('dark_bg_logo_id', 'For Dark Backgrounds', 'Light-coloured elements'),
  _BrandRole('light_bg_logo_id', 'For Light Backgrounds', 'Dark-coloured elements'),
  _BrandRole('icon_mark_logo_id', 'Icon Mark', 'Icon-only, for avatars/favicons'),
];

class _BrandKitScreenState extends State<BrandKitScreen> {
  final _api = ApiService();
  List<Map<String, dynamic>> _logos = [];
  Map<String, dynamic>? _kit;
  bool _loadingLogos = true;

  @override
  void initState() {
    super.initState();
    _loadLogos();
    _loadKit();
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

  Future<void> _loadKit() async {
    try {
      final kit = await _api.getBrandKit();
      if (mounted) setState(() => _kit = kit);
    } catch (_) {
      // Non-fatal -- the rest of the screen (live colours/typography/
      // logo list) still works without a saved Brand Kit yet.
    }
  }

  Future<void> _assignRole(_BrandRole role) async {
    if (_logos.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Save a logo first, then assign it here')));
      return;
    }
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Set as ${role.label}', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            ..._logos.map((logo) {
              final url = logo['image_url']?.toString();
              return ListTile(
                leading: url == null
                    ? const Icon(Icons.workspace_premium)
                    : Image.network(url, width: 36, height: 36, fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(Icons.workspace_premium)),
                title: Text(logo['label']?.toString() ?? 'Logo'),
                onTap: () => Navigator.pop(ctx, logo['id']?.toString()),
              );
            }),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    try {
      final saved = await _api.saveBrandKit(
        primaryLogoId: role.idKey == 'primary_logo_id' ? chosen : null,
        secondaryLogoId: role.idKey == 'secondary_logo_id' ? chosen : null,
        monoLogoId: role.idKey == 'mono_logo_id' ? chosen : null,
        darkBgLogoId: role.idKey == 'dark_bg_logo_id' ? chosen : null,
        lightBgLogoId: role.idKey == 'light_bg_logo_id' ? chosen : null,
        iconMarkLogoId: role.idKey == 'icon_mark_logo_id' ? chosen : null,
      );
      if (mounted) setState(() => _kit = saved);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    }
  }

  Future<void> _addPaletteColor() async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => const ColorPickerDialog(initial: Colors.blue, title: 'Add a brand colour'),
    );
    if (picked == null) return;
    final hex = '#${(picked.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    final current = ((_kit?['palette'] as List?) ?? []).map((e) => e.toString()).toList();
    if (current.contains(hex)) return;
    final updated = [...current, hex];
    try {
      final saved = await _api.saveBrandKit(palette: updated);
      if (mounted) setState(() => _kit = saved);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    }
  }

  Future<void> _removePaletteColor(String hex) async {
    final current = ((_kit?['palette'] as List?) ?? []).map((e) => e.toString()).toList();
    final updated = current.where((c) => c != hex).toList();
    try {
      final saved = await _api.saveBrandKit(palette: updated);
      if (mounted) setState(() => _kit = saved);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
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
            _sectionHeader('Brand Palette'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ...((_kit?['palette'] as List?) ?? []).map((c) {
                      final hex = c.toString();
                      final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
                      final color = value == null ? Colors.grey : Color(0xFF000000 | value);
                      return InkWell(
                        onTap: () => _removePaletteColor(hex),
                        borderRadius: BorderRadius.circular(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                  color: color, shape: BoxShape.circle,
                                  border: Border.all(color: Colors.grey.shade300)),
                            ),
                            const SizedBox(height: 2),
                            Text(hex, style: const TextStyle(fontSize: 9, color: Colors.grey)),
                          ],
                        ),
                      );
                    }),
                    InkWell(
                      onTap: _addPaletteColor,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.grey.shade400, style: BorderStyle.solid)),
                        child: const Icon(Icons.add, size: 18, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _sectionHeader('Brand Kit Logo Roles'),
            Card(
              child: Column(
                children: kBrandRoles.map((role) {
                  final url = _kit?['${role.idKey}_url']?.toString();
                  final isLast = role == kBrandRoles.last;
                  return Column(
                    children: [
                      ListTile(
                        leading: Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8)),
                          child: url == null
                              ? Icon(Icons.add_photo_alternate_outlined, color: Colors.grey.shade400, size: 18)
                              : Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Image.network(url, fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 16)),
                                ),
                        ),
                        title: Text(role.label),
                        subtitle: Text(url == null ? role.hint : 'Tap to change',
                            style: const TextStyle(fontSize: 11)),
                        onTap: () => _assignRole(role),
                      ),
                      if (!isLast) const Divider(height: 1),
                    ],
                  );
                }).toList(),
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
