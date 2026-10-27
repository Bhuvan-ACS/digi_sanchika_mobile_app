import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';
import 'bird_animation.dart';
import 'sheet_hero.dart';

/// Page shell for the registration pages: gradient background, flying bird,
/// back button and a white bottom sheet that wraps its content (scrolling
/// only when it would exceed [maxSheetFraction] of the screen height or the
/// space left above the keyboard).
class AuthPage extends StatelessWidget {
  const AuthPage({
    super.key,
    required this.children,
    this.maxSheetFraction = 0.58,
    this.showBack = true,
  });

  final List<Widget> children;
  final double maxSheetFraction;

  /// Hide the back arrow on pages reached by pushReplacement (e.g. login).
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final hPad = (mq.size.width * 0.07).clamp(20.0, 36.0);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: UiColors.lightGradient),
        child: LayoutBuilder(
          builder: (context, c) {
            final keyboardOpen = mq.viewInsets.bottom > 0;
            final maxSheet = keyboardOpen
                ? c.maxHeight - mq.padding.top - 56
                : c.maxHeight * maxSheetFraction;
            return Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(top: mq.padding.top + 48),
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: BirdFlyAnimation(size: 380),
                          ),
                        ),
                      ),
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: maxSheet),
                      child: SheetHero(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: SingleChildScrollView(
                                physics: const ClampingScrollPhysics(),
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                padding: EdgeInsets.fromLTRB(
                                  hPad,
                                  32,
                                  hPad,
                                  12,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: children,
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.only(
                                bottom: mq.padding.bottom + 16,
                                top: 8,
                                left: hPad,
                                right: hPad,
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.lock_outline_rounded,
                                    size: 15,
                                    color: UiColors.muted,
                                  ),
                                  SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      'Secured with enterprise-grade 256-bit encryption',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: UiColors.muted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (showBack)
                Positioned(
                  top: mq.padding.top + 4,
                  left: 8,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: UiColors.ink,
                      size: 20,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class AuthTitle extends StatelessWidget {
  const AuthTitle({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: UiColors.ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 14,
            color: UiColors.muted,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

InputDecoration authInputDecoration({
  required String label,
  required String hint,
  required IconData icon,
  Widget? suffix,
}) {
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: c, width: w),
  );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: Icon(icon, color: UiColors.royalBlue),
    suffixIcon: suffix,
    filled: true,
    fillColor: UiColors.background,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    enabledBorder: border(UiColors.border),
    disabledBorder: border(UiColors.border),
    focusedBorder: border(UiColors.brightBlue, 1.8),
    errorBorder: border(Colors.red.shade400),
    focusedErrorBorder: border(Colors.red.shade400, 1.8),
  );
}

class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: UiColors.royalBlue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: UiColors.royalBlue.withValues(alpha: 0.4),
          disabledForegroundColor: Colors.white70,
          elevation: 4,
          shadowColor: UiColors.royalBlue.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

class AuthError extends StatelessWidget {
  const AuthError(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Text(
      message,
      style: TextStyle(
        fontSize: 13,
        color: Colors.red.shade600,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
