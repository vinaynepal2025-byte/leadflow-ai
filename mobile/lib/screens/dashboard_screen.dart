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

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ApiService _api = ApiService();
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.getAnalyticsSummary();
  }

  void _refresh() => setState(() => _future = _api.getAnalyticsSummary());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
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
            icon: const Icon(Icons.notifications_outlined),
            tooltip: 'Notifications',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
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
              children: [
                GlassButton(
                  icon: Icons.bolt,
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WorkQueueScreen())),
                  child: Text(context.tr('work_queue_title')),
                ),
                const SizedBox(height: 20),
                Text(context.tr('today_glance'), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: _metricCard(context.tr('total_leads'), '${data['total_leads']}', Icons.people_outline, Theme.of(context).colorScheme.primary)),
                    const SizedBox(width: 12),
                    Expanded(child: _metricCard(context.tr('conversion'), '${data['conversion_rate_percent']}%', Icons.trending_up, AppColors.successGreen)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _metricCard(context.tr('pending_followups'), '${data['pending_reminders']}', Icons.alarm_outlined, Theme.of(context).colorScheme.secondary)),
                    const SizedBox(width: 12),
                    Expanded(child: _metricCard(context.tr('overdue'), '${data['overdue_reminders']}', Icons.priority_high, AppColors.coralAlert)),
                  ],
                ),
                const SizedBox(height: 28),
                Text(context.tr('pipeline_breakdown'), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                GlassContainer(
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
                                child: Text('${e.value}', textAlign: TextAlign.end,
                                    style: TextStyle(fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
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
