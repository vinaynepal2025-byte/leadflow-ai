import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/lead.dart';
import '../models/communication.dart';
import '../services/api_service.dart';
import '../theme/edit_mode_settings.dart';
import '../widgets/stage_chip.dart';
import '../widgets/score_badge.dart';
import '../widgets/lead360_panel.dart';
import '../widgets/launcher_tile.dart';
import '../widgets/quick_style_editor_sheet.dart';
import 'customize_registry.dart';
import 'documents_screen.dart';
import 'admissions_fees_screen.dart';
import 'email_compose_screen.dart';
import 'calls_voice_notes_screen.dart';
import 'meetings_screen.dart';
import 'journey_screen.dart';
import 'alumni_match_screen.dart';
import 'compliance_screen.dart';
import 'cockpit_screen.dart';
import 'lead_notes_screen.dart';
import 'customize_lead_detail_screen.dart';
import 'flyer_studio/flyer_history_screen.dart';
import 'lead_timeline_screen.dart';
import 'automation_center_screen.dart';
import '../widgets/glass_widgets.dart';

// Must stay in sync with backend/routes/leadDetailSections.js DEFAULTS
// and screens/customize_lead_detail_screen.dart -- three places carry
// this same small map because the backend only stores an override,
// never the default label/icon text itself.
const Map<String, IconData> _kIconOptions = {
  'auto_awesome': Icons.auto_awesome,
  'bolt': Icons.bolt,
  'chat': Icons.chat,
  'folder_outlined': Icons.folder_outlined,
  'workspace_premium': Icons.workspace_premium,
  'school_outlined': Icons.school_outlined,
  'phone_in_talk_outlined': Icons.phone_in_talk_outlined,
  'event_available_outlined': Icons.event_available_outlined,
  'flight_takeoff_outlined': Icons.flight_takeoff_outlined,
  'diversity_3_outlined': Icons.diversity_3_outlined,
  'privacy_tip_outlined': Icons.privacy_tip_outlined,
  'star': Icons.star,
  'favorite': Icons.favorite,
  'call': Icons.call,
  'email_outlined': Icons.email_outlined,
  'work_outline': Icons.work_outline,
  'description_outlined': Icons.description_outlined,
  'payments_outlined': Icons.payments_outlined,
  'group_outlined': Icons.group_outlined,
  'shield_outlined': Icons.shield_outlined,
  'map_outlined': Icons.map_outlined,
};

const Map<String, String> _kDefaultLabels = {
  'ai_insight': 'AI Insight',
  'calling_cockpit': 'Open Calling Cockpit',
  'whatsapp': 'Send WhatsApp (free)',
  'documents': 'Documents',
  'admissions_fees': 'Admissions & Fees',
  'calls_voice_notes': 'Calls & Voice Notes',
  'meetings': 'Meetings & Campus Tours',
  'visa_travel_student': 'Visa, Travel & Student',
  'alumni': 'Alumni Network',
  'consent_compliance': 'Consent & Compliance',
  'lead_notes': 'Notes',
  'flyer_studio': 'Make a Flyer',
  'activity_timeline': 'Activity Timeline',
  'share_logo': 'Share Logo',
};

const Map<String, String> _kDefaultIcons = {
  'ai_insight': 'auto_awesome',
  'calling_cockpit': 'bolt',
  'whatsapp': 'chat',
  'documents': 'folder_outlined',
  'admissions_fees': 'school_outlined',
  'calls_voice_notes': 'phone_in_talk_outlined',
  'meetings': 'event_available_outlined',
  'visa_travel_student': 'flight_takeoff_outlined',
  'alumni': 'diversity_3_outlined',
  'consent_compliance': 'privacy_tip_outlined',
  'lead_notes': 'description_outlined',
  'flyer_studio': 'auto_awesome_mosaic_outlined',
  'activity_timeline': 'history',
  'share_logo': 'workspace_premium',
};

class LeadDetailScreen extends StatefulWidget {
  final String leadId;
  const LeadDetailScreen({super.key, required this.leadId});

  @override
  State<LeadDetailScreen> createState() => _LeadDetailScreenState();
}

class _LeadDetailScreenState extends State<LeadDetailScreen> {
  final ApiService _api = ApiService();
  Lead? _lead;
  List<Communication> _comms = [];
  List<Map<String, dynamic>> _customFieldDefs = [];
  List<Map<String, dynamic>> _stages = [];
  List<Map<String, dynamic>> _sections = [];
  bool _loading = true;
  AiInsight? _insight;
  bool _analyzing = false;
  String? _aiError;
  Map<String, dynamic>? _score;

