import 'package:flutter/material.dart';
import 'package:digi_sanchika/utils/design_tokens.dart';

/// Wraps a page body with consistent horizontal gutters and max-width
/// constraints based on screen class (compact/standard/expanded).
class ResponsivePage extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;

  const ResponsivePage({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    final layout = AppLayout.of(context);
    return layout.constrain(
      Padding(
        padding: padding ?? layout.pagePadding,
        child: child,
      ),
    );
  }
}

