import 'package:flutter/material.dart';
import 'glass_widgets.dart';

/// A self-contained mini preview of what a real screen would look like
/// with the current live settings. Reuses GlassContainer/GlassButton —
/// the exact same widgets hero screens use — so Neon Glow, Edge Blur,
/// Liquid sheen, and every style mode render here with full fidelity,
/// not just a theme-level approximation.
class LivePreviewPanel extends StatelessWidget {
  const LivePreviewPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.visibility_outlined, size: 16, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 6),
              Text('Live Preview', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          GlassContainer(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                  child: Icon(Icons.person, color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Sample Lead Card', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 14)),
                      const Text('This is how a card looks', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                Chip(label: const Text('New', style: TextStyle(fontSize: 11))),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: GlassButton(onPressed: () {}, child: const Text('Primary'))),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton(onPressed: () {}, child: const Text('Secondary'))),
            ],
          ),
          const SizedBox(height: 12),
          const TextField(
            decoration: InputDecoration(labelText: 'Sample input', isDense: true),
          ),
        ],
      ),
    );
  }
}
