import 'package:flutter/material.dart';
import 'package:digi_sanchika/widgets/folder_illustration.dart';

/// Card-less folder: a blue folder shape *is* the container. Name, metadata
/// and the action menu sit in white over the front panel.
///
/// [frontTop] is the fraction of the height where the front panel starts;
/// the paper sheet peeks out above it. Size is dictated entirely by the
/// parent's constraints, so the shape never stretches the layout.
class FolderTile extends StatelessWidget {
  final String title;
  final List<String> details;
  final Widget menu;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double frontTop;
  final double tabWidth;
  final double titleSize;
  final double detailSize;
  final int titleLines;
  final EdgeInsets contentPadding;
  final BorderRadius radius;
  final bool dense;

  /// Shows an amber star before the menu when true.
  final bool favorite;

  const FolderTile({
    super.key,
    required this.title,
    required this.details,
    required this.menu,
    required this.onTap,
    this.onLongPress,
    this.frontTop = 0.36,
    this.tabWidth = 0.34,
    this.titleSize = 15,
    this.detailSize = 11.5,
    this.titleLines = 1,
    this.contentPadding = const EdgeInsets.fromLTRB(14, 0, 4, 10),
    this.radius = const BorderRadius.all(Radius.circular(20)),
    this.dense = false,
    this.favorite = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final compact = dense || titleSize <= 13 || c.maxWidth < 150;
        final iconSize = dense ? 58.0 : (compact ? 42.0 : 54.0);
        final padding = dense ? 12.0 : (compact ? 10.0 : 16.0);
        final titleFontSize = dense ? titleSize : (compact ? 13.0 : titleSize);
        final detailFontSize = dense ? detailSize : (compact ? 10.5 : detailSize);

        return Stack(
          children: [
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                borderRadius: radius,
                child: Ink(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: radius,
                  border: Border.all(color: Colors.grey.shade100),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: InkWell(
                  borderRadius: radius,
                  onTap: onTap,
                  onLongPress: onLongPress,
                  child: Padding(
                    padding: EdgeInsets.all(padding),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          // Menu centred on the icon, matching document cards.
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: iconSize,
                              height: iconSize,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEAF2FF),
                                borderRadius: BorderRadius.circular(
                                  compact ? 12 : 16,
                                ),
                              ),
                              child: Center(
                                child: FolderIllustration(
                                  size: dense ? 46 : (compact ? 34 : 46),
                                ),
                              ),
                            ),
                            const Spacer(),
                            if (favorite)
                              const Icon(
                                Icons.star_rounded,
                                size: 16,
                                color: Colors.amber,
                                semanticLabel: 'Favourite',
                              ),
                            menu,
                          ],
                        ),
                        SizedBox(height: dense ? 10 : (compact ? 10 : 16)),
                        Text(
                          title,
                          maxLines: compact ? 1 : titleLines,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: const Color(0xFF0F172A),
                            fontSize: titleFontSize,
                            fontWeight: FontWeight.w600,
                            height: 1.15,
                          ),
                        ),
                        if (details.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            details.first,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: detailFontSize,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        if (details.length > 1) ...[
                          const Spacer(),
                          Text(
                            details.last,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: detailFontSize,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FolderTilePainter extends CustomPainter {
  final double frontTop;
  final double tabWidth;

  _FolderTilePainter({required this.frontTop, required this.tabWidth});

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final h = s.height;
    final r = (h * 0.16).clamp(10.0, 22.0);
    final tabH = h * 0.1;
    final tabW = w * tabWidth;

    // Back panel with tab
    final back = Path()
      ..moveTo(0, r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..lineTo(tabW - r, 0)
      ..quadraticBezierTo(tabW, 0, tabW + r * 0.5, tabH)
      ..lineTo(w - r, tabH)
      ..quadraticBezierTo(w, tabH, w, tabH + r)
      ..lineTo(w, h - r)
      ..quadraticBezierTo(w, h, w - r, h)
      ..lineTo(r, h)
      ..quadraticBezierTo(0, h, 0, h - r)
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

    final frontY = h * frontTop;

    // Paper sheet peeking out behind the front panel
    final paperTop = tabH + (frontY - tabH) * 0.35;
    canvas.save();
    canvas.translate(w * 0.1, paperTop);
    canvas.rotate(-0.04);
    final paper = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w * 0.62, (frontY - paperTop) + r),
      Radius.circular(r * 0.7),
    );
    canvas.drawRRect(paper, Paint()..color = Colors.white.withAlpha(240));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.04, (frontY - paperTop) * 0.2, w * 0.1,
            (frontY - paperTop) * 0.45),
        Radius.circular(r * 0.3),
      ),
      Paint()..color = const Color(0xFFD5E2F2),
    );
    canvas.restore();

    // Front panel
    final front = RRect.fromRectAndCorners(
      Rect.fromLTWH(0, frontY, w, h - frontY),
      topLeft: Radius.circular(r),
      topRight: Radius.circular(r),
      bottomLeft: Radius.circular(r),
      bottomRight: Radius.circular(r),
    );
    canvas.drawRRect(
      front,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF4F9BF8), Color(0xFF2F86F2)],
        ).createShader(front.outerRect),
    );
  }

  @override
  bool shouldRepaint(covariant _FolderTilePainter old) =>
      old.frontTop != frontTop || old.tabWidth != tabWidth;
}
