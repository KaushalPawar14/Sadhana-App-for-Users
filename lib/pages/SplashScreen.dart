import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../main.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../widgets/FolkPageBackground.dart';
import '../widgets/FolkStatusBar.dart';
import '../utils/ForceUpdateCheck.dart';
import 'ForceUpdateScreen.dart';

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

  /// Follow-up task, 2026-09-10 — kicked off HERE, concurrently with the
  /// splash's own timer below, so it costs no extra visible delay in the
  /// common case: a Firestore round trip comfortably finishes inside the
  /// existing 5-second window, and a slow/failed one still resolves
  /// (fails open) via its own timeout by the time that timer fires.
  late final Future<bool> _forceUpdateCheck;

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

    _forceUpdateCheck = ForceUpdateCheck.isUpdateRequired();

    // 🔥 Navigate after 4 sec
    Future.delayed(const Duration(seconds: 5), () async {
      if (!mounted) return;

      // Decided at the SAME point splash already decides where to go, so
      // the update screen wins outright — whichever branch below fires is
      // the ONLY navigation this splash screen ever performs. The normal
      // destination, `AnimatedLogin`, is what calls `markAppReady()` (the
      // one thing that can flush a queued notification route — see
      // `utils/NotificationRouter.dart`), from ITS OWN `initState()`.
      // Pushing `ForceUpdateScreen` instead means `AnimatedLogin` — and
      // therefore `markAppReady()` — is simply never reached: a
      // notification tapped while an update is required stays queued,
      // structurally unable to fire underneath or after this blocking
      // screen, rather than needing an explicit skip here.
      final mustUpdate = await _forceUpdateCheck;
      if (!mounted) return;

      if (mustUpdate) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const ForceUpdateScreen(),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 700),
          ),
        );
        return;
      }

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
    final text = context.folkText;
    final reduced = FolkMotion.reduced(context);

    final tagline = SizedBox(
      width: MediaQuery.of(context).size.width * 0.8,
      child: Text(
        "Let's Improve Our Sadhana Together !!",
        textAlign: TextAlign.center,
        style: text.topBarTitle.copyWith(fontSize: 22, height: 1.25),
      ),
    );

    return FolkStatusBar(
      child: Scaffold(
        body: FolkPageBackground(
          child: Stack(
            children: [
              // ✨ Floating particles
              const FloatingParticles(),

              // 🎬 Lottie + Text
              Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Lottie.asset(
                        'assets/emoji/splash_screen.json',
                        width: 260,
                        // Reduce animations: the first frame only.
                        animate: !reduced,
                      ),

                      const SizedBox(height: 20),

                      Center(
                        child: reduced
                            ? tagline
                            : FadeTransition(
                                opacity: fadeText,
                                child: SlideTransition(
                                  position: slideText,
                                  child: tagline,
                                ),
                              ),
                      )
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
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
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The drifting dots stand still with "reduce animations" on.
    if (FolkMotion.reduced(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose(); // 🔥 FIXED MEMORY LEAK
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size; // 🔥 OPTIMIZED
    final colors = context.folk;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {

        return Stack(
          children: List.generate(15, (index) {
            final progress = (_controller.value + index / 15) % 1;

            return Positioned(
              left: size.width * (index / 15),
              top: size.height * (1 - progress),

              // A translucent colour, not an `Opacity` layer around each of
              // the 15 moving dots.
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: colors.mutedText.withValues(alpha: .3),
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