  // Lead 360 — unified cross-module intelligence (Phase 1 of the Meta-OS
  // interconnection layer). Fetched separately from the rest of the
  // screen (it involves an AI call across many tables, so it shouldn't
  // block the basic lead view from rendering).
  Map<String, dynamic>? _lead360;
  bool _lead360Loading = false;
  String? _lead360Error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final lead = await _api.getLead(widget.leadId);
    final comms = await _api.getCommunications(widget.leadId);
    final defs = await _api.getCustomFieldDefinitions();
    final stages = await _api.getPipelineStages();
    try {
      _score = await _api.getLeadScore(widget.leadId);
    } catch (_) {
      _score = null; // non-critical — screen still works without it
    }
    unawaited(_loadLead360());

    List<Map<String, dynamic>> sections;
    try {
      sections = await _api.getLeadDetailSections();
    } catch (_) {
      // If the config endpoint is unreachable, fall back to every
      // built-in section enabled in its default order rather than
      // showing a broken/empty screen.
      final keys = _kDefaultLabels.keys.toList();
      sections = List.generate(keys.length, (i) => {
            'section_key': keys[i],
            'enabled': true,
            'sort_order': i,
            'custom_label': null,
            'icon_override': null,
            'color_override': null,
            'size_override': null,
            'shape_override': null,
          });
    }

