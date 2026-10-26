import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import '../providers/device_provider.dart';

/// Layar animasi pemrosesan UV.
///
/// Dipakai dalam DUA skenario:
///   1. Hardware nyata  → hwResult sudah ada di provider saat layar dibuka.
///      Dalam kasus ini animasi dipersingkat (langsung 100%) lalu navigate ke result.
///   2. Mode simulasi   → tahapan fake berjalan seperti biasa (~8 detik).
class UVProcessingScreen extends ConsumerStatefulWidget {
  final Function(String) navigate;
  const UVProcessingScreen({super.key, required this.navigate});

  @override
  ConsumerState<UVProcessingScreen> createState() =>
      _UVProcessingScreenState();
}

class _UVProcessingScreenState extends ConsumerState<UVProcessingScreen>
    with TickerProviderStateMixin {
  int stageIdx = 0;
  bool _hardwareMode = false;

  late final AnimationController _scanLineController;
  late final AnimationController _rotateController;
  late final AnimationController _pulseController;
  late final AnimationController _progressController;

  final List<Map<String, dynamic>> _stages = [
    {'label': 'Inisialisasi Sensor UV...', 'sub': 'Kalibrasi panjang gelombang 365nm', 'progress': 15},
    {'label': 'Kalibrasi BC-Care...', 'sub': 'Menyesuaikan parameter fluorosensi', 'progress': 30},
    {'label': 'Memproses Citra Kamera...', 'sub': 'Akuisisi gambar resolusi tinggi', 'progress': 50},
    {'label': 'Menjalankan Analisis CNN...', 'sub': 'EfficientNetB3 — analisis mendalam', 'progress': 70},
    {'label': 'Memproses Data Spektral...', 'sub': 'Pemetaan pola fluorosensi lesi', 'progress': 85},
    {'label': 'Menyusun Laporan Klinis...', 'sub': 'Kompilasi temuan dan rekomendasi', 'progress': 95},
    {'label': 'Analisis Selesai!', 'sub': 'Hasil siap untuk ditinjau', 'progress': 100},
  ];

  @override
  void initState() {
    super.initState();
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
      value: 0.15,
    );

    // Deteksi apakah hasil hardware sudah tersedia (layar dibuka dari waiting_scan
    // mode simulasi). Untuk hardware nyata, waiting_scan langsung navigate ke 'result'.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final hwResult = ref.read(latestHardwareResultProvider);
      if (hwResult != null) {
        // Hardware result sudah ada — percepat animasi ke 100% lalu ke result
        _hardwareMode = true;
        _progressController.animateTo(1.0,
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOut);
        setState(() => stageIdx = _stages.length - 1);
        Timer(const Duration(milliseconds: 1200), () {
          if (mounted) widget.navigate('result');
        });
      } else {
        // Simulasi — jalankan tahapan seperti biasa
        _scheduleNext();
      }
    });
  }

  void _scheduleNext() {
    if (!mounted || _hardwareMode) return;
    if (stageIdx < _stages.length - 1) {
      Timer(const Duration(milliseconds: 1100), () {
        if (!mounted || _hardwareMode) return;
        setState(() => stageIdx++);
        _progressController.animateTo(
          _stages[stageIdx]['progress'] / 100.0,
          curve: Curves.easeOut,
        );
        _scheduleNext();
      });
    } else {
      Timer(const Duration(milliseconds: 900), () {
        if (mounted) widget.navigate('result');
      });
    }
  }

  @override
  void dispose() {
    _scanLineController.dispose();
    _rotateController.dispose();
    _pulseController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stage  = _stages[stageIdx];
    final isDone = stageIdx == _stages.length - 1;

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF060F1A),
            Color(0xFF091929),
            Color(0xFF0A2538),
            Color(0xFF0B3040),
          ],
          stops: [0.0, 0.4, 0.8, 1.0],
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            // Background glow
            Center(
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF0A858C).withOpacity(0.12),
                      Colors.transparent,
                    ],
                    stops: const [0, 0.7],
                  ),
                ),
              ),
            ),

            // Top bar
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(
                          color: const Color(0xFF77DAD7).withOpacity(0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.bolt_rounded,
                              color: Color(0xFF77DAD7), size: 13),
                          const SizedBox(width: 6),
                          Text(
                            _hardwareMode ? 'BC-Care · Hasil Hardware' : 'BC-Care Active',
                            style: const TextStyle(
                              color: Color(0xFF77DAD7),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => widget.navigate('dashboard'),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.1),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.15)),
                        ),
                        child: const Icon(Icons.close_rounded,
                            color: Colors.white70, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Main content
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Scan frame
                  SizedBox(
                    width: 210 + 22 * 3 * 2.0,
                    height: 210 + 22 * 3 * 2.0,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Pulsing rings
                        ...List.generate(3, (i) {
                          return AnimatedBuilder(
                            animation: _pulseController,
                            builder: (_, __) => Opacity(
                              opacity: Tween<double>(begin: 0.2, end: 0.8)
                                  .evaluate(_pulseController),
                              child: Container(
                                width: 210 + (i + 1) * 32.0,
                                height: 210 + (i + 1) * 32.0,
                                decoration: BoxDecoration(
                                  borderRadius:
                                      BorderRadius.circular(28 + (i + 1) * 6),
                                  border: Border.all(
                                    color: const Color(0xFF77DAD7)
                                        .withOpacity(0.25 - i * 0.07),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),

                        // Rotating ring
                        AnimatedBuilder(
                          animation: _rotateController,
                          builder: (_, __) => Transform.rotate(
                            angle: _rotateController.value * 2 * 3.14159,
                            child: Container(
                              width: 210 + 22 * 2.0,
                              height: 210 + 22 * 2.0,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(40),
                                border: Border.all(
                                  color: const Color(0xFF77DAD7).withOpacity(0.2),
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Scan box
                        ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: Container(
                            width: 210,
                            height: 210,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: const Color(0xFF77DAD7).withOpacity(0.45),
                                width: 2,
                              ),
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFF0A858C).withOpacity(0.15),
                                  const Color(0xFF36B8B7).withOpacity(0.08),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Stack(
                              children: [
                                // UV overlay
                                Container(
                                  decoration: BoxDecoration(
                                    gradient: RadialGradient(
                                      center: const Alignment(-0.1, 0.1),
                                      radius: 0.7,
                                      colors: [
                                        const Color(0xFF8A2BE2).withOpacity(0.45),
                                        const Color(0xFF4B0082).withOpacity(0.25),
                                        Colors.transparent,
                                      ],
                                      stops: const [0, 0.4, 0.7],
                                    ),
                                  ),
                                ),
                                // Simulated tissue
                                Positioned(
                                  top: 210 * 0.38,
                                  left: 210 * 0.35,
                                  child: Container(
                                    width: 50,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: RadialGradient(
                                        colors: [
                                          const Color(0xFFFFD278).withOpacity(0.55),
                                          const Color(0xFFFF9632).withOpacity(0.3),
                                          Colors.transparent,
                                        ],
                                        stops: const [0, 0.5, 0.8],
                                      ),
                                    ),
                                  ),
                                ),
                                // Grid lines
                                ...List.generate(3, (i) => Positioned(
                                      left: 0,
                                      right: 0,
                                      top: 210 * (i + 1) / 4,
                                      child: Container(
                                        height: 1,
                                        color: const Color(0xFF77DAD7)
                                            .withOpacity(0.08),
                                      ),
                                    )),
                                ...List.generate(3, (i) => Positioned(
                                      top: 0,
                                      bottom: 0,
                                      left: 210 * (i + 1) / 4,
                                      child: Container(
                                        width: 1,
                                        color: const Color(0xFF77DAD7)
                                            .withOpacity(0.08),
                                      ),
                                    )),
                                // Scan line
                                AnimatedBuilder(
                                  animation: _scanLineController,
                                  builder: (_, __) {
                                    final t = _scanLineController.value;
                                    final y = (t < 0.5 ? t * 2 : (1 - t) * 2);
                                    return Positioned(
                                      top: (0.08 + y * 0.8) * 210 - 1,
                                      left: 0,
                                      right: 0,
                                      child: Container(
                                        height: 2,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Colors.transparent,
                                              const Color(0xFF77DAD7).withOpacity(0.9),
                                              const Color(0xFFA5E6E2),
                                              const Color(0xFF77DAD7).withOpacity(0.9),
                                              Colors.transparent,
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                // Corner brackets
                                Positioned(top: -1, left: -1, child: _cornerBracket(topLeft: true)),
                                Positioned(top: -1, right: -1, child: _cornerBracket(topRight: true)),
                                Positioned(bottom: -1, left: -1, child: _cornerBracket(bottomLeft: true)),
                                Positioned(bottom: -1, right: -1, child: _cornerBracket(bottomRight: true)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 44),

                  // Stage label
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.1),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: Column(
                      key: ValueKey(stageIdx),
                      children: [
                        Text(
                          stage['label'] as String,
                          style: TextStyle(
                            color: isDone
                                ? const Color(0xFF77DAD7)
                                : Colors.white.withOpacity(0.9),
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          stage['sub'] as String,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Progress bar
                  SizedBox(
                    width: 240,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: AnimatedBuilder(
                        animation: _progressController,
                        builder: (_, __) => LinearProgressIndicator(
                          value: _progressController.value,
                          backgroundColor: Colors.white.withOpacity(0.1),
                          valueColor: const AlwaysStoppedAnimation(
                              Color(0xFF77DAD7)),
                          minHeight: 5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  AnimatedBuilder(
                    animation: _progressController,
                    builder: (_, __) => Text(
                      '${(_progressController.value * 100).round()}% Complete',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.4), fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom specs
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  {'label': 'UV Wavelength', 'value': '365 nm'},
                  {'label': 'CNN Model', 'value': 'EfficientNetB3'},
                  {'label': 'Sensor', 'value': 'BC-Care'},
                ].map((item) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Column(
                      children: [
                        Text(item['label']!,
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.28),
                                fontSize: 10)),
                        const SizedBox(height: 3),
                        Text(item['value']!,
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cornerBracket({
    bool topLeft = false,
    bool topRight = false,
    bool bottomLeft = false,
    bool bottomRight = false,
  }) {
    return SizedBox(
      width: 24,
      height: 24,
      child: CustomPaint(
        painter: _CornerPainter(
          topLeft: topLeft,
          topRight: topRight,
          bottomLeft: bottomLeft,
          bottomRight: bottomRight,
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final bool topLeft, topRight, bottomLeft, bottomRight;
  const _CornerPainter({
    this.topLeft = false,
    this.topRight = false,
    this.bottomLeft = false,
    this.bottomRight = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF77DAD7)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (topLeft) {
      canvas.drawLine(const Offset(0, 10), const Offset(0, 6), paint);
      canvas.drawArc(const Rect.fromLTWH(0, 0, 12, 12), 3.14159, 0.5, false, paint);
      canvas.drawLine(const Offset(6, 0), const Offset(10, 0), paint);
    }
    if (topRight) {
      canvas.drawLine(const Offset(24, 10), const Offset(24, 6), paint);
      canvas.drawArc(const Rect.fromLTWH(12, 0, 12, 12), 4.71239, 0.5, false, paint);
      canvas.drawLine(const Offset(18, 0), const Offset(14, 0), paint);
    }
    if (bottomLeft) {
      canvas.drawLine(const Offset(0, 14), const Offset(0, 18), paint);
      canvas.drawArc(const Rect.fromLTWH(0, 12, 12, 12), 1.5708, 0.5, false, paint);
      canvas.drawLine(const Offset(6, 24), const Offset(10, 24), paint);
    }
    if (bottomRight) {
      canvas.drawLine(const Offset(24, 14), const Offset(24, 18), paint);
      canvas.drawArc(const Rect.fromLTWH(12, 12, 12, 12), 0, 0.5, false, paint);
      canvas.drawLine(const Offset(18, 24), const Offset(14, 24), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
