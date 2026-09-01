import 'package:flutter/material.dart';
import '../../layouts/main_layout.dart';
import 'splash_screen_apple_studio.dart';
import 'splash_screen_cinematic_gold.dart';
import 'splash_screen_cybernetic_boot.dart';

/// Available Splash Screen Concept Styles
enum SplashScreenType {
  /// Concept 1: Cinematic Obsidian & Liquid Gold (Particle Dust + Orbit Ring)
  cinematicGold,

  /// Concept 2: Minimalist Apple Studio Glassmorphism (Default ✨)
  appleStudio,

  /// Concept 3: Cybernetic AI Diagnostic Boot (Laser Scan + Sci-Fi HUD)
  cyberneticBoot,
}

/// Master Orchestrator for App Startup Splash
class AppSplashScreen extends StatefulWidget {
  final SplashScreenType type;

  const AppSplashScreen({
    super.key,
    this.type = SplashScreenType.appleStudio, // Concept 2 is default as requested!
  });

  @override
  State<AppSplashScreen> createState() => _AppSplashScreenState();
}

class _AppSplashScreenState extends State<AppSplashScreen> {
  bool _isNavigating = false;

  void _navigateToMain() {
    if (_isNavigating || !mounted) return;
    _isNavigating = true;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const MainLayout(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOutCubic,
            ),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.type) {
      case SplashScreenType.cinematicGold:
        return SplashScreenCinematicGold(onFinished: _navigateToMain);
      case SplashScreenType.appleStudio:
        return SplashScreenAppleStudio(onFinished: _navigateToMain);
      case SplashScreenType.cyberneticBoot:
        return SplashScreenCyberneticBoot(onFinished: _navigateToMain);
    }
  }
}
