import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Stacked "Digi / Sanchika" wordmark in a display serif: "Digi" in a
/// blue→teal gradient with a wing on its D, "Sanchika" in deep navy with a
/// wing swash trailing off the final a. Scales down rather than overflowing.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.fontSize = 30});

  /// Size of each line; the wordmark is roughly 2.2× this tall.
  final double fontSize;

  static const _navy = Color(0xFF0F1E4A);
  static const _gradient = LinearGradient(
    colors: [Color(0xFF1D4ED8), Color(0xFF0EA5C6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  @override
  Widget build(BuildContext context) {
    final fs = fontSize;
    final style = TextStyle(
      fontFamily: 'Libre Baskerville',
      fontSize: fs,
      fontWeight: FontWeight.w700,
      height: 1.0,
      color: _navy,
    );
    final wing = Size(fs * 0.62, fs * 0.5);

    return Semantics(
      label: 'Digi Sanchika',
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          // Room for the wings, which sit outside the letters.
          padding: EdgeInsets.fromLTRB(fs * 0.5, fs * 0.15, fs * 0.6, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: _gradient.createShader,
                    // Taller line box so the gradient also covers the g's descender.
                    child: Text('Digi', style: style.copyWith(height: 1.3)),
                  ),
                  Positioned(
                    left: -fs * 0.46,
                    top: -fs * 0.13,
                    child: CustomPaint(
                      size: wing,
                      painter: const _WingPainter(gradient: _gradient),
                    ),
                  ),
                ],
              ),
              SizedBox(height: fs * 0.04),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Text('Sanchika', style: style),
                  Positioned(
                    right: -fs * 0.56,
                    bottom: fs * 0.21,
                    child: Transform.flip(
                      flipX: true,
                      child: CustomPaint(
                        size: wing,
                        painter: const _WingPainter(color: _navy),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A swept wing: tapered feathers rooted along a short leading edge at the
/// bottom-right of the box, all sweeping up and to the left, the longest at
/// the top. Flip it horizontally for a right-hand wing.
class _WingPainter extends CustomPainter {
  const _WingPainter({this.color, this.gradient});

  final Color? color;
  final Gradient? gradient;

  // (position along the leading edge 0–1, direction in degrees — 180 = left,
  // 270 = up — length, width), lengths and widths as fractions of the box.
  static const _feathers = <(double, double, double, double)>[
    (0.00, 204, 0.64, 0.30),
    (0.50, 218, 0.84, 0.32),
    (1.00, 233, 1.00, 0.30),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.fill;
    if (gradient != null) {
      paint.shader = gradient!.createShader(Offset.zero & size);
    } else {
      paint.color = color ?? Colors.black;
    }

    // Leading edge runs from the wing root up towards the top-right.
    final root = Offset(size.width * 0.96, size.height * 0.98);
    final shoulder = Offset(size.width * 0.9, size.height * 0.7);
    final reach = size.width * 0.95;

    for (final (t, deg, len, width) in _feathers) {
      final base = Offset.lerp(root, shoulder, t)!;
      final a = deg * math.pi / 180;
      final dir = Offset(math.cos(a), math.sin(a));
      // Perpendicular pointing up/out, so feathers bow upward like a wing.
      final normal = Offset(dir.dy, -dir.dx);
      final l = reach * len;
      final w = reach * width;
      final tip = base + dir * l + normal * (w * 0.6);

      final upper = base + dir * (l * 0.45) + normal * (w * 1.1);
      final lower = base + dir * (l * 0.6) - normal * (w * 0.25);
      final path = Path()
        ..moveTo(base.dx, base.dy)
        ..quadraticBezierTo(upper.dx, upper.dy, tip.dx, tip.dy)
        ..quadraticBezierTo(lower.dx, lower.dy, base.dx, base.dy)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_WingPainter old) =>
      old.color != color || old.gradient != gradient;
}
