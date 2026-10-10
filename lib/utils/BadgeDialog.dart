// import 'dart:math';
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
//
// import 'ColorProvider.dart';
//
// Future<void> showBadgeDialog(BuildContext context, String badgeName) {
//   final colorProvider = Provider.of<ColorProvider>(context, listen: false);
//   return showDialog(
//     context: context,
//     barrierDismissible: true,
//     barrierColor: Colors.black.withOpacity(0.65),
//     builder: (_) => BadgeDialog(badgeName: badgeName),
//   );
// }
//
// class BadgeDialog extends StatefulWidget {
//   final String badgeName;
//
//   const BadgeDialog({super.key, required this.badgeName});
//
//   @override
//   State<BadgeDialog> createState() => _BadgeDialogState();
// }
//
// class _BadgeDialogState extends State<BadgeDialog>
//     with TickerProviderStateMixin {
//   late AnimationController starController;
//   late AnimationController badgeController;
//   late Animation<double> scaleAnim;
//
//   final int starCount = 120;
//   final Random random = Random();
//
//   @override
//   void initState() {
//     super.initState();
//
//     starController = AnimationController(
//       vsync: this,
//       duration: const Duration(seconds: 10),
//     )..repeat(); // infinite stars
//
//     badgeController = AnimationController(
//       vsync: this,
//       duration: const Duration(milliseconds: 10000),
//     );
//
//     scaleAnim = CurvedAnimation(
//       parent: badgeController,
//       curve: Curves.elasticOut,
//     );
//
//     badgeController.forward(); // badge pops once
//   }
//
//   @override
//   void dispose() {
//     starController.dispose();
//     badgeController.dispose();
//     super.dispose();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final size = MediaQuery.of(context).size;
//
//     return Dialog(
//       backgroundColor: Colors.transparent,
//       child: Container(
//         width: size.width * 0.8,
//         height: size.height * 0.5,
//         decoration: BoxDecoration(
//           color: Colors.black87,
//           borderRadius: BorderRadius.circular(25),
//           boxShadow: [
//             BoxShadow(
//               color: Colors.black.withOpacity(0.8),
//               blurRadius: 25,
//             ),
//           ],
//           border: Border.all(
//             color: Colors.white,
//             width: 2.2,
//           ),
//         ),
//         child: ClipRRect(
//           borderRadius: BorderRadius.circular(25),
//           child: Stack(
//             children: [
//
//               /// ⭐ FULL STAR PARTICLES
//               AnimatedBuilder(
//                 animation: starController,
//                 builder: (_, __) {
//                   return CustomPaint(
//                     size: Size.infinite,
//                     painter: StarPainter(starController.value),
//                   );
//                 },
//               ),
//
//               /// badge content
//               Center(
//                 child: Column(
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//
//                     const Text(
//                       "Congratulations!",
//                       style: TextStyle(
//                         color: Colors.white,
//                         fontSize: 26,
//                         fontWeight: FontWeight.bold,
//                       ),
//                     ),
//
//                     const SizedBox(height: 2),
//                     const Text(
//                       "You Won ✨",
//                       style: TextStyle(
//                         color: Colors.white,
//                         fontSize: 26,
//                         fontWeight: FontWeight.bold,
//                       ),
//                     ),
//
//                     const SizedBox(height: 30),
//
//                     ScaleTransition(
//                       scale: scaleAnim,
//                       child: Image.asset(
//                         "assets/images/${widget.badgeName}.png",
//                         width: 180,
//                       ),
//                     ),
//
//                     const SizedBox(height: 20),
//
//                     Text(
//                       widget.badgeName
//                           .replaceAll("_", " ")
//                           .toUpperCase(),
//                       style: const TextStyle(
//                         color: Colors.amber,
//                         fontSize: 20,
//                         fontWeight: FontWeight.bold,
//                       ),
//                     ),
//
//                   ],
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }
//
// /// ⭐ STAR PARTICLE PAINTER
// class StarPainter extends CustomPainter {
//   final double progress;
//   final Random random = Random();
//
//   StarPainter(this.progress);
//
//   @override
//   void paint(Canvas canvas, Size size) {
//     final paint = Paint();
//
//     for (int i = 0; i < 120; i++) {
//       final x = (i * 37 % size.width);
//       final y =
//       ((i * 83 + progress * 200) % size.height);
//
//       final opacity =
//           (sin(progress * 2 * pi + i) + 1) / 2;
//
//       paint.color =
//           Colors.white.withOpacity(opacity);
//
//       canvas.drawCircle(
//         Offset(x, y),
//         random.nextDouble() * 2 + 0.5,
//         paint,
//       );
//     }
//   }
//
//   @override
//   bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
// }
import 'dart:math';
import 'package:flutter/material.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';

