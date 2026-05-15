import 'package:flutter/material.dart';

/// Breakpoints
const double _kMobileMax = 600;
const double _kTabletMax = 1024;

enum DeviceType { mobile, tablet, desktop }
enum WidthClass { compact, standard, expanded }

class ResponsiveHelper {
  final double screenWidth;
  final double screenHeight;
  final double pixelRatio;

  const ResponsiveHelper._({
    required this.screenWidth,
    required this.screenHeight,
    required this.pixelRatio,
  });

  factory ResponsiveHelper.of(BuildContext context) {
    final mq = MediaQuery.of(context);
    return ResponsiveHelper._(
      screenWidth: mq.size.width,
      screenHeight: mq.size.height,
      pixelRatio: mq.devicePixelRatio,
    );
  }

  // ── Device type ───────────────────────────────────────────────────────────

  bool get isMobile => screenWidth < _kMobileMax;
  bool get isTablet => screenWidth >= _kMobileMax && screenWidth < _kTabletMax;
  bool get isDesktop => screenWidth >= _kTabletMax;

  DeviceType get deviceType {
    if (isDesktop) return DeviceType.desktop;
    if (isTablet) return DeviceType.tablet;
    return DeviceType.mobile;
  }

  WidthClass get widthClass {
    if (screenWidth < _kMobileMax) return WidthClass.compact;
    if (screenWidth < _kTabletMax) return WidthClass.standard;
    return WidthClass.expanded;
  }

  // ── Dimension helpers ─────────────────────────────────────────────────────

  /// Fractional screen width  e.g. wp(0.5) = 50% of width
  double wp(double fraction) => screenWidth * fraction;

  /// Fractional screen height e.g. hp(0.5) = 50% of height
  double hp(double fraction) => screenHeight * fraction;

  // ── Font size scaling ─────────────────────────────────────────────────────

  /// Scale [size] proportionally to screen width.
  /// Base reference width is 390 (iPhone 14 logical pixels).
  /// Clamped so text never goes too tiny or too huge.
  double sp(double size) {
    const baseWidth = 390.0;
    final scale = (screenWidth / baseWidth).clamp(0.75, 1.40);
    return (size * scale).roundToDouble();
  }

  // ── Adaptive padding ──────────────────────────────────────────────────────

  /// Returns a padding value scaled to screen width.
  double p(double value) {
    const baseWidth = 390.0;
    final scale = (screenWidth / baseWidth).clamp(0.8, 1.35);
    return (value * scale).roundToDouble();
  }

  /// Horizontal padding – slightly more generous on wide screens.
  double get horizontalPadding {
    if (isDesktop) return 48;
    if (isTablet) return 32;
    return 16;
  }

  /// Standard card/section padding.
  EdgeInsets get cardPadding => EdgeInsets.all(p(12));

  EdgeInsets get pagePadding =>
      EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: p(12));

  // ── Grid columns ──────────────────────────────────────────────────────────

  /// Number of grid columns for document/folder grids.
  int get gridColumns {
    if (isDesktop) return 4;
    if (isTablet) return 3;
    return 2;
  }

  /// Number of compact-grid columns.
  int get compactGridColumns {
    if (isDesktop) return 6;
    if (isTablet) return 4;
    return 3;
  }

  // ── Convenience text styles ───────────────────────────────────────────────

  TextStyle headline(BuildContext context) => TextStyle(
        fontSize: sp(20),
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.onSurface,
      );

  TextStyle title(BuildContext context) => TextStyle(
        fontSize: sp(16),
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurface,
      );

  TextStyle body(BuildContext context) => TextStyle(
        fontSize: sp(14),
        color: Theme.of(context).colorScheme.onSurface,
      );

  TextStyle caption(BuildContext context) => TextStyle(
        fontSize: sp(12),
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
      );
}

/// Convenience extension so you can write `context.r.sp(16)` anywhere.
extension ResponsiveContext on BuildContext {
  ResponsiveHelper get r => ResponsiveHelper.of(this);
}
