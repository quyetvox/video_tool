import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'core/providers.dart';
import 'core/python_bridge.dart';
import 'screens/splash/app_splash_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize MediaKit for high-performance desktop video playback
  MediaKit.ensureInitialized();

  // Initialize Desktop Window
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      size: Size(1366, 860),
      minimumSize: Size(1024, 700),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      title: 'Sub-Video Desktop — AI Video Translator',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });

    // Ensure graceful process cleanup on window close
    await windowManager.setPreventClose(true);
  }

  runApp(const ProviderScope(child: SubVideoDesktopApp()));
}

class SubVideoDesktopApp extends ConsumerStatefulWidget {
  const SubVideoDesktopApp({super.key});

  @override
  ConsumerState<SubVideoDesktopApp> createState() => _SubVideoDesktopAppState();
}

class _SubVideoDesktopAppState extends ConsumerState<SubVideoDesktopApp> with WindowListener {
  @override
  void initState() {
    super.initState();
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      windowManager.addListener(this);
    }
  }

  @override
  void dispose() {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowClose() async {
    // Kill all running python subprocesses cleanly
    await PythonBridge.killAll();
    await windowManager.destroy();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(appThemeModeProvider);

    return MaterialApp(
      title: 'Sub-Video Desktop',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: const AppSplashScreen(
        type: SplashScreenType.appleStudio, // Concept 2: Minimalist Apple Studio (Default)
      ),
    );
  }
}
