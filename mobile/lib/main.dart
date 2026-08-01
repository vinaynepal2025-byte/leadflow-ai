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

/// Startup on this build must NEVER await any plugin (SharedPreferences,
/// etc.) before the first frame — on some Android ROMs a plugin's native
/// call can block the entire Dart isolate synchronously, which means even
/// Future.timeout() can't fire because the event loop itself is stuck.
/// So: zero awaits before runApp. Everything plugin-related happens in the
/// background, purely fire-and-forget, and only updates the UI later via
/// setState if/when it actually completes.
void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      debugPrint('FlutterError: ${details.exceptionAsString()}');
    };

    // Fire-and-forget. baseUrl already has a sane default; if this
    // resolves later it just updates the static field for later API calls.
    ApiService.loadBaseUrl().catchError((e) {
      debugPrint('loadBaseUrl failed: $e');
    });

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => GlassSettings()..load()),
          ChangeNotifierProvider(create: (_) => AppearanceSettings()..load()),
          ChangeNotifierProvider(create: (_) => LocaleSettings()..load()),
        ],
        child: const LeadFlowApp(),
      ),
    );
  }, (error, stack) {
    debugPrint('Uncaught zone error: $error\n$stack');
  });
}

class LeadFlowApp extends StatelessWidget {
  const LeadFlowApp({super.key});

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
          // No plugin-gated startup gate anymore. Always land on LoginScreen
          // first — it's the safest, guaranteed-to-render default. If a
          // saved session exists, we check for it here, in the background,
          // AFTER the first frame is already on screen, and hand off to
          // HomeShell only if/when that resolves.
          home: const _PostFirstFrameAuthCheck(),
        );
      },
    );
  }
}

class _PostFirstFrameAuthCheck extends StatefulWidget {
  const _PostFirstFrameAuthCheck();

  @override
  State<_PostFirstFrameAuthCheck> createState() => _PostFirstFrameAuthCheckState();
}

class _PostFirstFrameAuthCheckState extends State<_PostFirstFrameAuthCheck> {
  bool _checked = false;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    // Runs after the first frame is already visible, so even if this
    // never completes, the person is never staring at a blank screen.
    AuthService().isLoggedIn().then((value) {
      if (mounted) setState(() => _loggedIn = value);
    }).catchError((e) {
      debugPrint('isLoggedIn failed: $e');
    }).whenComplete(() {
      if (mounted) setState(() => _checked = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checked && _loggedIn) return const HomeShell();
    return const LoginScreen();
  }
}
