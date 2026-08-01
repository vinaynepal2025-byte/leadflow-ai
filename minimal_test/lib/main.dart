import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme/app_theme.dart';
import 'theme/appearance_settings.dart';
import 'theme/glass_settings.dart';
import 'theme/locale_settings.dart';

final List<String> _log = [];
final ValueNotifier<int> _tick = ValueNotifier<int>(0);

void log(String msg) {
  _log.add(msg);
  _tick.value++;
}

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    log('binding initialized');

    log('google fonts config set');

    FlutterError.onError = (FlutterErrorDetails details) {
      log('FlutterError: ${details.exceptionAsString()}');
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      log('PlatformDispatcher error: $error');
      return true;
    };

    runApp(const _DiagApp());
    log('runApp called');
  }, (error, stack) {
    log('ZONE ERROR: $error');
    log(stack.toString().split('\n').take(5).join(' | '));
  });
}

class _DiagApp extends StatefulWidget {
  const _DiagApp();
  @override
  State<_DiagApp> createState() => _DiagAppState();
}

class _DiagAppState extends State<_DiagApp> {
  bool _themeReady = false;
  ThemeData? _theme;

  @override
  void initState() {
    super.initState();
    _runDiagnostics();
  }

  Future<void> _runDiagnostics() async {
    late GlassSettings glass;
    late AppearanceSettings appearance;
    late LocaleSettings locale;

    try {
      glass = GlassSettings();
      log('GlassSettings() constructed');
    } catch (e) {
      log('GlassSettings() constructor FAILED: $e');
      return;
    }

    try {
      appearance = AppearanceSettings();
      log('AppearanceSettings() constructed');
    } catch (e) {
      log('AppearanceSettings() constructor FAILED: $e');
      return;
    }

    try {
      locale = LocaleSettings();
      log('LocaleSettings() constructed');
    } catch (e) {
      log('LocaleSettings() constructor FAILED: $e');
      return;
    }

    try {
      await glass.load();
      log('glass.load() completed');
    } catch (e) {
      log('glass.load() FAILED: $e');
    }

    try {
      await appearance.load();
      log('appearance.load() completed');
    } catch (e) {
      log('appearance.load() FAILED: $e');
    }

    try {
      await locale.load();
      log('locale.load() completed');
    } catch (e) {
      log('locale.load() FAILED: $e');
    }

    try {
      final theme = AppTheme.build(appearance, brightness: Brightness.light);
      log('AppTheme.build() completed');
      if (mounted) setState(() { _theme = theme; _themeReady = true; });
    } catch (e, st) {
      log('AppTheme.build() FAILED: $e');
      log(st.toString().split('\n').take(5).join(' | '));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _themeReady ? _theme : null,
      home: ValueListenableBuilder<int>(
        valueListenable: _tick,
        builder: (context, _, __) {
          return Material(
            color: Colors.black,
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('DIAGNOSTIC LOG', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Text(
                      _log.join('\n'),
                      style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
