import 'package:flutter/material.dart';
import 'brand_kit_screen.dart';
import 'emoji_generator_screen.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import 'customize_appearance_screen.dart';
import 'customize_dashboard_screen.dart';
import 'customize_lead_detail_screen.dart';
import 'customize_share_targets_screen.dart';
import 'flyer_studio/logo_library_screen.dart';

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
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Customize App Look'),
              subtitle: const Text('Colors, fonts, corners, dark mode, glass effect'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomizeAppearanceScreen())),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.space_dashboard_outlined),
              title: const Text('Customize Dashboard'),
              subtitle: const Text('Show, hide, reorder, and recolour your Dashboard widgets'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomizeDashboardScreen())),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.tune_outlined),
              title: const Text('Customize Lead Detail'),
              subtitle: const Text('Show, hide, reorder, and restyle lead-screen buttons'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomizeLeadDetailScreen())),
            ),
          ),
          const SizedBox(height: 8),
          Card(
              child: ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Share Targets'),
                subtitle: const Text('Show, hide, reorder, and restyle apps for sharing flyers and creative assets'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomizeShareTargetsScreen())),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.diamond_outlined),
                title: const Text('Brand Kit'),
                subtitle: const Text('Colors, typography, and logos -- your brand identity in one place'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BrandKitScreen())),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.emoji_emotions_outlined),
                title: const Text('Emoji Generator'),
                subtitle: const Text('AI-suggested emoji for any message, save your favourites'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EmojiGeneratorScreen())),
              ),
            ),
            const SizedBox(height: 8),
            Card(
            child: ListTile(
              leading: const Icon(Icons.workspace_premium_outlined),
              title: const Text('Brand Logos'),
              subtitle: const Text('Upload and manage logos for flyers and branded documents'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LogoLibraryScreen())),
            ),
          ),
        ],
      ),
    );
  }
}
