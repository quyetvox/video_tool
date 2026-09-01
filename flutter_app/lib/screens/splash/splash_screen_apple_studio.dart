import 'package:flutter/material.dart';
import '../../core/app_colors.dart';

/// Concept 2: Minimalist Apple Studio Splash Screen (Borderless / Seamless Design)
/// Completely removes any outer card box or border-radius containers.
/// Clean, floating 3D gold logo, studio typography, hairline progress bar, and subtle ambient glow.
class SplashScreenAppleStudio extends StatefulWidget {
  final VoidCallback onFinished;
  final Duration duration;

  const SplashScreenAppleStudio({
    super.key,
    required this.onFinished,
    this.duration = const Duration(milliseconds: 2200),
  });

  @override
  State<SplashScreenAppleStudio> createState() => _SplashScreenAppleStudioState();
}

class _SplashScreenAppleStudioState extends State<SplashScreenAppleStudio>
    with TickerProviderStateMixin {
  late AnimationController _mainController;
  late AnimationController _shimmerController;

  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _progressAnimation;
  late Animation<double> _exitFadeAnimation;

  String _statusText = 'Loading Neural Engine Presets...';

  @override
  void initState() {
    super.initState();

    _mainController = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    // Entry Animations
    _fadeAnimation = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.0, 0.35, curve: Curves.easeOutCubic),
    );

    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOutCubic),
      ),
    );

    // Progress Bar Animation
    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.15, 0.85, curve: Curves.easeInOutCubic),
      ),
    );

    // Exit Fade Out
    _exitFadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.88, 1.0, curve: Curves.easeInOut),
      ),
    );

    // Listen for progress updates
    _mainController.addListener(() {
      final val = _mainController.value;
      if (val < 0.35) {
        if (_statusText != 'Loading Neural Engine Presets...') {
          setState(() => _statusText = 'Loading Neural Engine Presets...');
        }
      } else if (val < 0.65) {
        if (_statusText != 'Initializing Apple Vision OCR & MLX Core...') {
          setState(() => _statusText = 'Initializing Apple Vision OCR & MLX Core...');
        }
      } else if (val < 0.88) {
        if (_statusText != 'Configuring Audio Separation DSP...') {
          setState(() => _statusText = 'Configuring Audio Separation DSP...');
        }
      } else {
        if (_statusText != 'Studio Workspace Ready') {
          setState(() => _statusText = 'Studio Workspace Ready');
        }
      }
    });

    _mainController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onFinished();
      }
    });

    _mainController.forward();
  }

  @override
  void dispose() {
    _mainController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07080B),
      body: AnimatedBuilder(
        animation: _mainController,
        builder: (context, child) {
          return Opacity(
            opacity: _exitFadeAnimation.value.clamp(0.0, 1.0),
            child: Stack(
              children: [
                // 1. Subtle Radial Ambient Lighting
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 0.85,
                        colors: [
                          AppColors.primary.withOpacity(0.09),
                          const Color(0xFF101218).withOpacity(0.5),
                          const Color(0xFF07080B),
                        ],
                        stops: const [0.0, 0.45, 1.0],
                      ),
                    ),
                  ),
                ),

                // 2. Center Content (Completely Freeform & Borderless - No Card Box)
                Center(
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: ScaleTransition(
                      scale: _scaleAnimation,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Floating 3D Gold Logo with Gleam Shimmer & Ambient Glow
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              // Ambient soft gold halo glow
                              Container(
                                width: 140,
                                height: 140,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary.withOpacity(0.28),
                                      blurRadius: 48,
                                      spreadRadius: 12,
                                    ),
                                  ],
                                ),
                              ),
                              Image.asset(
                                'assets/images/logo.png',
                                width: 115,
                                height: 115,
                                fit: BoxFit.contain,
                              ),
                              // Animated light gleam line
                              AnimatedBuilder(
                                animation: _shimmerController,
                                builder: (context, _) {
                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(20),
                                    child: SizedBox(
                                      width: 115,
                                      height: 115,
                                      child: Transform.translate(
                                        offset: Offset(
                                          (_shimmerController.value * 280) - 140,
                                          0,
                                        ),
                                        child: Container(
                                          width: 32,
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.transparent,
                                                Colors.white.withOpacity(0.28),
                                                Colors.transparent,
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),

                          const SizedBox(height: 32),

                          // App Title
                          const Text(
                            'SUB-VIDEO AI',
                            style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 3.5,
                              color: Colors.white,
                            ),
                          ),

                          const SizedBox(height: 8),

                          // Subtitle
                          Text(
                            'Neural Video Translation & Dubbing Studio',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w400,
                              letterSpacing: 0.6,
                              color: Colors.white.withOpacity(0.55),
                            ),
                          ),

                          const SizedBox(height: 40),

                          // Hairline Sleek Progress Bar (No container box)
                          SizedBox(
                            width: 260,
                            child: Column(
                              children: [
                                Container(
                                  height: 2.5,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: FractionallySizedBox(
                                      widthFactor: _progressAnimation.value.clamp(0.0, 1.0),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(2),
                                          gradient: const LinearGradient(
                                            colors: [
                                              Color(0xFFE5A020),
                                              Color(0xFFFFD466),
                                            ],
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: AppColors.primary.withOpacity(0.65),
                                              blurRadius: 8,
                                              spreadRadius: 1,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 14),

                                // Dynamic Status text
                                Text(
                                  _statusText,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.3,
                                    color: Colors.white.withOpacity(0.42),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // 3. Bottom Minimalist Engine Capabilities Line (Clean text, No boxes)
                Positioned(
                  bottom: 24,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Text(
                        '⚡ Metal Accelerated   •   🧠 CoreML / MLX Core   •   🎬 4K Pro VideoToolbox',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.4,
                          color: Colors.white.withOpacity(0.32),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
