import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Concept 1: Cinematic Obsidian & Liquid Gold Splash Screen
/// 360° glowing orbit ring, particle dust, spring logo reveal, expanding typography.
class SplashScreenCinematicGold extends StatefulWidget {
  final VoidCallback onFinished;
  final Duration duration;

  const SplashScreenCinematicGold({
    super.key,
    required this.onFinished,
    this.duration = const Duration(milliseconds: 2300),
  });

  @override
  State<SplashScreenCinematicGold> createState() => _SplashScreenCinematicGoldState();
}

class _SplashScreenCinematicGoldState extends State<SplashScreenCinematicGold>
    with TickerProviderStateMixin {
  late AnimationController _mainController;
  late AnimationController _orbitController;
  late AnimationController _particleController;

  late Animation<double> _logoScale;
  late Animation<double> _logoFade;
  late Animation<double> _titleFade;
  late Animation<double> _titleTracking;
  late Animation<double> _progress;
  late Animation<double> _exitFade;

  @override
  void initState() {
    super.initState();

    _mainController = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();

    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();

    // 1. Logo Reveal (Spring Pop)
    _logoScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.1, 0.55, curve: Curves.easeOutBack),
      ),
    );

    _logoFade = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.05, 0.4, curve: Curves.easeOut),
    );

    // 2. Cinematic Typography Tracking Expand
    _titleFade = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.35, 0.65, curve: Curves.easeOut),
    );

    _titleTracking = Tween<double>(begin: 1.0, end: 4.5).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.35, 0.85, curve: Curves.easeOutCubic),
      ),
    );

    // 3. Liquid Gold Progress Bar
    _progress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.3, 0.85, curve: Curves.easeInOutCubic),
      ),
    );

    // 4. Exit Transition
    _exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.88, 1.0, curve: Curves.easeInOut),
      ),
    );

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
    _orbitController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070709),
      body: AnimatedBuilder(
        animation: Listenable.merge([_mainController, _orbitController, _particleController]),
        builder: (context, child) {
          return Opacity(
            opacity: _exitFade.value.clamp(0.0, 1.0),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 1. Deep Cosmic Nebula Glow
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 0.9,
                        colors: [
                          const Color(0xFFE5A020).withOpacity(0.12),
                          const Color(0xFF1B1408).withOpacity(0.4),
                          const Color(0xFF070709),
                        ],
                        stops: const [0.0, 0.45, 1.0],
                      ),
                    ),
                  ),
                ),

                // 2. Ambient Gold Bokeh Dust Particles
                Positioned.fill(
                  child: CustomPaint(
                    painter: _GoldDustPainter(progress: _particleController.value),
                  ),
                ),

                // 3. Center Cinematic Composition
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Orbit Ring + Logo
                    SizedBox(
                      width: 220,
                      height: 220,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Custom Painter for 360 Glowing Particle Orbit
                          CustomPaint(
                            size: const Size(200, 200),
                            painter: _OrbitRingPainter(
                              rotation: _orbitController.value * 2 * math.pi,
                              glowColor: const Color(0xFFFFD466),
                            ),
                          ),

                          // 3D Gold Logo
                          FadeTransition(
                            opacity: _logoFade,
                            child: ScaleTransition(
                              scale: _logoScale,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFE5A020).withOpacity(0.35),
                                      blurRadius: 48,
                                      spreadRadius: 8,
                                    ),
                                  ],
                                ),
                                child: Image.asset(
                                  'assets/images/logo.png',
                                  width: 130,
                                  height: 130,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Cinematic Title with Animated Tracking
                    FadeTransition(
                      opacity: _titleFade,
                      child: Column(
                        children: [
                          Text(
                            'SUB-VIDEO AI',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: _titleTracking.value,
                              foreground: Paint()
                                ..shader = const LinearGradient(
                                  colors: [
                                    Color(0xFFFFF4D0),
                                    Color(0xFFFFD466),
                                    Color(0xFFE5A020),
                                  ],
                                ).createShader(const Rect.fromLTWH(0, 0, 240, 30)),
                              shadows: [
                                Shadow(
                                  color: const Color(0xFFE5A020).withOpacity(0.4),
                                  blurRadius: 16,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'AI VIDEO TRANSLATION & DUBBING SUITE',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 2.0,
                              color: Colors.white.withOpacity(0.45),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 48),

                    // Liquid Gold Progress Bar
                    FadeTransition(
                      opacity: _titleFade,
                      child: SizedBox(
                        width: 240,
                        child: Column(
                          children: [
                            Container(
                              height: 3,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor: _progress.value.clamp(0.0, 1.0),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(2),
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFFE5A020),
                                          Color(0xFFFFF0B3),
                                          Color(0xFFE5A020),
                                        ],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFFFFD466).withOpacity(0.8),
                                          blurRadius: 10,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'INITIALIZING STUDIO CORE...',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.5,
                                color: const Color(0xFFFFD466).withOpacity(0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Custom Painter for the Rotating Orbit with Particle Glow Head
class _OrbitRingPainter extends CustomPainter {
  final double rotation;
  final Color glowColor;

  _OrbitRingPainter({required this.rotation, required this.glowColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;

    // 1. Thin Base Ring
    final ringPaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, radius, ringPaint);

    // 2. Glowing Arc
    final arcPaint = Paint()
      ..shader = SweepGradient(
        startAngle: 0.0,
        endAngle: math.pi * 2,
        colors: [
          Colors.transparent,
          glowColor.withOpacity(0.1),
          glowColor.withOpacity(0.85),
        ],
        stops: const [0.0, 0.6, 1.0],
        transform: GradientRotation(rotation),
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.2;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      rotation,
      math.pi * 1.2,
      false,
      arcPaint,
    );

    // 3. Glowing Lead Particle
    final particleX = center.dx + radius * math.cos(rotation + math.pi * 1.2);
    final particleY = center.dy + radius * math.sin(rotation + math.pi * 1.2);
    final particleOffset = Offset(particleX, particleY);

    final particleGlow = Paint()
      ..color = glowColor.withOpacity(0.6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(particleOffset, 4.0, particleGlow);

    final particleCore = Paint()..color = Colors.white;
    canvas.drawCircle(particleOffset, 2.0, particleCore);
  }

  @override
  bool shouldRepaint(covariant _OrbitRingPainter oldDelegate) =>
      oldDelegate.rotation != rotation;
}

/// Custom Painter for Floating Gold Dust Bokeh
class _GoldDustPainter extends CustomPainter {
  final double progress;

  _GoldDustPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(42);
    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < 28; i++) {
      final initX = random.nextDouble() * size.width;
      final initY = random.nextDouble() * size.height;
      final speed = 0.2 + random.nextDouble() * 0.8;
      final radius = 1.0 + random.nextDouble() * 2.0;

      final currentY = (initY - (progress * speed * 80)) % size.height;
      final alpha = (0.15 + 0.35 * math.sin((progress + i) * math.pi * 2)).clamp(0.0, 1.0);

      paint.color = const Color(0xFFFFD466).withOpacity(alpha * 0.4);
      canvas.drawCircle(Offset(initX, currentY), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GoldDustPainter oldDelegate) => true;
}
