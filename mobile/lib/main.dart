import 'dart:async';
import 'dart:io';
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

const String _logPath =
    '/storage/emulated/0/Android/data/com.leadflowai.leadflow_ai/files/crash_log.txt';

void _log(String message) {
  try {
    final file = File(_logPath);
    file.createSync(recursive: true, exclusive: false);
    file.writeAsStringSync('${DateTime.now()}: $message\n', mode: FileMode.append);
  } catch (_) {
    // Logging must never itself crash the app.
  }
}

void main() {
  runZonedGuarded(() async {
    _log('main() entered');
    WidgetsFlutterBinding.ensureInitialized();
    _log('WidgetsFlutterBinding initialized');

    FlutterError.onError = (FlutterErrorDetails details) {
      _log('FlutterError: ${details.exceptionAsString()}\n${details.stack}');
    };

    ErrorWidget.builder = (FlutterErrorDetails details) {
      _log('ErrorWidget shown: ${details.exceptionAsString()}');
      return Material(
        color: Colors.white,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Text(
              details.exceptionAsString(),
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
        ),
      );
    };

    ApiService.loadBaseUrl().timeout(
      const Duration(seconds: 5),
      onTimeout: () => _log('loadBaseUrl timed out'),
    ).catchError((e) {
      _log('loadBaseUrl failed: $e');
    });

    _log('about to call runApp');
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
    _log('runApp returned');
  }, (error, stack) {
    _log('Uncaught zone error: $error\n$stack');
  });
}

class LeadFlowApp extends StatelessWidget {
  const LeadFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    _log('LeadFlowApp.build() called');
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
          home: const _StartupGate(),
        );
      },
    );
  }
}

class _StartupGate extends StatelessWidget {
  const _StartupGate();

  @override
  Widget build(BuildContext context) {
    _log('_StartupGate.build() called');
    return FutureBuilder<bool>(
      future: AuthService().isLoggedIn().timeout(const Duration(seconds: 5), onTimeout: () => false),
      builder: (context, snapshot) {
        _log('_StartupGate FutureBuilder state: ${snapshot.connectionState}');
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        _log('_StartupGate resolved: loggedIn=${snapshot.data}');
        return (snapshot.data ?? false) ? const HomeShell() : const LoginScreen();
      },
    );
  }
}
