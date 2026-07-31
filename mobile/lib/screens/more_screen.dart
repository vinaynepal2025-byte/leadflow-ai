import 'package:flutter/material.dart';
import 'settings_screen.dart';
import 'performance_screen.dart';
import 'audit_screen.dart';
import 'knowledge_screen.dart';
import 'automations_screen.dart';
import 'calendar_screen.dart';
import 'colleges_screen.dart';
import 'team_screen.dart';
import 'parent_crm_screen.dart';
import 'custom_fields_builder_screen.dart';
import 'pipeline_builder_screen.dart';
import 'social_links_screen.dart';
import 'capture_forms_screen.dart';
import 'scoring_config_screen.dart';
import 'triage_test_screen.dart';
import 'insights_overview_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.family_restroom_outlined),
            title: const Text('Parent CRM'),
            subtitle: const Text('Leads with guardian contacts'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ParentCrmScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.groups_outlined),
            title: const Text('Team'),
            subtitle: const Text('Counselors & consultants'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TeamScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.school_outlined),
            title: const Text('Colleges & Universities'),
            subtitle: const Text('Partner institutions'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CollegesScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_month_outlined),
            title: const Text('Calendar'),
            subtitle: const Text('Tasks & follow-ups by date'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CalendarScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.leaderboard_outlined),
            title: const Text('Performance'),
            subtitle: const Text('Counselor leaderboard'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PerformanceScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Audit Timeline'),
            subtitle: const Text('All activity, one feed'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuditScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('Knowledge Base'),
            subtitle: const Text('Visa/university guides'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const KnowledgeScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.bolt_outlined),
            title: const Text('Automation Hub'),
            subtitle: const Text('Auto-reminders on triggers'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AutomationsScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.analytics_outlined),
            title: const Text('Insights & Records'),
            subtitle: const Text('Alumni links, college performance, data requests'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InsightsOverviewScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.smart_toy_outlined),
            title: const Text('Smart Triage'),
            subtitle: const Text('Test AI auto-reply before enabling'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TriageTestScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('Lead Scoring Rules'),
            subtitle: const Text('Customize what makes a "hot" lead'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScoringConfigScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.qr_code_2_outlined),
            title: const Text('Lead Capture Forms'),
            subtitle: const Text('Public forms for website/QR/social'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CaptureFormsScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: const Text('Social Media Links'),
            subtitle: const Text('Trackable links, QR codes, attribution'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SocialLinksScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.view_kanban_outlined),
            title: const Text('Pipeline Builder'),
            subtitle: const Text('Customize your lead stages'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PipelineBuilderScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard_customize_outlined),
            title: const Text('Custom Fields'),
            subtitle: const Text('Define your own lead fields'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomFieldsBuilderScreen())),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            subtitle: const Text('Branding & contact info'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
    );
  }
}
