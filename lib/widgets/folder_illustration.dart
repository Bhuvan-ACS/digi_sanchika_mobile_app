import 'package:flutter/material.dart';

/// Compact folder illustration: pale-blue back panel, a white "paper" sheet
/// peeking out, and a blue front panel. Purely visual; scales with [size].
class FolderIllustration extends StatelessWidget {
  final double size;

  const FolderIllustration({super.key, this.size = 36});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 0.82,
      child: CustomPaint(painter: _FolderPainter()),
    );
  }
}

class _FolderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final h = s.height;

    // Back panel with tab
    final back = Path()
      ..moveTo(0, h * 0.14)
      ..quadraticBezierTo(0, 0, w * 0.14, 0)
      ..lineTo(w * 0.36, 0)
      ..quadraticBezierTo(w * 0.42, 0, w * 0.46, h * 0.12)
      ..lineTo(w * 0.88, h * 0.12)
      ..quadraticBezierTo(w, h * 0.12, w, h * 0.28)
      ..lineTo(w, h * 0.86)
      ..quadraticBezierTo(w, h, w * 0.86, h)
      ..lineTo(w * 0.14, h)
      ..quadraticBezierTo(0, h, 0, h * 0.86)
      ..close();
    canvas.drawPath(
      back,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFBFD9FF), Color(0xFF8DBBFA)],
        ).createShader(Offset.zero & s),
    );

    // Paper sheet
    final paper = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.12, h * 0.2, w * 0.68, h * 0.5),
      Radius.circular(w * 0.08),
    );
    canvas.drawRRect(paper, Paint()..color = Colors.white.withAlpha(235));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.18, h * 0.27, w * 0.16, h * 0.12),
        Radius.circular(w * 0.03),
      ),
      Paint()..color = const Color(0xFFD5E2F2),
    );

    // Front panel
    final front = RRect.fromRectAndCorners(
      Rect.fromLTWH(0, h * 0.4, w, h * 0.6),
      topLeft: Radius.circular(w * 0.16),
      topRight: Radius.circular(w * 0.16),
      bottomLeft: Radius.circular(w * 0.14),
      bottomRight: Radius.circular(w * 0.14),
    );
    canvas.drawRRect(
      front,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5B9CF6), Color(0xFF3B82E8)],
        ).createShader(front.outerRect),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
