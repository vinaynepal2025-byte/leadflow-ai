import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_widgets.dart';
import '../l10n/app_strings.dart';
import '../widgets/stage_chip.dart';
import 'login_screen.dart';
import 'notifications_screen.dart';
import 'campaigns_screen.dart';
import 'work_queue_screen.dart';
import 'inbox_screen.dart';
import 'customize_dashboard_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ApiService _api = ApiService();
  late Future<Map<String, dynamic>> _future;
  int _unreadCount = 0;

  // The Dashboard's own show/hide/reorder/recolour config -- see
  // CustomizeDashboardScreen. Falls back to this fixed default order
  // (matching the backend's own DEFAULTS) if the config can't be loaded,
  // so a network hiccup never breaks the Dashboard itself, just the
  // ability to customize it that moment.
  static const List<String> _defaultSectionOrder = [
    'work_queue',
    'metric_total_leads',
    'metric_conversion',
    'metric_pending_followups',
    'metric_overdue',
    'pipeline_breakdown',
  ];
  List<Map<String, dynamic>> _sections = [];

  @override
  void initState() {
    super.initState();
    _future = _api.getAnalyticsSummary();
    _loadUnreadCount();
    _loadSections();
  }

  Future<void> _loadSections() async {
    try {
      final sections = await _api.getDashboardSections();
      if (mounted) setState(() => _sections = sections);
    } catch (_) {
      // Non-critical -- fall back to the default order/visibility below.
      if (mounted) {
        setState(() {
          _sections = [
            for (var i = 0; i < _defaultSectionOrder.length; i++)
              {'section_key': _defaultSectionOrder[i], 'enabled': true, 'sort_order': i},
          ];
        });
      }
    }
  }

  Future<void> _loadUnreadCount() async {
    try {
      final count = await _api.getUnreadCount();
      if (mounted) setState(() => _unreadCount = count);
    } catch (_) {
      // Non-critical — dashboard still works without the badge.
    }
  }

  void _refresh() {
    setState(() => _future = _api.getAnalyticsSummary());
    _loadUnreadCount();
    _loadSections();
  }

  Color _hexToColor(String hex) {
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.parse(h, radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Customize Dashboard',
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomizeDashboardScreen()));
              _loadSections();
            },
          ),
          IconButton(
            icon: const Icon(Icons.inbox_outlined),
            tooltip: 'Inbox',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InboxScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.campaign_outlined),
            tooltip: 'Campaigns',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CampaignsScreen())),
          ),
          IconButton(
            icon: Badge(
              label: Text('$_unreadCount'),
              isLabelVisible: _unreadCount > 0,
              child: const Icon(Icons.notifications_outlined),
            ),
            tooltip: 'Notifications',
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
              _loadUnreadCount();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () async {
              await AuthService().logout();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context, MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false,
                );
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 100),
                  Icon(Icons.cloud_off, size: 40, color: AppColors.slate.withValues(alpha: 0.5)),
                  const SizedBox(height: 12),
                  Center(
                    child: Text('Could not load dashboard',
                        style: TextStyle(color: AppColors.slate), textAlign: TextAlign.center),
                  ),
                ],
              );
            }
            final data = snapshot.data!;
            final byStage = (data['by_stage'] as List)
                .map((e) => MapEntry(e['stage'] as String, e['count'] as int))
                .toList();

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: _buildSectionWidgets(context, data, byStage),
            );
          },
        ),
      ),
    );
  }

  /// Renders every enabled Dashboard section in the user's chosen order.
  /// Metric cards are collected into consecutive runs and laid out two per
  /// row (their original grid), even when the run is broken up by a
  /// non-metric section elsewhere in the order -- a lone reordered metric
  /// still renders correctly as a single half-width card.
  List<Widget> _buildSectionWidgets(
      BuildContext context, Map<String, dynamic> data, List<MapEntry<String, int>> byStage) {
    final enabled = _sections.where((s) => s['enabled'] != false).toList()
      ..sort((a, b) => (a['sort_order'] as num).compareTo((b['sort_order'] as num)));

    final widgets = <Widget>[];
    var i = 0;
    while (i < enabled.length) {
      final key = enabled[i]['section_key'] as String;
      if (key == 'work_queue') {
        widgets.add(GlassButton(
          icon: Icons.bolt,
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WorkQueueScreen())),
          child: Text(context.tr('work_queue_title')),
        ));
        widgets.add(const SizedBox(height: 20));
        i++;
      } else if (key == 'pipeline_breakdown') {
        widgets.add(Text(context.tr('pipeline_breakdown'), style: Theme.of(context).textTheme.titleMedium));
        widgets.add(const SizedBox(height: 12));
        widgets.add(GlassContainer(
          child: Column(
            children: byStage.map((e) {
              final color = stageColor(e.key);
              final total = (data['total_leads'] as int);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    SizedBox(width: 100, child: StageChip(stage: e.key)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: total > 0 ? e.value / total : 0,
                          minHeight: 8,
                          backgroundColor: color.withValues(alpha: 0.08),
                          color: color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 24,
                      child:
                          Text('${e.value}', textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ));
        widgets.add(const SizedBox(height: 16));
        i++;
      } else if (key.startsWith('metric_')) {
        final run = <Map<String, dynamic>>[];
        while (i < enabled.length && (enabled[i]['section_key'] as String).startsWith('metric_')) {
          run.add(enabled[i]);
          i++;
        }
        if (run.isNotEmpty) {
          widgets.add(Text(context.tr('today_glance'), style: Theme.of(context).textTheme.titleMedium));
          widgets.add(const SizedBox(height: 14));
        }
        for (var r = 0; r < run.length; r += 2) {
          final left = run[r];
          final right = r + 1 < run.length ? run[r + 1] : null;
          widgets.add(Row(
            children: [
              Expanded(child: _metricCardFor(context, left, data)),
              if (right != null) ...[
                const SizedBox(width: 12),
                Expanded(child: _metricCardFor(context, right, data)),
              ],
            ],
          ));
          widgets.add(const SizedBox(height: 12));
        }
        widgets.add(const SizedBox(height: 16));
      } else {
        // Unknown section key (e.g. a future addition on an older app
        // build) -- skip it rather than crash.
        i++;
      }
    }
    return widgets;
  }

  Widget _metricCardFor(BuildContext context, Map<String, dynamic> section, Map<String, dynamic> data) {
    final key = section['section_key'] as String;
    final colorHex = section['color_override'] as String?;
    String label;
    String value;
    IconData icon;
    Color defaultColor;
    switch (key) {
      case 'metric_total_leads':
        label = context.tr('total_leads');
        value = '${data['total_leads']}';
        icon = Icons.people_outline;
        defaultColor = Theme.of(context).colorScheme.primary;
        break;
      case 'metric_conversion':
        label = context.tr('conversion');
        value = '${data['conversion_rate_percent']}%';
        icon = Icons.trending_up;
        defaultColor = AppColors.successGreen;
        break;
      case 'metric_pending_followups':
        label = context.tr('pending_followups');
        value = '${data['pending_reminders']}';
        icon = Icons.alarm_outlined;
        defaultColor = Theme.of(context).colorScheme.secondary;
        break;
      case 'metric_overdue':
      default:
        label = context.tr('overdue');
        value = '${data['overdue_reminders']}';
        icon = Icons.priority_high;
        defaultColor = AppColors.coralAlert;
        break;
    }
    final color = colorHex != null ? _hexToColor(colorHex) : defaultColor;
    return _metricCard(label, value, icon, color);
  }

  Widget _metricCard(String label, String value, IconData icon, Color color) {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 24)),
          Text(label, style: TextStyle(fontSize: 12, color: AppColors.slate)),
        ],
      ),
    );
  }
}
