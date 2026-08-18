import 'package:flutter/material.dart';
import 'customize_registry.dart';
import 'ai_restyle_screen.dart';

/// Search any customizable button/section in the app by name and jump
/// straight to its editor -- the direct answer to "settings studio me
/// he jaha main koi bhi button search karke apne according customize
/// kar saku". Registry (49 items across 5 categories) comes from
/// customize_registry.dart, shared with AI Quick Restyle so both
/// features draw from one source of truth.
class SettingsStudioScreen extends StatefulWidget {
  const SettingsStudioScreen({super.key});

  @override
  State<SettingsStudioScreen> createState() => _SettingsStudioScreenState();
}

class _SettingsStudioScreenState extends State<SettingsStudioScreen> {
  late final List<CustomizeRegistryItem> _registry = buildCustomizeRegistry();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final results = q.isEmpty
        ? _registry
        : _registry.where((i) => i.label.toLowerCase().contains(q) || i.category.toLowerCase().contains(q)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings Studio')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search any button or section to customize...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${results.length} customizable item${results.length == 1 ? '' : 's'}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('AI Quick Restyle'),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiRestyleScreen())),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: results.isEmpty
                ? const Center(child: Text('No matches', style: TextStyle(color: Colors.grey)))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final item = results[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: item.categoryColor.withValues(alpha: 0.12),
                          child: Icon(item.icon, color: item.categoryColor, size: 20),
                        ),
                        title: Text(item.label),
                        subtitle: Text(item.category, style: TextStyle(fontSize: 11, color: item.categoryColor)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => item.screenBuilder())),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
