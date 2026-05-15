import 'package:flutter/material.dart';
import 'package:digi_sanchika/utils/responsive_helper.dart';

/// App-wide responsive layout tokens (gutters, max widths, rails).
/// Keep screen-class logic centralized here.
class AppLayout {
  final double gutter;
  final double maxContentWidth;
  final bool useNavigationRail;
  final double navigationRailWidth;

  const AppLayout._({
    required this.gutter,
    required this.maxContentWidth,
    required this.useNavigationRail,
    required this.navigationRailWidth,
  });

  factory AppLayout.of(BuildContext context) {
    final r = ResponsiveHelper.of(context);

    switch (r.widthClass) {
      case WidthClass.compact:
        return const AppLayout._(
          gutter: 16,
          maxContentWidth: double.infinity,
          useNavigationRail: false,
          navigationRailWidth: 0,
        );
      case WidthClass.standard:
        return const AppLayout._(
          gutter: 20,
          maxContentWidth: 720,
          useNavigationRail: true,
          navigationRailWidth: 80,
        );
      case WidthClass.expanded:
        return const AppLayout._(
          gutter: 24,
          maxContentWidth: 960,
          useNavigationRail: true,
          navigationRailWidth: 88,
        );
    }
  }

  EdgeInsets get pagePadding => EdgeInsets.symmetric(horizontal: gutter);

  Widget constrain(Widget child) {
    if (maxContentWidth == double.infinity) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxContentWidth),
        child: child,
      ),
    );
  }
}

