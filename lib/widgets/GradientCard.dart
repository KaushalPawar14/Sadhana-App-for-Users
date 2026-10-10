import 'package:flutter/material.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTokens.dart';
import 'PressScale.dart';

// A gradient tile in one of the five styles. Looks the same in light and dark;
// text and icons inside are always the dark ink colour. Decorations are soft
// white shapes at low opacity, never lines or grids.
class GradientCard extends StatelessWidget {
  const GradientCard({
    super.key,
    required this.style,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = FolkShape.cardRadius,
    this.height,
    this.onTap,
    this.decorate = true,
    this.semanticLabel,
  });

  final FolkGradientStyle style;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double? height;
  final VoidCallback? onTap;
  final bool decorate;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);

    Widget card = Container(
      height: height,
      decoration: BoxDecoration(
        gradient: FolkGradients.of(style),
        borderRadius: borderRadius,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            if (decorate)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _DecorationPainter(style)),
                ),
              ),
            Padding(
              padding: padding,
              child: DefaultTextStyle.merge(
                style: const TextStyle(color: FolkColors.onGradient),
                child: IconTheme.merge(
                  data: const IconThemeData(color: FolkColors.onGradient),
                  child: child,
                ),
              ),
            ),
            if (onTap != null)
              Positioned.fill(
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: borderRadius,
                    onTap: onTap,
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (onTap != null) {
      card = PressScale(child: card);
    }
    return Semantics(
      button: onTap != null,
      label: semanticLabel,
      container: semanticLabel != null,
      child: card,
    );
  }
}

// Port of the SVG/CSS decorations in the design files, scaled to the card.
class _DecorationPainter extends CustomPainter {
  const _DecorationPainter(this.style);

  final FolkGradientStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    switch (style) {
      case FolkGradientStyle.green:
        _leaves(canvas, size);
      case FolkGradientStyle.violet:
        _sparkle(canvas, size);
      case FolkGradientStyle.saffron:
        _dots(canvas, size);
      case FolkGradientStyle.coral:
        _circles(canvas, size);
      case FolkGradientStyle.warm:
      case FolkGradientStyle.sky:
        break;
    }
  }

  Paint _white(double opacity) =>
      Paint()..color = Color.fromRGBO(255, 255, 255, opacity);

  // 104 box, right -14, bottom -18; two leaves.
  void _leaves(Canvas canvas, Size size) {
    const box = 104.0;
    canvas.save();
    canvas.translate(size.width - box + 14, size.height - box + 18);
    canvas.scale(box / 120);
    final big = Path()
      ..moveTo(20, 100)
      ..cubicTo(14, 56, 44, 24, 96, 20)
      ..cubicTo(100, 70, 66, 104, 20, 100)
      ..close();
    final small = Path()
      ..moveTo(52, 114)
      ..cubicTo(48, 86, 66, 68, 98, 64)
      ..cubicTo(100, 92, 80, 114, 52, 114)
      ..close();
    canvas.drawPath(big, _white(.4));
    canvas.drawPath(small, _white(.3));
    canvas.restore();
  }

  // 100 box, right -16, top 12; a large and a small four-point star.
  void _sparkle(Canvas canvas, Size size) {
    const box = 100.0;
    canvas.save();
    canvas.translate(size.width - box + 16, 12);
    canvas.scale(box / 120);
    final big = Path()
      ..moveTo(60, 8)
      ..cubicTo(63, 40, 80, 57, 112, 60)
      ..cubicTo(80, 63, 63, 80, 60, 112)
      ..cubicTo(57, 80, 40, 63, 8, 60)
      ..cubicTo(40, 57, 57, 40, 60, 8)
      ..close();
    final small = Path()
      ..moveTo(22, 14)
      ..cubicTo(23, 24, 26, 27, 36, 28)
      ..cubicTo(26, 29, 23, 32, 22, 42)
      ..cubicTo(21, 32, 18, 29, 8, 28)
      ..cubicTo(18, 27, 21, 24, 22, 14)
      ..close();
    canvas.drawPath(big, _white(.42));
    canvas.drawPath(small, _white(.55));
    canvas.restore();
  }

  // Soft white dots, 26 dp apart, starting 6 dp in.
  void _dots(Canvas canvas, Size size) {
    final paint = _white(.65);
    for (double y = 6 + 13; y < size.height; y += 26) {
      for (double x = 6 + 13; x < size.width; x += 26) {
        canvas.drawCircle(Offset(x, y), 2, paint);
      }
    }
  }

  // Circles and one ring, positioned by percentage of the card.
  void _circles(Canvas canvas, Size size) {
    Offset at(double fx, double fy) =>
        Offset(size.width * fx, size.height * fy);
    canvas.drawCircle(at(.9, .14), 18, _white(.55));
    canvas.drawCircle(
      at(.9, .14),
      29.75,
      Paint()
        ..color = const Color.fromRGBO(255, 255, 255, .5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(at(.7, .38), 34, _white(.3));
    canvas.drawCircle(at(.97, .66), 9, _white(.3));
  }

  @override
  bool shouldRepaint(_DecorationPainter oldDelegate) =>
      oldDelegate.style != style;
}