    if (!mounted) return;
    setState(() {
      _lead = lead;
      _comms = comms;
      _customFieldDefs = defs;
      _stages = stages;
      _sections = sections;
      _loading = false;
    });
  }

  Future<void> _changeStage(String newStage) async {
    await _api.updateLeadStage(widget.leadId, newStage);
    _load();
  }

  Future<void> _loadLead360() async {
    setState(() {
      _lead360Loading = true;
      _lead360Error = null;
    });
    try {
      final report = await _api.getLead360(widget.leadId);
      if (!mounted) return;
      setState(() {
        _lead360 = report;
        _lead360Loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lead360Error = e.toString();
        _lead360Loading = false;
      });
    }
  }

  // Alerts from Lead 360 carry a module key that matches the customizable
  // section keys already used elsewhere on this screen — one map, reused,
  // instead of a second routing table to keep in sync.
  void _navigateToModule(String module) {
    if (_lead == null) return;
    final lead = _lead!;
    switch (module) {
      case 'admissions_fees':
        Navigator.push(context, MaterialPageRoute(builder: (_) => AdmissionsFeesScreen(leadId: lead.id)));
        break;
      case 'documents':
        Navigator.push(context, MaterialPageRoute(builder: (_) => DocumentsScreen(leadId: lead.id)));
        break;
      case 'visa_travel_student':
        Navigator.push(context, MaterialPageRoute(builder: (_) => JourneyScreen(leadId: lead.id)));
        break;
      case 'consent_compliance':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ComplianceScreen(leadId: lead.id, leadName: lead.fullName)),
        );
        break;
      case 'meetings':
        Navigator.push(context, MaterialPageRoute(builder: (_) => MeetingsScreen(leadId: lead.id)));
        break;
      case 'activity_timeline':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => LeadTimelineScreen(leadId: lead.id, leadName: lead.fullName)),
        );
        break;
      case 'calling_cockpit':
      default:
        Navigator.push(context, MaterialPageRoute(builder: (_) => CockpitScreen(leadId: lead.id)));
    }
  }

  Map<String, dynamic>? _configFor(String key) {
    for (final s in _sections) {
      if (s['section_key'] == key) return s;
    }
    return null;
  }

  bool _isEnabled(String key) => (_configFor(key)?['enabled'] as bool?) ?? true;
  // '__email' is a pseudo-section: it lives in the same launcher grid but
  // isn't part of the customizable section set, so it has no DB config and
  // needs its own label/icon fallback.
  String _labelFor(String key) =>
      key == '__email' ? 'Email' : (_configFor(key)?['custom_label'] ?? _kDefaultLabels[key] ?? key);
  IconData _iconFor(String key) => key == '__email'
      ? Icons.email_outlined
      : (_kIconOptions[_configFor(key)?['icon_override'] ?? _kDefaultIcons[key]] ?? Icons.star);

  Color _colorFor(String key, Color fallback) {
    final hex = _configFor(key)?['color_override'] as String?;
    if (hex == null) return fallback;
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.parse(h, radix: 16));
  }

  String _sizeFor(String key) => _configFor(key)?['size_override'] ?? 'standard';
  String _shapeFor(String key) => _configFor(key)?['shape_override'] ?? 'rounded';

  /// The destination + identity colour for every navigation-type section,
  /// in one place. Both the grid tiles and the (still supported) full-width
  /// button style read from this, so a section's behaviour is defined once
  /// regardless of how the user has chosen to render it.
  /// Returns null for sections that aren't simple navigation (ai_insight
  /// renders as a rich panel) or that don't apply to this lead.
  ({Color color, VoidCallback onTap})? _navActionFor(String key, Lead lead) {
    switch (key) {
      case 'calling_cockpit':
        return (
          color: Theme.of(context).colorScheme.primary,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CockpitScreen(leadId: lead.id))),
        );
      case 'whatsapp':
        if (lead.phone == null) return null;
        return (
          color: Colors.green,
          onTap: () async {
            final link = await _api.getWhatsAppChatLink(lead.id, 'Hi ${lead.fullName}, following up on your enquiry.');
            await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
            await _api.confirmWhatsAppSent(lead.id, 'Hi ${lead.fullName}, following up on your enquiry.', 'Counselor');
            _load();
          },
        );
      case 'documents':
        return (
          color: Colors.blueGrey,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DocumentsScreen(leadId: lead.id))),
        );
      case 'admissions_fees':
        return (
          color: Colors.indigo,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdmissionsFeesScreen(leadId: lead.id))),
        );
      case 'calls_voice_notes':
        return (
          color: Colors.teal,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CallsVoiceNotesScreen(leadId: lead.id))),
        );
      case 'meetings':
        return (
          color: Colors.orange,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MeetingsScreen(leadId: lead.id))),
        );
      case 'visa_travel_student':
        return (
          color: Colors.cyan,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => JourneyScreen(leadId: lead.id))),
        );
      case 'alumni':
        return (
          color: Colors.purple,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AlumniMatchScreen(leadId: lead.id))),
        );
      case 'consent_compliance':
        return (
          color: Colors.brown,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ComplianceScreen(leadId: lead.id, leadName: lead.fullName)),
          ),
        );
      case 'lead_notes':
        return (
          color: Colors.amber.shade800,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LeadNotesScreen(leadId: lead.id, leadName: lead.fullName))),
        );
      case 'flyer_studio':
        return (
          color: Colors.deepPurple,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FlyerHistoryScreen(leadId: lead.id))),
        );
      case 'activity_timeline':
        return (
          color: Colors.blueGrey,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LeadTimelineScreen(leadId: lead.id, leadName: lead.fullName))),
        );
      case 'share_logo':
        return (
          color: Colors.indigo,
          onTap: () => _shareLogoWithLead(lead),
        );
      default:
        final config = _configFor(key);
        if (config == null || config['is_custom'] != true) return null;
        final actionType = config['custom_action_type'] as String?;
        final actionValue = config['custom_action_value'] as String?;
        if (actionType == null || actionValue == null) return null;
        return (color: Colors.blueGrey, onTap: () => _launchCustomAction(actionType, actionValue));
    }
  }

  /// LeadFlow integration (Logo Studio master spec §20: "Lead Detail ->
  /// Attach Logo", "Communication Hub -> Share Logo") -- picks one of the
  /// tenant's saved brand logos and opens this lead's WhatsApp chat with
  /// it, the same wa.me-link pattern every other WhatsApp send on this
  /// screen already uses.
  Future<void> _shareLogoWithLead(Lead lead) async {
    List<Map<String, dynamic>> logos;
    try {
      logos = await _api.getTenantLogos();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load logos: $e')));
      }
      return;
    }
    if (logos.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No saved logos yet — add one in Settings > Brand Logos')));
      }
      return;
    }
    if (!mounted) return;

    final chosenId = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Share which logo with ${lead.fullName}?',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            ...logos.map((logo) {
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
    if (chosenId == null || !mounted) return;

    try {
      final share = await _api.getLogoShareLink(
        chosenId,
        leadId: lead.id,
        message: 'Hi ${lead.fullName}, here is our logo.',
      );
      final link = share['whatsapp_link']?.toString();
      if (link == null || link.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(share['warning']?.toString() ?? 'This lead has no phone number on file')));
        }
        return;
      }
      final launched = await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
      if (!launched) return;
      final message = share['message']?.toString() ?? 'Shared our logo';
      await _api.confirmWhatsAppSent(lead.id, message, 'Counselor');
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not share logo: $e')));
      }
    }
  }

  // Built once, not per-build -- the registry is static data (labels/
  // icons/screen builders), only the live _sections list changes.
  late final List<CustomizeRegistryItem> _registry = buildCustomizeRegistry();

  /// Folds the older shape_override/size_override fields (predating
  /// style_json) into equivalent style_json defaults, so a section
  /// customised before this session's fine-grained controls existed keeps
  /// looking the way it did instead of silently resetting the first time
  /// this screen renders through LauncherTile. Once a user actually opens
  /// the style editor and changes cornerRadius/contentScale directly,
  /// those explicit values take over.
  Map<String, dynamic> _effectiveStyleJson(String key) {
    final sj = (_configFor(key)?['style_json'] as Map?)?.cast<String, dynamic>() ?? {};
    final result = Map<String, dynamic>.from(sj);
    if (!result.containsKey('cornerRadius')) {
      final shape = _shapeFor(key);
      result['cornerRadius'] = shape == 'square' ? 0.0 : (shape == 'pill' ? 24.0 : 14.0);
    }
    if (!result.containsKey('contentScale')) {
      final size = _sizeFor(key);
      result['contentScale'] = size == 'compact' ? 0.85 : (size == 'large' ? 1.15 : 1.0);
    }
    return result;
  }

  /// Edit Mode entry point for a Modules tile -- mirrors More screen's
  /// _openQuickEditor exactly, so "tap a tile while Edit Mode is on"
  /// means the same thing everywhere in the app. '__email' is a
  /// pseudo-section (no DB row, no registry entry) and stays
  /// uncustomizable, same as before.
  Future<void> _openQuickEditor(String sectionKey) async {
    CustomizeRegistryItem? regItem;
    for (final r in _registry) {
      if (r.source == CustomizeSource.leadDetail && r.key == sectionKey) {
        regItem = r;
        break;
      }
    }
    if (regItem == null) return;

    final config = _configFor(sectionKey);
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => QuickStyleEditorSheet(
        item: regItem!,
        currentColorHex: (config?['color_override'] as String?) ?? '#1B2A4A',
        currentStyleVariant: (config?['style_variant'] as String?) ?? 'flat',
        currentGradientEndHex: config?['gradient_override'] as String?,
        currentStyleJson: _effectiveStyleJson(sectionKey),
      ),
    );
    if (result == null) return;
    setState(() {
      final idx = _sections.indexWhere((s) => s['section_key'] == sectionKey);
      if (idx != -1) {
        _sections[idx] = {
          ..._sections[idx],
          'color_override': result['color'],
          'style_variant': result['styleVariant'],
          'gradient_override': result['gradientEnd'],
          'style_json': result['styleJson'],
        };
      }
    });
  }

  /// Compact grid tile -- built on the same LauncherTile every other
  /// "grid of destinations" screen uses (More, Settings, Leads List),
  /// so a section's fine-grained style (corner radius, border, glow,
  /// blur, texture, free-form size) actually applies here too, not just
  /// on the More menu. Previously this screen had its own separate
  /// tile-rendering code that only understood colour/style_variant/
  /// shape_override/size_override and had never been wired to
  /// style_json at all -- so setting any of the newer per-tile controls
  /// from Settings Studio / AI Quick Restyle silently did nothing here.
  Widget _navTile(String sectionKey, Color defaultColor, VoidCallback onTap) {
    final color = _colorFor(sectionKey, defaultColor);
    final styleVariant = _configFor(sectionKey)?['style_variant'] as String? ?? 'flat';
    final gradHex = _configFor(sectionKey)?['gradient_override'] as String?;
    Color? gradientEnd;
    if (gradHex != null) {
      var gh = gradHex.replaceAll('#', '');
      if (gh.length == 6) gh = 'FF' + gh;
      gradientEnd = Color(int.parse(gh, radix: 16));
    }
    final editModeOn = sectionKey != '__email' && context.watch<EditModeSettings>().enabled;

    return LauncherTile(
      label: _labelFor(sectionKey),
      icon: _iconFor(sectionKey),
      color: color,
      gradientEnd: gradientEnd,
      styleVariant: styleVariant,
      styleJson: _effectiveStyleJson(sectionKey),
      onTap: onTap,
      onEditTap: editModeOn ? () => _openQuickEditor(sectionKey) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _lead == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final lead = _lead!;
    final orderedSections = List<Map<String, dynamic>>.from(_sections)
      ..sort((a, b) => (a['sort_order'] as int? ?? 0).compareTo(b['sort_order'] as int? ?? 0));

    // Navigation-type sections that are enabled AND actually applicable to
    // this lead (e.g. WhatsApp drops out when there's no phone number).
    // ai_insight is excluded — it renders as a full-width panel below.
    final navSections = orderedSections.where((s) {
      final key = s['section_key'] as String;
      if (key == 'ai_insight' || !_isEnabled(key)) return false;
      return _navActionFor(key, lead) != null;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(lead.fullName),
        actions: [
          IconButton(
            icon: const Icon(Icons.hub_outlined),
            tooltip: 'AI Agents',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AutomationCenterScreen(initialLeadId: lead.id, initialLeadName: lead.fullName),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Customize this screen',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CustomizeLeadDetailScreen()),
            ).then((_) => _load()),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                StageChip(stage: lead.stage),
                if (_score != null) ...[
                  const SizedBox(width: 8),
                  ScoreBadge(
                    score: _score!['score'] as int,
                    temperature: _score!['temperature'] as String,
                    onTap: () => showScoreExplanation(context, _score!),
                  ),
                ],
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: lead.stage,
                    items: _stages
                        .map((s) => DropdownMenuItem(value: s['name'] as String, child: Text('Move to ${s['name']}')))
                        .toList(),
                    onChanged: (v) {
                      if (v != null && v != lead.stage) _changeStage(v);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Lead360Panel(
              data: _lead360,
              loading: _lead360Loading,
              error: _lead360Error,
              onRefresh: _loadLead360,
              onAlertTap: _navigateToModule,
            ),
            const SizedBox(height: 16),

            // Contact details grouped into one card instead of a loose run
            // of rows, so the eye can skip past it to the modules below.
            if (lead.phone != null || lead.email != null || lead.source != null ||
                (lead.notes?.isNotEmpty ?? false) || lead.parentName != null)
              GlassContainer(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Column(
                  children: [
                    if (lead.phone != null) _infoRow(Icons.phone, lead.phone!),
                    if (lead.email != null) _infoRow(Icons.email, lead.email!),
                    if (lead.source != null) _infoRow(Icons.source, lead.source!),
                    if (lead.notes != null && lead.notes!.isNotEmpty) _infoRow(Icons.notes, lead.notes!),
                    if (lead.parentName != null)
                      _infoRow(Icons.family_restroom,
                          'Guardian: ${lead.parentName}${lead.parentPhone != null ? " (${lead.parentPhone})" : ""}'),
                  ],
                ),
              ),
            if (_customFieldDefs.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Custom Fields', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 8),
              ..._customFieldDefs.map((def) => _customFieldTile(lead, def)),
            ],
            const SizedBox(height: 20),

            // AI Insight stays a full-width rich panel — it shows content,
            // not just a destination, so it can't collapse into a tile.
            if (_isEnabled('ai_insight')) ...[
              _aiSection(),
              const SizedBox(height: 16),
            ],

            if (navSections.isNotEmpty || lead.email != null) ...[
              Row(
                children: [
                  const Text('Modules', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                  const Spacer(),
                  if (context.watch<EditModeSettings>().enabled)
                    const Text('Edit Mode -- tap a tile to restyle it',
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 10),
              // A Wrap, not GridView.count -- a fixed 3-column grid forces
              // every tile to the same cell size, which would make the
              // free-form width/height controls in the style editor a
              // no-op here even after wiring style_json through (exactly
              // the "set width, nothing happens" bug this pass fixes).
              // Mirrors More screen's own _buildGrid: each tile picks its
              // own widthFraction/tileHeight via style_json, falling back
              // to the same 3-per-row size the old GridView.count produced
              // when neither is set, so nothing shifts until a tile is
              // actually resized.
              LayoutBuilder(builder: (context, constraints) {
                const spacing = 10.0;
                final defaultCellWidth = (constraints.maxWidth - 2 * spacing) / 3;

                Widget sized(String key, Widget tile) {
                  final sj = _effectiveStyleJson(key);
                  final widthFraction = (sj['widthFraction'] as num?)?.toDouble();
                  final tileWidth = widthFraction != null
                      ? (constraints.maxWidth * widthFraction).clamp(60.0, constraints.maxWidth)
                      : defaultCellWidth;
                  final explicitHeight = (sj['tileHeight'] as num?)?.toDouble();
                  final tileHeight = explicitHeight ?? (tileWidth / 0.95);
                  return SizedBox(width: tileWidth, height: tileHeight, child: tile);
                }

                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    // Email isn't part of the customizable section set, but
                    // belongs in the same launcher grid rather than floating
                    // above it as a lone full-width button.
                    if (lead.email != null)
                      sized(
                        '__email',
                        _navTile('__email', Colors.blue, () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => EmailComposeScreen(lead: lead)),
                            )),
                      ),
                    ...navSections.map((s) {
                      final key = s['section_key'] as String;
                      final action = _navActionFor(key, lead)!;
                      return sized(key, _navTile(key, action.color, action.onTap));
                    }),
                  ],
                );
              }),
              const SizedBox(height: 20),
            ],

            const Text('Communication History', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            if (_comms.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No interactions logged yet', style: TextStyle(color: Colors.grey)),
              )
            else
              ..._comms.map(_commTile),
          ],
        ),
      ),
    );
  }

  Future<void> _launchCustomAction(String actionType, String value) async {
    Uri uri;
    switch (actionType) {
      case 'phone':
        uri = Uri(scheme: 'tel', path: value);
        break;
      case 'email':
        uri = Uri(scheme: 'mailto', path: value);
        break;
      case 'url':
      default:
        uri = Uri.parse(value);
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open: $e')));
      }
    }
  }

  Widget _customFieldTile(Lead lead, Map<String, dynamic> def) {
    final key = def['field_key'] as String;
    final currentValue = lead.customFields[key];

    if (def['field_type'] == 'select') {
      final options = (def['options'] as List?)?.cast<String>() ?? [];
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: DropdownButtonFormField<String>(
          value: options.contains(currentValue) ? currentValue as String : null,
          decoration: InputDecoration(labelText: def['label'], isDense: true, border: const OutlineInputBorder()),
          items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          onChanged: (v) async {
            if (v != null) await _api.setLeadCustomField(lead.id, key, v);
          },
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        initialValue: currentValue?.toString() ?? '',
        keyboardType: def['field_type'] == 'number' ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(labelText: def['label'], isDense: true, border: const OutlineInputBorder()),
        onFieldSubmitted: (v) async => await _api.setLeadCustomField(lead.id, key, v),
        onTapOutside: (_) => FocusScope.of(context).unfocus(),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Widget _commTile(Communication c) {
    final inbound = c.direction == 'inbound';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          inbound ? Icons.call_received : Icons.call_made,
          color: inbound ? Colors.green : Colors.blue,
        ),
        title: Text(c.body ?? '(no text)'),
        subtitle: Text('${c.channel} • ${c.createdAt}${c.createdBy != null ? ' • ${c.createdBy}' : ''}'),
        dense: true,
      ),
    );
  }

  Widget _aiSection() {
    final label = _labelFor('ai_insight');
    final color = _colorFor('ai_insight', Colors.deepPurple);
    return Card(
      color: color.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_iconFor('ai_insight'), color: color, size: 20),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(
                  onPressed: _analyzing ? null : _runAnalysis,
                  child: Text(_analyzing ? 'Analyzing...' : 'Analyze'),
                ),
              ],
            ),
            if (_aiError != null)
              Text(_aiError!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            if (_insight != null) ...[
              const SizedBox(height: 6),
              Text(_insight!.summary),
              const SizedBox(height: 6),
              Text('Sentiment: ${_insight!.sentiment} • Intent: ${_insight!.buyingIntent}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 6),
              Text('Next step: ${_insight!.suggestedNextAction}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _runAnalysis() async {
    setState(() {
      _analyzing = true;
      _aiError = null;
    });
    try {
      final insight = await _api.analyzeLead(widget.leadId);
      setState(() => _insight = insight);
    } catch (e) {
      setState(() => _aiError = e.toString());
    } finally {
      setState(() => _analyzing = false);
    }
  }
}
