import 'dart:async';
import 'dart:ui';
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
final ValueNotifier<int> _tick = ValueNotifier<int>(0);

void log(String msg) {
  _bootLog.add(msg);
  _tick.value++;
}

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    log('binding initialized');

    FlutterError.onError = (FlutterErrorDetails details) {
      log('FlutterError: ${details.exceptionAsString()}');
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      log('PlatformDispatcher error: $error');
      return true;
    };

    ApiService.loadBaseUrl().catchError((e) {
      log('loadBaseUrl failed: $e');
    });

    runApp(const _DiagRoot());
    log('runApp called');
  }, (error, stack) {
    log('ZONE ERROR: $error');
    log(stack.toString().split('\n').take(4).join(' | '));
  });
}

class _DiagRoot extends StatefulWidget {
  const _DiagRoot();
  @override
  State<_DiagRoot> createState() => _DiagRootState();
}

class _DiagRootState extends State<_DiagRoot> {
  bool _ready = false;
  bool _loggedIn = false;
  ThemeData? _lightTheme;
  ThemeData? _darkTheme;
  AppearanceSettings? _appearance;
  GlassSettings? _glass;
  LocaleSettings? _locale;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      _glass = GlassSettings();
      log('GlassSettings constructed');
      _appearance = AppearanceSettings();
      log('AppearanceSettings constructed');
      _locale = LocaleSettings();
      log('LocaleSettings constructed');
    } catch (e) {
      log('Settings construction FAILED: $e');
      return;
    }

    try {
      await _glass!.load();
      log('glass.load() done');
    } catch (e) {
      log('glass.load() FAILED: $e');
    }

    try {
      await _appearance!.load();
      log('appearance.load() done');
    } catch (e) {
      log('appearance.load() FAILED: $e');
    }

    try {
      await _locale!.load();
      log('locale.load() done');
    } catch (e) {
      log('locale.load() FAILED: $e');
    }

    try {
      _lightTheme = AppTheme.build(_appearance!, brightness: Brightness.light);
      _darkTheme = AppTheme.build(_appearance!, brightness: Brightness.dark);
      log('AppTheme.build() done for both brightnesses');
    } catch (e, st) {
      log('AppTheme.build() FAILED: $e');
      log(st.toString().split('\n').take(4).join(' | '));
      return;
    }

    try {
      _loggedIn = await AuthService().isLoggedIn();
      log('isLoggedIn resolved: $_loggedIn');
    } catch (e) {
      log('isLoggedIn FAILED: $e');
    }

    log('boot complete — switching to real app');
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _appearance == null || _glass == null || _locale == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ValueListenableBuilder<int>(
          valueListenable: _tick,
          builder: (context, _, __) => Material(
            color: Colors.black,
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('LeadFlow AI — DIAGNOSTIC BOOT',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Text(_bootLog.join('\n'),
                        style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontFamily: 'monospace')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _glass!),
        ChangeNotifierProvider.value(value: _appearance!),
        ChangeNotifierProvider.value(value: _locale!),
      ],
      child: _RealApp(loggedIn: _loggedIn),
    );
  }
}

class _RealApp extends StatelessWidget {
  final bool loggedIn;
  const _RealApp({required this.loggedIn});

  @override
  Widget build(BuildContext context) {
    return Consumer3<AppearanceSettings, GlassSettings, LocaleSettings>(
      builder: (context, appearance, glass, locale, _) {
        // Rebuilt fresh on every appearance change (font, color, mode,
        // radius, ...). Previously this received ThemeData objects built
        // once at boot, so color changes appeared to work (glass widgets
        // read AppearanceSettings directly) but font/typography changes
        // silently did nothing anywhere in the app until a full restart.
        final lightTheme = AppTheme.build(appearance, brightness: Brightness.light);
        final darkTheme = AppTheme.build(appearance, brightness: Brightness.dark);
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
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: appearance.darkMode ? ThemeMode.dark : ThemeMode.light,
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            Widget result = MediaQuery(
              data: mq.copyWith(textScaler: TextScaler.linear(appearance.fontScale)),
              child: child ?? const SizedBox.shrink(),
            );
            if (appearance.textureEnabled) {
              result = Stack(children: [result, const Positioned.fill(child: GrainOverlay(opacity: 0.05))]);
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
