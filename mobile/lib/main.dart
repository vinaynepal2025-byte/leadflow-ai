import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';
import 'theme/appearance_settings.dart';
import 'theme/glass_settings.dart';
import 'theme/locale_settings.dart';
import 'services/api_service.dart';
import 'widgets/grain_overlay.dart';

final List<String> _bootLog = [];
final ValueNotifier<int> _bootLogTick = ValueNotifier<int>(0);

void _log(String message) {
  final line = '${DateTime.now().toIso8601String().substring(11, 19)}  $message';
  _bootLog.add(line);
  _bootLogTick.value++;
  // ignore: avoid_print
  print('[BOOT] $message');
}

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    _log('main() entered, binding initialized');
    runApp(const _BootScreen());
  }, (error, stack) {
    _log('ZONE ERROR: $error');
    _log(stack.toString());
  });
}

/// Shown immediately on launch, before any async setup runs. Because this
/// is the very first frame rendered, if setup below ever hangs or throws,
/// the boot log stays visible on screen instead of a blank/gray/blue
/// screen — the exact failure point is always readable without adb.
class _BootScreen extends StatefulWidget {
  const _BootScreen();

  @override
  State<_BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<_BootScreen> {
  bool _ready = false;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      FlutterError.onError = (FlutterErrorDetails details) {
        _log('FlutterError: ${details.exceptionAsString()}');
      };
      ErrorWidget.builder = (FlutterErrorDetails details) {
        _log('ErrorWidget: ${details.exceptionAsString()}');
        return _buildLogView();
      };

      _log('loading base url...');
      await ApiService.loadBaseUrl().timeout(
        const Duration(seconds: 5),
        onTimeout: () => _log('loadBaseUrl TIMED OUT'),
      );
      _log('base url ready: ${ApiService.baseUrl}');

      _log('checking login state...');
      _loggedIn = await AuthService().isLoggedIn().timeout(
        const Duration(seconds: 5),
        onTimeout: () => false,
      );
      _log('login state resolved: $_loggedIn');

      _log('boot complete, switching to real app');
      if (mounted) setState(() => _ready = true);
    } catch (e, st) {
      _log('BOOT EXCEPTION: $e');
      _log(st.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return MaterialApp(debugShowCheckedModeBanner: false, home: _buildLogView());
    }
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => GlassSettings()..load()),
        ChangeNotifierProvider(create: (_) => AppearanceSettings()..load()),
        ChangeNotifierProvider(create: (_) => LocaleSettings()..load()),
      ],
      child: LeadFlowApp(loggedIn: _loggedIn),
    );
  }

  Widget _buildLogView() {
    return ValueListenableBuilder<int>(
      valueListenable: _bootLogTick,
      builder: (context, _, __) {
        return Material(
          color: Colors.black,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('LeadFlow AI — starting up…',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Text(
                        _bootLog.join('\n'),
                        style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontFamily: 'monospace'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class LeadFlowApp extends StatelessWidget {
  final bool loggedIn;
  const LeadFlowApp({super.key, required this.loggedIn});

  @override
  Widget build(BuildContext context) {
    return Consumer3<AppearanceSettings, GlassSettings, LocaleSettings>(
      builder: (context, appearance, glass, locale, _) {
        return MaterialApp(
          title: 'LeadFlow AI',
          debugShowCheckedModeBanner: false,
          locale: locale.locale,
          supportedLocales: const [Locale('en'), Locale('hi'), Locale('ne')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.build(appearance, brightness: Brightness.light),
          darkTheme: AppTheme.build(appearance, brightness: Brightness.dark),
          themeMode: appearance.darkMode ? ThemeMode.dark : ThemeMode.light,
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            Widget result = MediaQuery(
              data: mq.copyWith(textScaler: TextScaler.linear(appearance.fontScale)),
              child: child ?? const SizedBox.shrink(),
            );
            if (appearance.textureEnabled) {
              result = Stack(
                children: [
                  result,
                  const Positioned.fill(child: GrainOverlay(opacity: 0.05)),
                ],
              );
            }
            if (glass.enabled) {
              result = Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            appearance.primaryColor,
                            appearance.accentColor.withValues(alpha: 0.7),
                            appearance.darkMode ? const Color(0xFF14171F) : const Color(0xFFF7F8FA),
                          ],
                          stops: const [0.0, 0.4, 1.0],
                        ),
                      ),
                    ),
                  ),
                  result,
                ],
              );
            }
            return result;
          },
          home: loggedIn ? const HomeShell() : const LoginScreen(),
        );
      },
    );
  }
}
