import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'theme/appearance_settings.dart';
import 'theme/glass_settings.dart';
import 'theme/locale_settings.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: Colors.red,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text(
            'CRASH:\n${details.exceptionAsString()}\n\nSTACK:\n${details.stack}',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ),
    );
  };

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
  };

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => GlassSettings()..load()),
        ChangeNotifierProvider(create: (_) => AppearanceSettings()..load()),
        ChangeNotifierProvider(create: (_) => LocaleSettings()..load()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer3<AppearanceSettings, GlassSettings, LocaleSettings>(
      builder: (context, appearance, glass, locale, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(appearance, brightness: Brightness.light),
          home: const Scaffold(
            backgroundColor: Colors.yellow,
            body: Center(
              child: Text(
                'THEME TEST — IF YOU SEE THIS, THEME WORKS',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      },
    );
  }
}
