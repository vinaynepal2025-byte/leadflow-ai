import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../theme/glass_settings.dart';
import '../theme/appearance_settings.dart';
import '../widgets/glass_widgets.dart';
import '../l10n/app_strings.dart';
import 'dashboard_screen.dart';
import 'leads_list_screen.dart';
import 'reminders_screen.dart';
import 'tasks_screen.dart';
import 'more_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _NavItem(this.icon, this.selectedIcon, this.label);
}

class _HomeShellState extends State<HomeShell> with SingleTickerProviderStateMixin {
  int _index = 0;
  TabController? _tabController;

  static const _screens = [
    DashboardScreen(),
    LeadsListScreen(),
    RemindersScreen(),
    TasksScreen(),
    MoreScreen(),
  ];

  static const _items = [
    _NavItem(Icons.dashboard_outlined, Icons.dashboard, 'nav_dashboard'),
    _NavItem(Icons.people_outline, Icons.people, 'nav_leads'),
    _NavItem(Icons.alarm_outlined, Icons.alarm, 'nav_followups'),
    _NavItem(Icons.checklist_outlined, Icons.checklist, 'nav_tasks'),
    _NavItem(Icons.more_horiz, Icons.more_horiz, 'nav_more'),
  ];

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glass = context.watch<GlassSettings>();
    final appearance = context.watch<AppearanceSettings>();
    final isTop = appearance.navPosition == NavPosition.top;

    if (isTop) {
      _tabController ??= TabController(length: _screens.length, vsync: this, initialIndex: _index);
      return Scaffold(
        appBar: AppBar(
          bottom: TabBar(
            controller: _tabController,
            onTap: (i) => _selectTab(i, appearance),
            tabs: _items.map((item) => Tab(icon: Icon(item.icon))).toList(),
          ),
        ),
        body: Stack(children: [IndexedStack(index: _index, children: _screens), _logoOverlay(appearance)]),
      );
    }

    return Scaffold(
      extendBody: true,
      body: Stack(children: [IndexedStack(index: _index, children: _screens), _logoOverlay(appearance)]),
      bottomNavigationBar: _customNavBar(glass, appearance),
    );
  }

  /// Floating branding logo, positioned per the user's LogoPosition
  /// choice. Lives above the IndexedStack (not inside any individual
  /// screen) so it renders consistently across every tab without
  /// touching each screen's own AppBar -- this app has no single
  /// shared AppBar, each screen builds its own.
  Widget _logoOverlay(AppearanceSettings appearance) {
    final path = appearance.customLogoPath;
    if (path == null) return const SizedBox.shrink();
    final file = File(path);
    if (!file.existsSync()) return const SizedBox.shrink();

    Alignment align;
    switch (appearance.logoPosition) {
      case LogoPosition.topLeft:
        align = Alignment.topLeft;
        break;
      case LogoPosition.topCenter:
        align = Alignment.topCenter;
        break;
      case LogoPosition.topRight:
        align = Alignment.topRight;
        break;
    }

    return SafeArea(
      child: Align(
        alignment: align,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: IgnorePointer(
            child: Image.file(file, height: 32, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  void _selectTab(int i, AppearanceSettings appearance) {
    if (appearance.haptics) HapticFeedback.selectionClick();
    setState(() => _index = i);
  }

  /// A fully custom-built bottom bar (not Flutter's stock NavigationBar)
  /// so each individual tab gets the same real press feedback — fade,
  /// glow pulse, or scale-down — that buttons and cards get elsewhere,
  /// rather than a static, non-reactive strip.
  Widget _customNavBar(GlassSettings glass, AppearanceSettings appearance) {
    final glow = navBarGlowShadow(appearance);
    final isGlassy = glass.enabled;
    final barColor = isGlassy ? Colors.white.withValues(alpha: 0.35) : Theme.of(context).navigationBarTheme.backgroundColor;
    final selectedColor = appearance.accentColor;
    final unselectedColor = isGlassy
        ? (appearance.darkMode ? Colors.white70 : appearance.primaryColor.withValues(alpha: 0.6))
        : Theme.of(context).colorScheme.onSurfaceVariant;

    Widget bar = Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: barColor,
        border: isGlassy ? Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.5))) : null,
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(_items.length, (i) {
            final selected = i == _index;
            final item = _items[i];
            final tab = Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? selectedColor.withValues(alpha: 0.18) : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(selected ? item.selectedIcon : item.icon, size: 22, color: selected ? selectedColor : unselectedColor),
                  const SizedBox(height: 2),
                  Text(context.tr(item.label), style: TextStyle(fontSize: 10, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? selectedColor : unselectedColor)),
                ],
              ),
            );
            return TouchFeedbackWrapper(
              appearance: appearance,
              radius: BorderRadius.circular(20),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _selectTab(i, appearance),
                child: tab,
              ),
            );
          }),
        ),
      ),
    );

    if (isGlassy) {
      bar = ClipRRect(
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: glass.blur, sigmaY: glass.blur), child: bar),
      );
    }
    if (glow != null) {
      bar = Container(decoration: BoxDecoration(boxShadow: [glow]), child: bar);
    }
    return bar;
  }
}
