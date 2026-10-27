import 'package:flutter/material.dart';
import 'package:digi_sanchika/utils/app_fonts.dart';

/// Design tokens for Digi Sanchika.
class UiColors {
  UiColors._();

  // One blue across the whole app (Home, Upload, Login, ...).
  static const Color royalBlue = Color(0xFF4F9BF8);
  static const Color brightBlue = Color(0xFF7BC8F7);
  static const Color iceBlue = Color(0xFFDCEEFE);
  static const Color indigo = Color(0xFF1A237E);
  static const Color background = Color(0xFFF1F5F9);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF0F172A);
  static const Color muted = Color(0xFF64748B);
  static const Color border = Color(0xFFD7E1EC);

  // Home / library design system.
  static const Color primary = royalBlue;
  static const Color primaryActive = Color(0xFF3B82E8);
  static const Color primaryTint = Color(0xFFEAF2FF);
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF475569);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color danger = Color(0xFFDC2626);

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [royalBlue, Color(0xFF283593), indigo],
  );

  /// Soft white to blue/lavender backdrop used on the welcome and login pages.
  static const LinearGradient lightGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF4F7FD), Color(0xFFD7E3FA), Color(0xFFB9CCF2)],
  );

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brightBlue, royalBlue],
  );
}

class UiTheme {
  UiTheme._();

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: UiColors.royalBlue,
      primary: UiColors.royalBlue,
      secondary: UiColors.brightBlue,
      surface: UiColors.surface,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: UiColors.background,
      fontFamily: appFontFamily,
      splashFactory: InkSparkle.splashFactory,
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: UiColors.ink,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: UiColors.ink,
        ),
        bodyMedium: TextStyle(fontSize: 14, color: UiColors.muted),
      ),
    );
  }
}

/// Soft, diffused ambient card shadow reused across the app
/// (0 5px 18px -1px rgba(15, 23, 42, 0.08)).
List<BoxShadow> softShadow([double alpha = 0.10]) => [
  BoxShadow(
    color: UiColors.ink.withValues(alpha: alpha),
    blurRadius: 18,
    spreadRadius: -1,
    offset: const Offset(0, 5),
  ),
];

/// Primary-coloured glow under the floating action button.
List<BoxShadow> primaryGlow([double alpha = 0.35]) => [
  BoxShadow(
    color: UiColors.primary.withValues(alpha: alpha),
    blurRadius: 18,
    spreadRadius: 0,
    offset: const Offset(0, 8),
  ),
];

/// Fade + slight upward slide route.
Route<T> fadeSlideRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 650),
    reverseTransitionDuration: const Duration(milliseconds: 450),
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.06),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Pure cross-fade; the bird and sheet heroes provide the motion.
Route<T> fadeRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 800),
    reverseTransitionDuration: const Duration(milliseconds: 600),
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (_, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: const Interval(0, 0.6),
      ),
      child: child,
    ),
  );
}
