import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../main.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {

  late AnimationController _textController;
  late Animation<double> _fadeText;
  late Animation<Offset> _slideText;

  @override
  void initState() {
    super.initState();

    // 🔥 Text animation
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fadeText = Tween<double>(begin: 0, end: 1).animate(_textController);

    _slideText = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeOut),
    );

    _textController.forward();

    // 🔥 Navigate after 4 sec
    Future.delayed(const Duration(seconds: 5), () {
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const AnimatedLogin(),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 700),
        ),
      );
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SplashUI(
      fadeText: _fadeText,
      slideText: _slideText,
    );
  }
}

class _SplashUI extends StatelessWidget {
  final Animation<double> fadeText;
  final Animation<Offset> slideText;

  const _SplashUI({
    required this.fadeText,
    required this.slideText,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [

          // 🌸 Gradient Background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFFF8E1FF),
                  Color(0xFFE9D5FF),
                  Color(0xFFD8B4FE),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          // ✨ Floating particles
          const FloatingParticles(),

          // 🎬 Lottie + Text
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Lottie.asset(
                  'assets/emoji/splash_screen.json',
                  width: 260,
                ),

                const SizedBox(height: 20),

                Center(
                  child: FadeTransition(
                    opacity: fadeText,
                    child: SlideTransition(
                      position: slideText,
                      child: SizedBox(
                        width: MediaQuery.of(context).size.width * 0.8,
                        child: const Text(
                          "Let's Improve Our Sadhana Together !!",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class FloatingParticles extends StatefulWidget {
  const FloatingParticles({super.key});

  @override
  State<FloatingParticles> createState() => _FloatingParticlesState();
}

class _FloatingParticlesState extends State<FloatingParticles>
    with SingleTickerProviderStateMixin {

  late AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose(); // 🔥 FIXED MEMORY LEAK
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size; // 🔥 OPTIMIZED

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {

        return Stack(
          children: List.generate(15, (index) {
            final progress = (_controller.value + index / 15) % 1;

            return Positioned(
              left: size.width * (index / 15),
              top: size.height * (1 - progress),

              child: Opacity(
                opacity: 0.3,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}