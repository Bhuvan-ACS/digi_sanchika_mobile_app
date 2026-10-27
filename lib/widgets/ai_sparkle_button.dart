import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

/// Circular "AI sparkle" button for the end of a search bar.
///
/// Resting: clean white-glass circle with a multicolour sparkle, no glow.
/// Hover / press / focus: a blurred, slowly rotating blue-red-yellow-green
/// halo fades in *outside* the circle plus a thin gradient rim. Everything
/// is paint-only inside a fixed-size box, so layout never shifts, and the
/// effect is isolated to this button (no search-field or mic changes).
class AiSparkleButton extends StatefulWidget {
  const AiSparkleButton({
    super.key,
    required this.onTap,
    this.size = 36,
    this.tooltip = 'AI search',
  });

  final VoidCallback? onTap;
  final double size;
  final String tooltip;

  @override
  State<AiSparkleButton> createState() => _AiSparkleButtonState();
}

class _AiSparkleButtonState extends State<AiSparkleButton>
    with TickerProviderStateMixin {
  static const _googleColors = [
    Color(0xFF34A853), // green
    Color(0xFFFBBC05), // yellow
    Color(0xFFEA4335), // red
    Color(0xFFA142F4), // purple
    Color(0xFF4285F4), // blue
    Color(0xFF34A853), // back to green for a seamless sweep
  ];

  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );

  bool _hover = false;
  bool _pressed = false;
  bool _focused = false;
  bool _holdAfterTap = false;

  bool get _active => _hover || _pressed || _focused || _holdAfterTap;

  void _sync() {
    if (_active) {
      _glow.forward();
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _glow.reverse().whenComplete(() {
        if (!_active && mounted) _spin.stop();
      });
    }
  }

  void _handleTap() {
    // Keep the glow visible briefly after a touch tap.
    _holdAfterTap = true;
    _sync();
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      _holdAfterTap = false;
      _sync();
    });
    widget.onTap?.call();
  }

  @override
  void dispose() {
    _glow.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return Tooltip(
      message: widget.tooltip,
      child: FocusableActionDetector(
        onShowFocusHighlight: (v) {
          _focused = v;
          _sync();
        },
        onShowHoverHighlight: (v) {
          _hover = v;
          _sync();
        },
        mouseCursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) {
            _pressed = true;
            _sync();
          },
          onTapCancel: () {
            _pressed = false;
            _sync();
          },
          onTapUp: (_) {
            _pressed = false;
            _sync();
          },
          onTap: _handleTap,
          child: SizedBox(
            width: s,
            height: s,
            child: AnimatedBuilder(
              animation: Listenable.merge([_glow, _spin]),
              builder: (context, _) {
                final t = Curves.easeOut.transform(_glow.value);
                final rot = _spin.value * 2 * math.pi;
                final sweep = SweepGradient(
                  colors: _googleColors,
                  transform: GradientRotation(rot),
                );
                return Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    // Outer multicolour glow (outside the circle only).
                    if (t > 0)
                      Positioned(
                        left: -s * 0.16,
                        top: -s * 0.16,
                        right: -s * 0.16,
                        bottom: -s * 0.16,
                        child: IgnorePointer(
                          child: Opacity(
                            opacity: 0.85 * t,
                            child: ImageFiltered(
                              imageFilter:
                                  ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: sweep,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    // Gradient rim + opaque glass face.
                    Container(
                      width: s,
                      height: s,
                      padding: const EdgeInsets.all(1.6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: t > 0
                            ? sweep
                            : const LinearGradient(
                                colors: [Color(0xFFE3E8F4), Color(0xFFE3E8F4)],
                              ),
                      ),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFFFFFFF),
                        ),
                        child: ShaderMask(
                          blendMode: BlendMode.srcIn,
                          shaderCallback: (r) => const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF4285F4),
                              Color(0xFF9B72F6),
                              Color(0xFFEA6A7B),
                            ],
                          ).createShader(r),
                          child: CustomPaint(
                            size: Size.square(s * 0.52),
                            painter: _SparklePainter(),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Four-point "magic sparkle" star with a smaller companion star.
class _SparklePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    canvas.drawPath(
      _star(Offset(size.width * 0.44, size.height * 0.56), size.width * 0.44),
      paint,
    );
    canvas.drawPath(
      _star(Offset(size.width * 0.82, size.height * 0.2), size.width * 0.18),
      paint,
    );
  }

  Path _star(Offset c, double r) {
    final k = r * 0.22; // pinch of the concave sides
    return Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + k, c.dy - k, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + k, c.dy + k, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - k, c.dy + k, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - k, c.dy - k, c.dx, c.dy - r)
      ..close();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
