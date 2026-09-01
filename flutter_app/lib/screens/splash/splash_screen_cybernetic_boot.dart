import 'package:flutter/material.dart';

/// Concept 3: Cybernetic AI Boot Splash Screen
/// Sci-Fi HUD, laser scanline, animated terminal diagnostic logs, glitch hologram logo reveal.
class SplashScreenCyberneticBoot extends StatefulWidget {
  final VoidCallback onFinished;
  final Duration duration;

  const SplashScreenCyberneticBoot({
    super.key,
    required this.onFinished,
    this.duration = const Duration(milliseconds: 2400),
  });

  @override
  State<SplashScreenCyberneticBoot> createState() => _SplashScreenCyberneticBootState();
}

class _SplashScreenCyberneticBootState extends State<SplashScreenCyberneticBoot>
    with TickerProviderStateMixin {
  late AnimationController _mainController;
  late AnimationController _scanController;

  final List<String> _allLogs = [
    'PROBE: Hardware VideoToolbox H.264/HEVC ... [OK]',
    'AUDIO: Demucs MLX Stem Separator Engine ... [OK]',
    'VISION: Apple Vision OCR Subtitle Neural ... [OK]',
    'SPEECH: Whisper MLX Speech-to-Text ... [OK]',
    'SYNC: Neural Sub-Locked TTS Parity ... [READY]',
  ];

  final List<String> _activeLogs = [];

  @override
  void initState() {
    super.initState();

    _mainController = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _mainController.addListener(() {
      final val = _mainController.value;
      final step = (val * (_allLogs.length + 1)).floor();
      if (step > 0 && step <= _allLogs.length) {
        if (_activeLogs.length < step) {
          setState(() {
            _activeLogs.add(_allLogs[_activeLogs.length]);
          });
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
    _scanController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF06090E),
      body: AnimatedBuilder(
        animation: Listenable.merge([_mainController, _scanController]),
        builder: (context, child) {
          final exitVal = (_mainController.value > 0.88)
              ? (1.0 - (_mainController.value - 0.88) / 0.12).clamp(0.0, 1.0)
              : 1.0;

          return Opacity(
            opacity: exitVal,
            child: Stack(
              children: [
                // 1. Cybernetic Grid Mesh & Laser Scanline
                Positioned.fill(
                  child: CustomPaint(
                    painter: _CyberGridPainter(scanProgress: _scanController.value),
                  ),
                ),

                // 2. Top HUD Status Bar
                Positioned(
                  top: 24,
                  left: 32,
                  right: 32,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildHudText('SYS_ID: SUB_VID_AI // CORE_V2.6'),
                      _buildHudText('TARGET: DARWIN_ARM64 [METAL_ACCEL]'),
                      _buildHudText('DSP_ENGINE: SYNCED [60_FPS]'),
                    ],
                  ),
                ),

                // 3. Center Content: Holographic Logo & Terminal Logs
                Center(
                  child: Container(
                    width: 540,
                    padding: const EdgeInsets.all(36),
                    decoration: BoxDecoration(
                      color: const Color(0xFF090D14).withOpacity(0.85),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF00FFCC).withOpacity(0.25),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00FFCC).withOpacity(0.12),
                          blurRadius: 30,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Hologram Logo
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFF5A623).withOpacity(0.4),
                                    blurRadius: 32,
                                    spreadRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                            Image.asset(
                              'assets/images/logo.png',
                              width: 90,
                              height: 90,
                              fit: BoxFit.contain,
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        const Text(
                          'SUB-VIDEO AI // NEURAL WORKSPACE',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 3.5,
                            color: Color(0xFF00FFCC),
                            fontFamily: 'monospace',
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Terminal Diagnostic Box
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF030508),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.08),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final log in _activeLogs)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6.0),
                                  child: Row(
                                    children: [
                                      const Text(
                                        '⚡ ',
                                        style: TextStyle(fontSize: 10),
                                      ),
                                      Expanded(
                                        child: Text(
                                          log,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0.5,
                                            fontFamily: 'monospace',
                                            color: log.contains('[READY]')
                                                ? const Color(0xFF00FFCC)
                                                : const Color(0xFFFFD466),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (_activeLogs.length < _allLogs.length)
                                Text(
                                  '▶ Running diagnostics ...',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                    color: Colors.white.withOpacity(0.35),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Cyberpunk Progress Bar
                        LinearProgressIndicator(
                          value: _mainController.value.clamp(0.0, 1.0),
                          backgroundColor: Colors.white.withOpacity(0.06),
                          color: const Color(0xFF00FFCC),
                          minHeight: 3,
                        ),
                      ],
                    ),
                  ),
                ),

                // 4. Bottom Corner Tech Accents
                Positioned(
                  bottom: 20,
                  left: 32,
                  child: _buildHudText('SYS_MEMORY: DUAL_BUFFER // OK'),
                ),
                Positioned(
                  bottom: 20,
                  right: 32,
                  child: _buildHudText('ALL AI SUBSYSTEMS ARMED'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHudText(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        fontFamily: 'monospace',
        color: const Color(0xFF00FFCC).withOpacity(0.4),
      ),
    );
  }
}

/// Custom Painter for Cyber Grid & Laser Scanline
class _CyberGridPainter extends CustomPainter {
  final double scanProgress;

  _CyberGridPainter({required this.scanProgress});

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFF00FFCC).withOpacity(0.03)
      ..strokeWidth = 1.0;

    const step = 40.0;

    // Vertical Lines
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Horizontal Lines
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Laser Horizontal Scanline
    final scanY = scanProgress * size.height;
    final scanPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          const Color(0xFF00FFCC).withOpacity(0.35),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, scanY - 1, size.width, 2))
      ..strokeWidth = 2.0;

    canvas.drawLine(Offset(0, scanY), Offset(size.width, scanY), scanPaint);
  }

  @override
  bool shouldRepaint(covariant _CyberGridPainter oldDelegate) =>
      oldDelegate.scanProgress != scanProgress;
}
