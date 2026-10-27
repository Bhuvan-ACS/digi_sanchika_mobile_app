import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';

const String sheetHeroTag = 'auth-sheet';
const double sheetRadius = 32;

/// White bottom sheet shared by the welcome and login pages. While the route
/// transitions, only the empty rounded surface flies, so the sheet appears to
/// morph into its new shape without squashing its contents.
class SheetHero extends StatelessWidget {
  const SheetHero({super.key, required this.child});

  final Widget child;

  static const _top = BorderRadius.vertical(top: Radius.circular(sheetRadius));

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: sheetHeroTag,
      flightShuttleBuilder: (_, animation, _, _, _) => DecoratedBox(
        decoration: BoxDecoration(
          color: UiColors.surface,
          borderRadius: _top,
          boxShadow: sheetShadow,
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: UiColors.surface,
          borderRadius: _top,
          boxShadow: sheetShadow,
        ),
        child: ClipRRect(
          borderRadius: _top,
          child: Material(color: Colors.transparent, child: child),
        ),
      ),
    );
  }
}

const List<BoxShadow> sheetShadow = [
  BoxShadow(color: Color(0x240D47A1), blurRadius: 32, offset: Offset(0, -8)),
];
