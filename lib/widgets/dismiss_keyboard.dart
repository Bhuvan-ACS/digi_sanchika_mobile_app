import 'package:flutter/material.dart';

/// Wrap any subtree to automatically dismiss the soft keyboard when the user
/// taps or drags anywhere outside the focused input.
class DismissKeyboard extends StatelessWidget {
  final Widget child;

  const DismissKeyboard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        final focus = FocusManager.instance.primaryFocus;
        if (focus != null && focus.hasFocus) {
          focus.unfocus();
        }
      },
      child: child,
    );
  }
}

