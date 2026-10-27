

import 'package:digi_sanchika/presentations/Screens/home_page.dart';
import 'package:digi_sanchika/presentations/Screens/login_page.dart';
import 'package:digi_sanchika/screens/onboarding_screen.dart';
import 'package:digi_sanchika/services/api_service.dart';
import 'package:digi_sanchika/services/token_storage.dart';
import 'package:digi_sanchika/theme/ui_theme.dart';
import 'package:digi_sanchika/widgets/bird_animation.dart';
import 'package:digi_sanchika/widgets/brand_wordmark.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

/// Key stored in SharedPreferences once the user finishes or skips onboarding.
const _kOnboardingDoneKey = 'onboarding_complete';

// ─── SplashScreen ─────────────────────────────────────────────────────────────
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {

  // Logo entry animation
  late final AnimationController _entryCtrl;
  late final Animation<double>   _fadeAnim;
  late final Animation<double>   _scaleAnim;

  // Loader bar — minimum display time
  late final AnimationController _loaderCtrl;
  late final Animation<double>   _loaderAnim;

  static const _minSplashDuration = Duration(milliseconds: 2800);

  // Holds the auth/prefs result while the animation plays
  late final Future<_NextRoute> _routeFuture;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    // ── Entry (fade + scale) ───────────────────────────────────────────────
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim  = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeIn);
    _scaleAnim = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutBack),
    );

    // ── Loader bar ─────────────────────────────────────────────────────────
    _loaderCtrl = AnimationController(
      vsync: this,
      duration: _minSplashDuration,
    );
    _loaderAnim = CurvedAnimation(
      parent: _loaderCtrl,
      curve: Curves.easeInOut,
    );

    // Kick off both: auth check (network) and the visual timer in parallel.
    // We navigate only when BOTH are done.
    _routeFuture = _determineNextRoute();

    _entryCtrl.forward().then((_) => _loaderCtrl.forward()).then((_) async {
      final nextRoute = await _routeFuture;
      if (mounted) _navigate(nextRoute);
    });
  }

  // ── Determine destination ─────────────────────────────────────────────────
  Future<_NextRoute> _determineNextRoute() async {
    // Run session check and prefs fetch concurrently
    final results = await Future.wait([
      _checkSession(),
      _isOnboardingDone(),
    ]);

    final hasSession      = results[0] as bool;
    final onboardingDone  = results[1] as bool;

    if (hasSession)       return _NextRoute.home;
    if (!onboardingDone)  return _NextRoute.onboarding;
    return _NextRoute.login;
  }

  Future<bool> _checkSession() async {
    try {
      final token = await TokenStorage.getAccessToken();
      if (token == null || token.trim().isEmpty) return false;

      await ApiService.initialize();
      final r = await ApiService.testAuthConnection();
      if (r['authenticated'] == true) return true;

      await ApiService.clearTokens();
    } catch (_) {}
    return false;
  }

  Future<bool> _isOnboardingDone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_kOnboardingDoneKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  // ── Navigate ──────────────────────────────────────────────────────────────
  void _navigate(_NextRoute route) {
    Widget destination;
    switch (route) {
      case _NextRoute.home:
        destination = const HomePage();
      case _NextRoute.onboarding:
        destination = const OnboardingScreen();
      case _NextRoute.login:
        destination = const LoginPage();
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, __, ___) => destination,
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _loaderCtrl.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final birdSize = (size.width * 0.82).clamp(220.0, 380.0);

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: UiColors.lightGradient),
        child: Stack(
          children: [
            Center(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: ScaleTransition(
                  scale: _scaleAnim,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      BirdFlyAnimation(size: birdSize),
                      const SizedBox(height: 8),
                      const BrandWordmark(),
                      const SizedBox(height: 10),
                      const Text(
                        'Your all-in-one digital document workspace',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.45,
                          letterSpacing: 0.1,
                          color: UiColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Loader bar at the bottom
            Positioned(
              bottom: 48,
              left: 0,
              right: 0,
              child: Center(child: _LoaderBar(animation: _loaderAnim)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Enum ─────────────────────────────────────────────────────────────────────
enum _NextRoute { home, onboarding, login }

// ─── Loader bar ───────────────────────────────────────────────────────────────
class _LoaderBar extends StatelessWidget {
  final Animation<double> animation;
  const _LoaderBar({required this.animation});

  static const double _trackWidth = 140;
  static const double _height = 4;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _trackWidth,
      height: _height,
      child: AnimatedBuilder(
        animation: animation,
        builder: (_, __) => Stack(
          children: [
            // Track
            Container(
              width: _trackWidth,
              height: _height,
              decoration: BoxDecoration(
                color: UiColors.royalBlue.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(_height / 2),
              ),
            ),
            // Fill
            Container(
              width: _trackWidth * animation.value,
              height: _height,
              decoration: BoxDecoration(
                color: UiColors.royalBlue,
                borderRadius: BorderRadius.circular(_height / 2),
                boxShadow: [
                  BoxShadow(
                    color: UiColors.royalBlue.withValues(alpha: 0.4),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
