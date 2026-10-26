import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import '../providers/auth_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  final Function(String) navigate;
  const SplashScreen({super.key, required this.navigate});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late AnimationController _dotController;
  late AnimationController _logoController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _logoFade;
  late Animation<Offset> _logoSlide;
  late Animation<double> _dividerScale;
  late Animation<double> _subtitleFade;
  late Animation<Offset> _subtitleSlide;
  late Animation<double> _badgeFade;
  late Animation<double> _bottomFade;

  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _dotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fadeAnimation =
        CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);
    _logoFade = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _logoController, curve: const Interval(0.0, 0.4, curve: Curves.easeOut)));
    _logoSlide = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(
        CurvedAnimation(parent: _logoController, curve: const Interval(0.0, 0.4, curve: Curves.easeOut)));
    _dividerScale = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _logoController, curve: const Interval(0.27, 0.6, curve: Curves.easeOut)));
    _subtitleFade = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _logoController, curve: const Interval(0.4, 0.7, curve: Curves.easeOut)));
    _subtitleSlide = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
        CurvedAnimation(parent: _logoController, curve: const Interval(0.4, 0.7, curve: Curves.easeOut)));
    _badgeFade = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _logoController, curve: const Interval(0.6, 0.85, curve: Curves.easeOut)));
    _bottomFade = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _logoController, curve: const Interval(0.8, 1.0, curve: Curves.easeOut)));

    _fadeController.forward();
    _logoController.forward();

    // After animation, check auth state and navigate accordingly
    Timer(const Duration(milliseconds: 3200), () {
      if (mounted && !_hasNavigated) {
        _checkAuthAndNavigate();
      }
    });
  }

  void _checkAuthAndNavigate() {
    if (_hasNavigated) return;
    final authState = ref.read(authStateProvider);
    authState.when(
      data: (user) {
        _hasNavigated = true;
        if (user != null) {
          widget.navigate('dashboard');
        } else {
          widget.navigate('login');
        }
      },
      loading: () {
        // Wait a bit more and retry
        Timer(const Duration(milliseconds: 500), () {
          if (mounted) _checkAuthAndNavigate();
        });
      },
      error: (_, __) {
        _hasNavigated = true;
        widget.navigate('login');
      },
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pulseController.dispose();
    _dotController.dispose();
    _logoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-0.5, -1),
            end: Alignment(0.5, 1),
            colors: [Color(0xFF0B757B), Color(0xFF0A858C), Color(0xFF36B8B7)],
            stops: [0.0, 0.45, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Decorative background circles
            Positioned(
              top: -100,
              right: -80,
              child: Container(
                width: 340,
                height: 340,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.07),
                ),
              ),
            ),
            Positioned(
              bottom: -70,
              left: -70,
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).size.height * 0.35,
              left: -40,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF77DAD7).withOpacity(0.12),
                ),
              ),
            ),
            // Main content
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Animated scan rings + logo
                  SizedBox(
                    width: 140,
                    height: 140,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Pulsing rings
                        ...List.generate(3, (i) {
                          return AnimatedBuilder(
                            animation: _pulseController,
                            builder: (_, __) {
                              final anim = Tween<double>(
                                begin: 1.0,
                                end: 1.08,
                              ).animate(CurvedAnimation(
                                parent: _pulseController,
                                curve: Interval(
                                  i * 0.2,
                                  (i * 0.2 + 0.8).clamp(0, 1),
                                  curve: Curves.easeInOut,
                                ),
                              ));
                              return Transform.scale(
                                scale: anim.value,
                                child: Container(
                                  width: 70.0 + i * 28,
                                  height: 70.0 + i * 28,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.4 - i * 0.1),
                                      width: 2.0 - i * 0.3,
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        }),
                        // Logo circle
                        Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.2),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.35),
                              width: 2,
                            ),
                          ),
                          clipBehavior: Clip.hardEdge,
                          child: Image.asset(
                            'assets/images/logo.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  // App name
                  FadeTransition(
                    opacity: _logoFade,
                    child: SlideTransition(
                      position: _logoSlide,
                      child: const Text(
                        'VioScan',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 7.2,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Divider line
                  ScaleTransition(
                    scale: _dividerScale,
                    child: Container(
                      width: 64,
                      height: 2,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.45),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Subtitle
                  FadeTransition(
                    opacity: _subtitleFade,
                    child: SlideTransition(
                      position: _subtitleSlide,
                      child: Text(
                        'AI-Assisted UV Fluorescence Screening',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.78),
                          fontSize: 13,
                          letterSpacing: 0.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // FLARE-AI badge
                  FadeTransition(
                    opacity: _badgeFade,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.25),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedBuilder(
                            animation: _dotController,
                            builder: (_, __) {
                              return Opacity(
                                opacity: Tween<double>(begin: 0.4, end: 1.0)
                                    .evaluate(_dotController),
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFF77DAD7),
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Powered by FLARE-AI',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Bottom elements
            Positioned(
              bottom: 90,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _bottomFade,
                child: Text(
                  'PKM-KC 2026 Innovation Project',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.45),
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
            // Loading dots
            Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) {
                  return AnimatedBuilder(
                    animation: _dotController,
                    builder: (_, __) {
                      final delay = i * 0.22;
                      final t = (_dotController.value - delay).clamp(0.0, 1.0);
                      final opacity = Tween<double>(begin: 0.3, end: 1.0)
                          .transform(t < 0.5 ? t * 2 : (1 - t) * 2);
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Opacity(
                          opacity: opacity,
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.65),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }),
              ),
            ),

          ],
        ),
      ),
    );
  }
}
