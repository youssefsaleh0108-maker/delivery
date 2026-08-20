import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// The app's mark: a delivery bag with motion behind it.
///
/// Drawn rather than shipped as an image, for three reasons. It is crisp at every size, from the
/// 20px app-bar mark to the 96px splash tile, with no @2x/@3x set to keep in step. It re-colours
/// itself, so the same mark works white-on-rose in a header and rose-on-white on a light surface.
/// And it has no asset to declare, so any of the three apps can use it by importing the design
/// system, which they all already do.
///
/// The geometry is authored on a 100x100 grid and scaled to whatever [size] asks for. The same
/// coordinates are mirrored in `web/favicon.svg` — that one file is the exception, because a
/// browser tab cannot run Flutter.
class DeliveryLogo extends StatelessWidget {
  const DeliveryLogo({
    super.key,
    this.size = 40,
    this.background = DeliveryColors.brand,
    this.foreground = DeliveryColors.white,
    this.badge = true,
    this.semanticLabel,
  });

  /// The mark alone, no badge behind it — for placing on a surface that is already brand-coloured,
  /// like the app bar.
  const DeliveryLogo.mark({
    super.key,
    this.size = 26,
    this.foreground = DeliveryColors.white,
    this.semanticLabel,
  })  : background = Colors.transparent,
        badge = false;

  final double size;

  /// The rounded-square field behind the mark. Ignored when [badge] is false.
  final Color background;
  final Color foreground;
  final bool badge;

  /// What a screen reader should say. Left to the caller because this package carries no
  /// localisations, and the app's name is translated. Null where the mark sits beside the name
  /// already, so it is not read out twice.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final Widget painted = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _LogoPainter(
          background: background,
          foreground: foreground,
          badge: badge,
        ),
      ),
    );

    if (semanticLabel == null) {
      // A decorative mark. Excluded rather than left unlabelled, so it is not announced as an
      // anonymous graphic.
      return ExcludeSemantics(child: painted);
    }
    return Semantics(image: true, label: semanticLabel, child: painted);
  }
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter({
    required this.background,
    required this.foreground,
    required this.badge,
  });

  final Color background;
  final Color foreground;
  final bool badge;

  @override
  void paint(Canvas canvas, Size size) {
    // Everything below is in design units on a 100x100 grid, so the numbers stay readable and the
    // proportions cannot drift when the mark is drawn at a different size.
    canvas.save();
    canvas.scale(size.width / 100.0, size.height / 100.0);

    if (badge) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, 100, 100),
          const Radius.circular(26),
        ),
        Paint()..color = background,
      );
    }

    final Paint stroke = Paint()
      ..color = foreground
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;

    // Motion, on the left. Two lines rather than three, and unequal, so it reads as speed rather
    // than as a list.
    canvas.drawLine(const Offset(12, 52), const Offset(27, 52), stroke);
    canvas.drawLine(const Offset(19, 69), const Offset(31, 69), stroke);

    // The bag's handle: the top half of a circle, meeting the body exactly at its centre line.
    canvas.drawArc(
      const Rect.fromLTRB(44, 30, 72, 58),
      math.pi,
      math.pi,
      false,
      stroke,
    );

    // The body. Slightly rounder at the bottom than the top, which is how a bag actually hangs.
    canvas.drawRRect(
      RRect.fromLTRBAndCorners(
        38, 44, 82, 86,
        topLeft: const Radius.circular(7),
        topRight: const Radius.circular(7),
        bottomLeft: const Radius.circular(11),
        bottomRight: const Radius.circular(11),
      ),
      Paint()..color = foreground,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter old) =>
      old.background != background || old.foreground != foreground || old.badge != badge;
}

/// The mark beside the app's name, for a header or a sign-in screen.
class DeliveryWordmark extends StatelessWidget {
  const DeliveryWordmark({
    super.key,
    required this.title,
    this.markSize = 26,
    this.fontSize = 19,
    this.color = DeliveryColors.white,
  });

  final String title;
  final double markSize;
  final double fontSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        DeliveryLogo.mark(size: markSize, foreground: color),
        SizedBox(width: markSize * 0.32),
        Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
      ],
    );
  }
}
