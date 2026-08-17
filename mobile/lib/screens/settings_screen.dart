import 'package:flutter/material.dart';
import 'brand_kit_screen.dart';
import 'emoji_generator_screen.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import 'customize_appearance_screen.dart';
import 'customize_dashboard_screen.dart';
import 'customize_lead_detail_screen.dart';
import 'customize_leads_list_screen.dart';
import 'customize_share_targets_screen.dart';
import 'flyer_studio/logo_library_screen.dart';
import '../widgets/launcher_tile.dart';

class _SettingsDestination {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Widget Function() screenBuilder;
  const _SettingsDestination(this.label, this.subtitle, this.icon, this.color, this.screenBuilder);
}

// Same distinct-hue-per-destination idea as kMoreMenuDefaultColors --
// this list used to render as identical-colour ListTiles-in-Cards, the
// exact same "flatter than the rest of the app" gap the More screen had
// before its premium grid pass.
final List<_SettingsDestination> _kSettingsDestinations = [
  _SettingsDestination('Customize App Look', 'Colors, fonts, corners, dark mode, glass effect', Icons.palette_outlined, Colors.deepPurple, () => const CustomizeAppearanceScreen()),
  _SettingsDestination('Customize Dashboard', 'Show, hide, reorder, and recolour your Dashboard widgets', Icons.space_dashboard_outlined, Colors.blue, () => const CustomizeDashboardScreen()),
  _SettingsDestination('Customize Leads List', 'Show, hide, and reorder the fields on every lead row', Icons.view_list_outlined, Colors.teal, () => const CustomizeLeadsListScreen()),
  _SettingsDestination('Customize Lead Detail', 'Show, hide, reorder, and restyle lead-screen buttons', Icons.tune_outlined, Colors.indigo, () => const CustomizeLeadDetailScreen()),
  _SettingsDestination('Share Targets', 'Show, hide, reorder, and restyle apps for sharing flyers and creative assets', Icons.share_outlined, Colors.green, () => const CustomizeShareTargetsScreen()),
  _SettingsDestination('Brand Kit', 'Colors, typography, and logos -- your brand identity in one place', Icons.diamond_outlined, Colors.pink, () => const BrandKitScreen()),
  _SettingsDestination('Emoji Generator', 'AI-suggested emoji for any message, save your favourites', Icons.emoji_emotions_outlined, Color(0xFFB8860B), () => const EmojiGeneratorScreen()),
  _SettingsDestination('Brand Logos', 'Upload and manage logos for flyers and branded documents', Icons.workspace_premium_outlined, Colors.deepOrange, () => const LogoLibraryScreen()),
];

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _api = ApiService();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _serverUrlCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _serverTestResult;

  @override
  void initState() {
    super.initState();
    _serverUrlCtrl.text = ApiService.baseUrl;
    _load();
  }

  Future<void> _load() async {
    final data = await _api.getSettings();
    _nameCtrl.text = data['name'] ?? '';
    _emailCtrl.text = data['contact_email'] ?? '';
    _phoneCtrl.text = data['contact_phone'] ?? '';
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await _api.updateSettings({
      'name': _nameCtrl.text.trim(),
      'contact_email': _emailCtrl.text.trim(),
      'contact_phone': _phoneCtrl.text.trim(),
    });
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
    }
  }

  Future<void> _saveServerUrl() async {
    setState(() => _serverTestResult = 'Testing...');
    await ApiService.setBaseUrl(_serverUrlCtrl.text.trim());
    try {
      // A real reachability check, not just saving the text — a typo'd
      // URL should fail loudly here, not silently break every screen
      // in the app afterward.
      await _api.getSettings();
      setState(() => _serverTestResult = '✅ Connected successfully');
    } catch (e) {
      setState(() => _serverTestResult = '❌ Could not reach this server: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Consultancy Branding', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Consultancy Name', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'Contact Email', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Contact Phone', border: OutlineInputBorder())),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving ? const CircularProgressIndicator(color: Colors.white) : const Text('Save'),
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 8),
          const Text('Server Connection', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          const Text(
            'Where this app fetches its data from. Change this to your deployed backend\'s real address once it\'s hosted somewhere — "localhost" only works while testing on the same computer.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(controller: _serverUrlCtrl, decoration: const InputDecoration(labelText: 'Server URL', border: OutlineInputBorder(), hintText: 'https://your-backend.example.com')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _saveServerUrl, child: const Text('Save & Test Connection')),
          if (_serverTestResult != null) ...[
            const SizedBox(height: 8),
            Text(_serverTestResult!, style: const TextStyle(fontSize: 13)),
          ],
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 12),
          const Text('Customize', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          const Text(
            'Every one of these opens its own show/hide/reorder/restyle screen for that part of the app.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 12),
          // Colourful destination grid -- previously a plain stack of
          // identical single-colour Cards/ListTiles, the same "flatter
          // than the rest of the app" gap the old More screen had.
          // Subtitle text moves into a tooltip-free long-press-free
          // simple label since a grid tile has no room for a subtitle
          // line; the intro text above covers what these do in general.
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.92,
            children: _kSettingsDestinations.map((d) {
              return LauncherTile(
                label: d.label,
                icon: d.icon,
                color: d.color,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => d.screenBuilder())),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
