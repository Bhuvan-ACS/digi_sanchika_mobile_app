import 'package:digi_sanchika/utils/screen_utils.dart';
import 'package:digi_sanchika/utils/app_fonts.dart' show appFontFamily;
import 'package:flutter/material.dart';

class ActivityItem {
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final List<TextSpan> textSpans; // mix of bold (names/files) and normal text
  final String timeAgo;

  ActivityItem({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.textSpans,
    required this.timeAgo,
  });
}

/// Activity timeline. A soft green "progress" flows up the connecting lines from
/// the oldest entry to the newest, softly lighting each icon as it arrives, then
/// fades and repeats. Touching (or hovering) an icon makes it glow softly on demand.
class ActivityFeed extends StatefulWidget {
  final List<ActivityItem> activities;

  const ActivityFeed({super.key, required this.activities});

  @override
  State<ActivityFeed> createState() => _ActivityFeedState();
}

class _ActivityFeedState extends State<ActivityFeed>
    with SingleTickerProviderStateMixin {
  // Soft white highlight (kept subtle so it never overpowers the card).
  static const _light = Colors.white;

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5200),
  );

  /// Rows the user is currently touching / hovering.
  final Set<int> _touched = {};

  @override
  void initState() {
    super.initState();
    _ctrl.repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _touch(int i, {bool hold = false}) {
    setState(() => _touched.add(i));
    if (!hold) {
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _touched.remove(i));
      });
    }
  }

  void _release(int i) {
    if (mounted) setState(() => _touched.remove(i));
  }

  // ── Animation maths ─────────────────────────────────────────────────────
  // Sweep runs bottom -> top over the first 80% of the cycle, then everything
  // fades out over the last 15%.
  static const _sweepEnd = 0.8;
  static const _fadeStart = 0.85;

  double _unit(int n) => _sweepEnd / (2 * n - 1);

  /// Time at which the sweep reaches icon [k].
  double _arrive(int k, int n) => 2 * (n - 1 - k) * _unit(n);

  double _fade(double t) =>
      t > _fadeStart ? 1 - ((t - _fadeStart) / (1 - _fadeStart)) : 1;

  double _iconGlow(int k, int n, double t) {
    final u = _unit(n);
    final a = _arrive(k, n);
    if (t < a) return 0;
    final rise = ((t - a) / (u * 0.6)).clamp(0.0, 1.0);
    return Curves.easeOut.transform(rise) * _fade(t);
  }

  /// How much of the line below icon [k] (up to icon k+1) is filled.
  double _lineFill(int k, int n, double t) {
    final u = _unit(n);
    final start = _arrive(k + 1, n) + u * 0.3;
    final end = _arrive(k, n);
    if (t <= start) return 0;
    return Curves.easeInOut.transform(((t - start) / (end - start)).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final acts = widget.activities;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD7E1EC)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 18,
            spreadRadius: -1,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = _ctrl.value;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              height10,
              for (int i = 0; i < acts.length; i++)
                _buildActivityRow(
                  i,
                  acts[i],
                  lineBottomColor: i == acts.length - 1
                      ? acts[i].iconColor
                      : acts[i + 1].iconColor,
                  isLast: i == acts.length - 1,
                  glow: _touched.contains(i)
                      ? 1.0
                      : _iconGlow(i, acts.length, t),
                  lineFill: i == acts.length - 1
                      ? 0
                      : _lineFill(i, acts.length, t),
                  lineOpacity: _fade(t),
                  touched: _touched.contains(i),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildActivityRow(
    int index,
    ActivityItem item, {
    required Color lineBottomColor,
    required bool isLast,
    required double glow,
    required double lineFill,
    required double lineOpacity,
    required bool touched,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon + connecting line column
          Column(
            children: [
              _buildIcon(index, item, glow: glow, touched: touched),
              if (!isLast)
                Expanded(
                  child: _buildLine(
                    fill: lineFill,
                    opacity: lineOpacity,
                    bottomColor: lineBottomColor,
                  ),
                ),
            ],
          ),
          width10,
          // Text content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontFamily: appFontFamily,
                        fontWeight: FontWeight.w400,
                        color: Colors.black,
                        height: 1.45,
                      ),
                      children: item.textSpans,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.timeAgo,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontFamily: appFontFamily,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIcon(
    int index,
    ActivityItem item, {
    required double glow,
    required bool touched,
  }) {
    final bg = Color.lerp(item.iconBackground, _light, glow * 0.35)!;
    final fg = item.iconColor;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _touch(index, hold: true),
      onExit: (_) => _release(index),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _touch(index, hold: true),
        onTapUp: (_) {
          Future.delayed(const Duration(milliseconds: 700), () => _release(index));
        },
        onTapCancel: () => _release(index),
        child: AnimatedScale(
          scale: 1 + 0.06 * glow + (touched ? 0.03 : 0),
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              border: Border.all(
                color: _light.withValues(alpha: 0.9 * glow),
                width: 1.5,
              ),
              boxShadow: [
                if (glow > 0.01) ...[
                  // soft white halo + a faint shadow so it reads on white
                  BoxShadow(
                    color: _light.withValues(alpha: 0.9 * glow),
                    blurRadius: 3 + 4 * glow,
                    spreadRadius: 1 + 1.5 * glow,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.07 * glow),
                    blurRadius: 8 * glow,
                    spreadRadius: 1,
                  ),
                ],
              ],
            ),
            child: Icon(item.icon, color: fg, size: 20),
          ),
        ),
      ),
    );
  }

  /// Grey base line with a solid animated color for each connector segment.
  /// The segment uses the lower icon's color while the light travels upward.
  ///
  /// Built without LayoutBuilder on purpose: the row is wrapped in an
  /// IntrinsicHeight, which cannot measure a LayoutBuilder.
  Widget _buildLine({
    required double fill,
    required double opacity,
    required Color bottomColor,
  }) {
    final o = opacity.clamp(0.0, 1.0);
    // Each connector owns one color: the color of the icon it is leaving.
    // The next connector changes color only after the animation reaches the
    // next icon, so adjacent colors never blend within one segment.
    final lineColor = bottomColor;
    return Container(
      width: 2,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (fill > 0)
            Positioned.fill(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: fill,
                  widthFactor: 1,
                  child: Opacity(
                    opacity: o,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: lineColor,
                        boxShadow: [
                          BoxShadow(
                            color: lineColor.withAlpha(70),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (fill > 0 && fill < 1)
            Positioned.fill(
              child: Align(
                // -1 = top, 1 = bottom: sits on the leading edge of the fill
                alignment: Alignment(0, 1 - 2 * fill),
                child: Opacity(
                  opacity: o,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: lineColor.withValues(alpha: 0.9 * o),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: lineColor.withAlpha(130),
                          blurRadius: 5,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
