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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService.loadBaseUrl();
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
}

class LeadFlowApp extends StatelessWidget {
  const LeadFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Every screen using theme-derived colors/fonts/cards (rather than a
    // hardcoded value) re-renders automatically the instant the user
    // changes anything in Customize App Look — no restart needed. This
    // single Consumer2 is what makes the customization genuinely
    // app-wide instead of only affecting a couple of hand-wired screens.
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

            // Rough Texture is independent of style mode — it can layer
            // on top of Solid, Corporate, Cartoon, anything. Painted once
            // here so it covers every screen automatically.
            if (appearance.textureEnabled) {
              result = Stack(
                children: [
                  result,
                  const Positioned.fill(child: GrainOverlay(opacity: 0.05)),
                ],
              );
            }

            // The one place that wraps every screen in the app — painting
            // the gradient backdrop here, once, is what makes Glass UI
            // apply everywhere rather than only on screens that manually
            // opted in. Individual screens (Login, Dashboard) still layer
            // their own real BackdropFilter blur on top for extra depth
            // on hero surfaces; everywhere else just sits on this
            // gradient with translucent theme-driven cards/buttons.
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

/// Decides whether to show the Login screen or go straight into the app,
/// based on whether a saved session token exists.
class _StartupGate extends StatelessWidget {
  const _StartupGate();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: AuthService().isLoggedIn(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return (snapshot.data ?? false) ? const HomeShell() : const LoginScreen();
      },
    );
  }
}