Future<void> showBadgeDialog(BuildContext context, String badgeName) {
  return showDialog(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.65),
    builder: (_) => BadgeDialog(badgeName: badgeName),
  );
}

class BadgeDialog extends StatefulWidget {
  final String badgeName;

  const BadgeDialog({super.key, required this.badgeName});

  @override
  State<BadgeDialog> createState() => _BadgeDialogState();
}

class _BadgeDialogState extends State<BadgeDialog>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController starController;
  late AnimationController badgeController;
  late Animation<double> scaleAnim;

  // ✅ new dialog entrance controller
  late AnimationController dialogController;
  late Animation<double> dialogScaleAnim;

  final int starCount = 120;
  final Random random = Random();

  bool _started = false;
  bool _reduced = false;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // ⭐ Stars animation (existing logic) — started in didChangeDependencies,
    // where "reduce animations" can be read.
    starController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );

    // ⭐ Badge pop animation (existing logic)
    badgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 10000),
    );
    scaleAnim = CurvedAnimation(
      parent: badgeController,
      curve: Curves.elasticOut,
    );

    // ⭐ Dialog entrance animation (new)
    dialogController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    dialogScaleAnim = CurvedAnimation(
      parent: dialogController,
      curve: Curves.easeOutBack,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = FolkMotion.reduced(context);
    if (!_started) {
      _started = true;
      if (_reduced) {
        // Reduce animations: the dialog and the badge simply appear.
        badgeController.value = 1;
        dialogController.value = 1;
      } else {
        badgeController.forward();
        dialogController.forward();
      }
    }
    _syncStars();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = state == AppLifecycleState.resumed;
    _syncStars();
  }

  // The drifting stars stop with "reduce animations" and in the background.
  void _syncStars() {
    if (_reduced || !_visible) {
      if (starController.isAnimating) starController.stop();
    } else if (!starController.isAnimating) {
      starController.repeat();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    starController.dispose();
    badgeController.dispose();
    dialogController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final text = context.folkText;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ScaleTransition(
        scale: dialogScaleAnim, // ✅ new dialog entrance animation
        child: Container(
          width: size.width * 0.8,
          // At least half the screen, and taller when the text size needs it.
          constraints: BoxConstraints(minHeight: size.height * 0.5),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: FolkGradients.saffron,
            borderRadius: BorderRadius.circular(FolkShape.cardRadius),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(FolkShape.cardRadius),
            child: Stack(
              children: [
                /// ⭐ FULL STAR PARTICLES
                Positioned.fill(
                  child: ExcludeSemantics(
                    child: AnimatedBuilder(
                      animation: starController,
                      builder: (_, __) {
                        return CustomPaint(
                          size: Size.infinite,
                          painter: StarPainter(starController.value),
                        );
                      },
                    ),
                  ),
                ),

                /// badge content
                Padding(
                  padding: const EdgeInsets.all(FolkSpace.xxl),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "Congratulations!",
                          textAlign: TextAlign.center,
                          style: text.screenTitle
                              .copyWith(color: FolkColors.onGradient, fontSize: 28),
                        ),

                        const SizedBox(height: 2),
                        Text(
                          "You Won ✨",
                          textAlign: TextAlign.center,
                          style: text.screenTitle
                              .copyWith(color: FolkColors.onGradient, fontSize: 28),
                        ),

                        const SizedBox(height: 30),

                        ScaleTransition(
                          scale: scaleAnim,
                          child: Image.asset(
                            "assets/images/${widget.badgeName}.webp",
                            width: 180,
                            semanticLabel: widget.badgeName.replaceAll("_", " "),
                          ),
                        ),

                        const SizedBox(height: 20),

                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 8),
                          decoration: BoxDecoration(
                            color: FolkColors.onGradientIconTile,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Text(
                            widget.badgeName
                                .replaceAll("_", " ")
                                .toUpperCase(),
                            style: text.chip.copyWith(
                                color: FolkColors.onGradient, fontSize: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ⭐ STAR PARTICLE PAINTER
class StarPainter extends CustomPainter {
  final double progress;
  final Random random = Random();

  StarPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    for (int i = 0; i < 120; i++) {
      final x = (i * 37 % size.width);
      final y = ((i * 83 + progress * 200) % size.height);

      final opacity = (sin(progress * 2 * pi + i) + 1) / 2;

      paint.color = Colors.white.withValues(alpha: opacity);

      canvas.drawCircle(
        Offset(x, y),
        random.nextDouble() * 2 + 0.5,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
