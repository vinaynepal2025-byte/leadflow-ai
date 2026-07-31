import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// Reachable from the Login screen without being logged in — a brand new
/// install still points at "localhost" by default, which only works on
/// the same machine as the backend. This is the one screen that has to
/// work before anything else does.
class ServerSetupScreen extends StatefulWidget {
  const ServerSetupScreen({super.key});

  @override
  State<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends State<ServerSetupScreen> {
  final _urlCtrl = TextEditingController();
  final _api = ApiService();
  String? _result;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _urlCtrl.text = ApiService.baseUrl;
  }

  Future<void> _saveAndTest() async {
    setState(() {
      _testing = true;
      _result = null;
    });
    await ApiService.setBaseUrl(_urlCtrl.text.trim());
    try {
      await _api.getSettings();
      setState(() => _result = '✅ Connected! You can go back and log in now.');
    } catch (e) {
      setState(() => _result = '❌ Could not reach this server: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Server Setup')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'This app needs to know where your LeadFlow AI backend is running. '
              '"localhost" only works if the backend is on this same device — '
              'for a real phone, enter your deployed backend\'s address.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _urlCtrl,
              decoration: const InputDecoration(labelText: 'Server URL', border: OutlineInputBorder(), hintText: 'https://your-backend.example.com'),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _testing ? null : _saveAndTest,
              child: _testing
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save & Test Connection'),
            ),
            if (_result != null) ...[
              const SizedBox(height: 16),
              Text(_result!, style: const TextStyle(fontSize: 14)),
            ],
          ],
        ),
      ),
    );
  }
}
