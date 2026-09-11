import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';

class SplashPage extends StatefulWidget {
  final VoidCallback onDone;
  const SplashPage({super.key, required this.onDone});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeIn;
  late final Animation<double> _scale;
  late final Animation<double> _logoFloat;
  bool _startExit = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _fadeIn = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    _logoFloat = Tween<double>(begin: 0, end: -10).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 0.8, curve: Curves.easeInOut),
      ),
    );
    _controller.forward();
    _schedule();
  }

  void _schedule() {
    Future.delayed(const Duration(milliseconds: 2600), () {
      if (mounted) _finish();
    });
  }

  Future<void> _finish() async {
    if (_startExit) return;
    _startExit = true;
    await _controller.reverse();
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryDark,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return FadeTransition(
            opacity: _fadeIn,
            child: Stack(
              children: [
                // Decorative circles
                Positioned(
                  top: -80,
                  right: -80,
                  child: Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primaryLight.withOpacity(0.12),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -120,
                  left: -100,
                  child: Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.accent.withOpacity(0.10),
                    ),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.translate(
                        offset: Offset(0, _logoFloat.value),
                        child: ScaleTransition(
                          scale: _scale,
                          child: Container(
                            width: 130,
                            height: 130,
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(32),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.25),
                                  blurRadius: 30,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(28),
                              child: Image.asset(
                                'assets/logo.png',
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        AppConstants.appName,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Sistem penjualan & manajemen toko buah',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 40),
                      _loadingDots(),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 32,
                  child: Text(
                    AppConstants.appCredit,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 13,
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

  Widget _loadingDots() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _Dot(index: i),
          ),
      ],
    );
  }
}

class _Dot extends StatefulWidget {
  final int index;
  const _Dot({required this.index});

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _op;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _op = Tween<double>(begin: 0.2, end: 1.0).animate(
      CurvedAnimation(
        parent: _c,
        curve: Interval(
          widget.index * 0.2,
          widget.index * 0.2 + 0.4,
          curve: Curves.easeInOut,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _op,
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
