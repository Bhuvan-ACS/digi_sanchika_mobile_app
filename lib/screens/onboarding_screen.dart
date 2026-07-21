// lib/presentations/Screens/onboarding_screen.dart
//
// Shown on first launch only. Writes 'onboarding_complete = true' to
// SharedPreferences so the splash screen routes directly to login on
// subsequent cold starts.

import 'package:digi_sanchika/presentations/Screens/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Constants ────────────────────────────────────────────────────────────────
const _kPrimary   = Color(0xFF2D4EE8);
const _kDeepBlue  = Color(0xFF2540D4);
const _kLightBlue = Color(0xFF3A5AF0);
const _kOnboardingDoneKey = 'onboarding_complete';

// ─── Page model ───────────────────────────────────────────────────────────────
class _PageData {
  final IconData icon;
  final String tag;
  final String title;
  final String description;
  final String buttonLabel;

  const _PageData({
    required this.icon,
    required this.tag,
    required this.title,
    required this.description,
    required this.buttonLabel,
  });
}

const _pages = [
  _PageData(
    icon: Icons.folder_outlined,
    tag: 'ORGANISE',
    title: 'All your documents in one secure hub',
    description:
        'Browse folders, star what matters, and find any file in seconds — across every department.',
    buttonLabel: 'Next',
  ),
  _PageData(
    icon: Icons.share_outlined,
    tag: 'COLLABORATE',
    title: 'Share, review and approve with your team',
    description:
        'Grant access, handle download and edit requests, and stay on top of every approval from your profile.',
    buttonLabel: 'Get Started',
  ),
];

// ─── OnboardingScreen ─────────────────────────────────────────────────────────
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {

  final PageController _pageCtrl = PageController();
  int _currentPage = 0;

  late final List<AnimationController> _entryCtrl;
  late final List<Animation<double>>   _fadeAnims;
  late final List<Animation<Offset>>   _slideAnims;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    _entryCtrl = List.generate(
      _pages.length,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 480),
      ),
    );

    _fadeAnims = _entryCtrl
        .map((c) => CurvedAnimation(parent: c, curve: Curves.easeOut))
        .toList();

    _slideAnims = _entryCtrl
        .map((c) => Tween<Offset>(
              begin: const Offset(0, 0.12),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: c, curve: Curves.easeOut)))
        .toList();

    _entryCtrl[0].forward();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    for (final c in _entryCtrl) c.dispose();
    super.dispose();
  }

  // ── Mark done + navigate ──────────────────────────────────────────────────
  Future<void> _finishOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kOnboardingDoneKey, true);
    } catch (_) {}

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, __, ___) => const LoginPage(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  void _onNext() {
    if (_currentPage < _pages.length - 1) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOut,
      );
    } else {
      _finishOnboarding();
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: PageView.builder(
        controller: _pageCtrl,
        itemCount: _pages.length,
        onPageChanged: (i) {
          setState(() => _currentPage = i);
          _entryCtrl[i].forward(from: 0);
        },
        itemBuilder: (_, i) => _PageWidget(
          data: _pages[i],
          fadeAnim: _fadeAnims[i],
          slideAnim: _slideAnims[i],
          currentPage: _currentPage,
          totalPages: _pages.length,
          onNext: _onNext,
          onSkip: _finishOnboarding,
        ),
      ),
    );
  }
}

// ─── Single page ──────────────────────────────────────────────────────────────
class _PageWidget extends StatelessWidget {
  final _PageData data;
  final Animation<double> fadeAnim;
  final Animation<Offset> slideAnim;
  final int currentPage;
  final int totalPages;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _PageWidget({
    required this.data,
    required this.fadeAnim,
    required this.slideAnim,
    required this.currentPage,
    required this.totalPages,
    required this.onNext,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Blue hero (top ~55%)
        Expanded(flex: 10, child: _BlueHero(icon: data.icon, onSkip: onSkip)),
        // White content panel (bottom ~45%)
        Expanded(
          flex: 9,
          child: FadeTransition(
            opacity: fadeAnim,
            child: SlideTransition(
              position: slideAnim,
              child: _BottomPanel(
                data: data,
                currentPage: currentPage,
                totalPages: totalPages,
                onNext: onNext,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Blue hero ────────────────────────────────────────────────────────────────
class _BlueHero extends StatelessWidget {
  final IconData icon;
  final VoidCallback onSkip;
  const _BlueHero({required this.icon, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_kPrimary, _kLightBlue, _kDeepBlue],
        ),
      ),
      child: Stack(
        children: [
          // Decorative circles
          _positioned(top: -20, right: -50, child: _circle(220)),
          _positioned(bottom: 20, left: -60, child: _circle(200)),
          _positioned(top: 60, left: 30, child: _circle(130)),

          // Status bar + Skip
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: GestureDetector(
                  onTap: onSkip,
                  child: const Text(
                    'Skip',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ),
          ),

          // Icon card
          Center(child: _IconCard(icon: icon)),
        ],
      ),
    );
  }

  Widget _circle(double size) => Container(
    width: size, height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.07)),
  );

  Widget _positioned({double? top, double? bottom, double? left, double? right, required Widget child}) =>
      Positioned(top: top, bottom: bottom, left: left, right: right, child: child);
}

class _IconCard extends StatelessWidget {
  final IconData icon;
  const _IconCard({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 110, height: 110,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withOpacity(0.18), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 32, offset: const Offset(0, 10))],
      ),
      child: Center(
        child: Container(
          width: 72, height: 72,
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(20)),
          child: Icon(icon, color: Colors.white, size: 36),
        ),
      ),
    );
  }
}

// ─── Bottom white panel ───────────────────────────────────────────────────────
class _BottomPanel extends StatelessWidget {
  final _PageData data;
  final int currentPage;
  final int totalPages;
  final VoidCallback onNext;

  const _BottomPanel({
    required this.data,
    required this.currentPage,
    required this.totalPages,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tag pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: _kPrimary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kPrimary.withOpacity(0.2), width: 1),
            ),
            child: Text(
              data.tag,
              style: const TextStyle(
                color: _kPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Headline
          Text(
            data.title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0D0D2B),
              height: 1.25,
              letterSpacing: -0.3,
            ),
          ),

          const SizedBox(height: 12),

          // Body
          Text(
            data.description,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500, height: 1.55),
          ),

          const Spacer(),

          // Dot indicators
          Row(
            children: List.generate(totalPages, (i) {
              final active = i == currentPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                margin: const EdgeInsets.only(right: 6),
                width: active ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: active ? _kPrimary : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),

          const SizedBox(height: 20),

          // CTA button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: onNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(data.buttonLabel, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}