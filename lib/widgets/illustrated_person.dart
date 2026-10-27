import 'package:flutter/material.dart';

enum HairStyle { short, sidePart, long, bun, curly, buzz, headscarf }

/// A flat 2D illustrated person used for the avatar quick presets. Drawn in
/// code so it needs no image assets and scales to any size.
class PersonAvatarSpec {
  const PersonAvatarSpec({
    required this.background,
    required this.skin,
    required this.hair,
    required this.hairStyle,
    required this.shirt,
    this.glasses = false,
    this.beard = false,
  });

  /// Two-colour background gradient (top-left to bottom-right).
  final List<Color> background;
  final Color skin;

  /// Hair colour, or the scarf colour for [HairStyle.headscarf].
  final Color hair;
  final HairStyle hairStyle;
  final Color shirt;
  final bool glasses;
  final bool beard;
}

class IllustratedPerson extends StatelessWidget {
  const IllustratedPerson({super.key, required this.spec, required this.size});

  final PersonAvatarSpec spec;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _PersonPainter(spec),
    );
  }
}

class _PersonPainter extends CustomPainter {
  _PersonPainter(this.spec);

  final PersonAvatarSpec spec;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    Offset p(double x, double y) => Offset(x * s, y * s);
    Rect oval(double cx, double cy, double w, double h) =>
        Rect.fromCenter(center: p(cx, cy), width: w * s, height: h * s);
    Paint fill(Color c) => Paint()
      ..color = c
      ..isAntiAlias = true;

    final bounds = Offset.zero & size;
    canvas.save();
    canvas.clipPath(Path()..addOval(bounds));

    // Background
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          colors: spec.background,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(bounds),
    );

    final skinShade = Color.lerp(spec.skin, Colors.black, 0.14)!;
    final scarf = spec.hairStyle == HairStyle.headscarf;

    // Hair behind the head
    if (spec.hairStyle == HairStyle.long) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(0.27 * s, 0.24 * s, 0.73 * s, 0.76 * s),
          Radius.circular(0.2 * s),
        ),
        fill(spec.hair),
      );
    }
    if (scarf) {
      canvas.drawOval(oval(0.5, 0.46, 0.52, 0.6), fill(spec.hair));
    }

    // Shoulders / shirt
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(0.16 * s, 0.75 * s, 0.84 * s, 1.2 * s),
        Radius.circular(0.3 * s),
      ),
      fill(spec.shirt),
    );

    // Neck and neckline
    if (!scarf) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(0.43 * s, 0.56 * s, 0.57 * s, 0.8 * s),
          Radius.circular(0.05 * s),
        ),
        fill(skinShade),
      );
      canvas.drawOval(oval(0.5, 0.78, 0.18, 0.08), fill(skinShade));
    }

    // Ears
    if (!scarf) {
      canvas.drawCircle(p(0.32, 0.46), 0.045 * s, fill(spec.skin));
      canvas.drawCircle(p(0.68, 0.46), 0.045 * s, fill(spec.skin));
    }

    // Head
    canvas.drawOval(oval(0.5, 0.44, 0.34, 0.4), fill(spec.skin));

    // Hair on top of the head
    final hairPaint = fill(spec.hair);
    Path cap(double bottom) => Path.combine(
      PathOperation.intersect,
      Path()..addOval(oval(0.5, 0.42, 0.4, 0.42)),
      Path()..addRect(Rect.fromLTRB(0, 0, s, bottom * s)),
    );
    switch (spec.hairStyle) {
      case HairStyle.short:
        canvas.drawPath(cap(0.34), hairPaint);
        break;
      case HairStyle.sidePart:
        canvas.drawPath(cap(0.33), hairPaint);
        canvas.drawOval(oval(0.4, 0.32, 0.22, 0.12), hairPaint);
        break;
      case HairStyle.long:
        canvas.drawPath(cap(0.33), hairPaint);
        canvas.drawOval(oval(0.36, 0.36, 0.1, 0.2), hairPaint);
        canvas.drawOval(oval(0.64, 0.36, 0.1, 0.2), hairPaint);
        break;
      case HairStyle.bun:
        canvas.drawPath(cap(0.33), hairPaint);
        canvas.drawCircle(p(0.5, 0.18), 0.08 * s, hairPaint);
        break;
      case HairStyle.curly:
        for (final c in const [
          [0.36, 0.3],
          [0.44, 0.24],
          [0.53, 0.23],
          [0.62, 0.27],
          [0.67, 0.35],
          [0.33, 0.38],
          [0.5, 0.29],
        ]) {
          canvas.drawCircle(p(c[0], c[1]), 0.075 * s, hairPaint);
        }
        break;
      case HairStyle.buzz:
        canvas.drawPath(cap(0.31), fill(spec.hair.withAlpha(200)));
        break;
      case HairStyle.headscarf:
        // Scarf frames the face: cover the top and wrap under the chin.
        canvas.drawPath(cap(0.3), hairPaint);
        break;
    }

    // Beard
    if (spec.beard) {
      final beard = Path.combine(
        PathOperation.intersect,
        Path()..addOval(oval(0.5, 0.46, 0.35, 0.42)),
        Path()..addRect(Rect.fromLTRB(0, 0.5 * s, s, s)),
      );
      canvas.drawPath(beard, hairPaint);
      // Mouth opening in the beard
      canvas.drawOval(oval(0.5, 0.55, 0.12, 0.05), fill(spec.skin));
    }

    // Eyes
    final eye = fill(const Color(0xFF1F2937));
    canvas.drawCircle(p(0.43, 0.45), 0.02 * s, eye);
    canvas.drawCircle(p(0.57, 0.45), 0.02 * s, eye);

    // Cheeks
    final blush = fill(const Color(0xFFF87171).withAlpha(60));
    canvas.drawCircle(p(0.39, 0.51), 0.03 * s, blush);
    canvas.drawCircle(p(0.61, 0.51), 0.03 * s, blush);

    // Smile
    canvas.drawArc(
      oval(0.5, 0.52, 0.1, 0.07),
      0.15,
      2.84,
      false,
      Paint()
        ..color = const Color(0xFF7F1D1D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.018 * s
        ..strokeCap = StrokeCap.round,
    );

    // Glasses
    if (spec.glasses) {
      final frame = Paint()
        ..color = const Color(0xFF111827)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.016 * s;
      canvas.drawCircle(p(0.43, 0.45), 0.055 * s, frame);
      canvas.drawCircle(p(0.57, 0.45), 0.055 * s, frame);
      canvas.drawLine(p(0.485, 0.45), p(0.515, 0.45), frame);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_PersonPainter oldDelegate) => oldDelegate.spec != spec;
}
