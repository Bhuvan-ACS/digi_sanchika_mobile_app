import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Shows [builder] centred over a dimmed, blurred backdrop with a scale + fade
/// entry/exit. Shared by the item action card and the create-folder dialog.
Future<T?> showBlurDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  String barrierLabel = 'Close',
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierLabel,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (ctx, _, _) => builder(ctx),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: curved,
                builder: (_, _) => BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: 8 * curved.value,
                    sigmaY: 8 * curved.value,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.9, end: 1).animate(curved),
              child: child,
            ),
          ),
        ],
      );
    },
  );
}
