// lib/screens/onboarding_screen.dart
//
// Shown on first launch only. Writes 'onboarding_complete = true' to
// SharedPreferences so the splash screen routes directly to login on
// subsequent cold starts.

import 'package:digi_sanchika/presentations/Screens/login_page.dart';
import 'package:digi_sanchika/theme/ui_theme.dart';
import 'package:digi_sanchika/widgets/bird_animation.dart';
import 'package:digi_sanchika/widgets/brand_wordmark.dart';
import 'package:digi_sanchika/widgets/sheet_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kOnboardingDoneKey = 'onboarding_complete';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  static const _features = <(IconData, String)>[
    (Icons.share_outlined, 'Secure File Sharing'),
    (Icons.cloud_outlined, 'Centralized Cloud Storing'),
    (Icons.visibility_outlined, 'Instant Document Viewing'),
    (Icons.cloud_sync_outlined, 'Swift Uploading & Downloading'),
  ];

  late final AnimationController _controller;
  late final List<Animation<double>> _rows;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();
    // Rows rise in one after another, top to bottom.
    _rows = List.generate(_features.length, (i) {
      final start = 0.12 * i;
      return CurvedAnimation(
        parent: _controller,
        curve: Interval(start, start + 0.45, curve: Curves.easeOutCubic),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ── Mark done + navigate ──────────────────────────────────────────────────
  Future<void> _finishOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kOnboardingDoneKey, true);
    } catch (_) {}

    if (!mounted) return;
    Navigator.of(context).pushReplacement(fadeRoute(const LoginPage()));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final hPad = (size.width * 0.07).clamp(20.0, 36.0);
    final birdSize = (size.width * 0.82).clamp(220.0, 380.0);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: UiColors.lightGradient),
        child: Column(
          children: [
            // Bird area: takes the space above the sheet.
            Expanded(
              child: SafeArea(
                bottom: false,
                child: Center(child: BirdFlyAnimation(size: birdSize)),
              ),
            ),
            SheetHero(
              child: Padding(
                padding: EdgeInsets.fromLTRB(hPad, 28, hPad, 20 + bottomPad),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                    const SizedBox(height: 18),
                    for (var i = 0; i < _features.length; i++)
                      _FeatureRow(
                        icon: _features[i].$1,
                        label: _features[i].$2,
                        animation: _rows[i],
                        showDivider: i != _features.length - 1,
                      ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _finishOnboarding,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: UiColors.royalBlue,
                          foregroundColor: Colors.white,
                          elevation: 6,
                          shadowColor: UiColors.royalBlue.withValues(
                            alpha: 0.4,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(27),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Get Started',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward_rounded, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One feature line: fixed-width icon column, vertically centred label,
/// trailing chevron and a hairline divider, so all rows line up.
class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.label,
    required this.animation,
    required this.showDivider,
  });

  final IconData icon;
  final String label;
  final Animation<double> animation;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, child) => Opacity(
        opacity: animation.value,
        child: Transform.translate(
          offset: Offset(0, 24 * (1 - animation.value)),
          child: child,
        ),
      ),
      child: Container(
        height: 62,
        decoration: BoxDecoration(
          border: showDivider
              ? const Border(bottom: BorderSide(color: UiColors.border))
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: UiColors.brightBlue.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 21, color: UiColors.royalBlue),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: UiColors.ink,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: UiColors.muted,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
