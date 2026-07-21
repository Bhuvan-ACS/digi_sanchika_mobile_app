import 'dart:async';

import 'package:device_preview/device_preview.dart';
import 'package:digi_sanchika/presentations/Screens/home_page.dart';
import 'package:digi_sanchika/presentations/Screens/login_page.dart';
import 'package:digi_sanchika/presentations/Screens/push_debug_screen.dart';
import 'package:digi_sanchika/screens/onboarding_screen.dart';
import 'package:digi_sanchika/screens/splash_screen.dart';
import 'package:digi_sanchika/services/api_service.dart';
import 'package:digi_sanchika/services/push_notifications_service.dart';
import 'package:digi_sanchika/utils/app_theme.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try { await Firebase.initializeApp(); } catch (_) {}
  await PushNotificationsService.showBackgroundNotification(message);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force status bar to light icons immediately so the splash looks correct
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  ));

  PushNotificationsService.instance.attachNavigator(rootNavigatorKey);

  // Show the app (SplashScreen) immediately; init services in background.
  runApp(const DigiSanchikaApp());

  unawaited(_initServices());
}

Future<void> _initServices() async {
  try { await dotenv.load(fileName: '.env'); } catch (_) {}

  final firebaseOk = await _tryInitFirebase();
  if (firebaseOk) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  try {
    await ApiService.initialize(
      baseUrl: dotenv.env['BASE_URL'] ?? dotenv.env['API_BASE_URL'],
    );
  } catch (e) {
    if (kDebugMode) print('ApiService init failed: $e');
  }

  if (kDebugMode) {
    print('Using backend: ${ApiService.currentBaseUrl}');
    print('Connected: ${ApiService.isConnected}');
  }
}

Future<bool> _tryInitFirebase() async {
  try {
    await Firebase.initializeApp();
    return true;
  } catch (e) {
    if (kDebugMode) print('Firebase init skipped/failed: $e');
    return false;
  }
}

// ─── App root ─────────────────────────────────────────────────────────────────
class DigiSanchikaApp extends StatelessWidget {
  const DigiSanchikaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(360, 690),
      minTextAdapt: true,
      splitScreenMode: true,
      // ⚠️ Use child pattern so SplashScreen is NOT rebuilt on ScreenUtil init
      child: const _AppShell(),
      builder: (context, child) {
        return DevicePreview(
          enabled: false,
          tools: const [...DevicePreview.defaultTools],
          builder: (_) => MaterialApp(
            title: 'Digi Sanchika',
            useInheritedMediaQuery: true,
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            navigatorKey: rootNavigatorKey,
            // ✅ SplashScreen is the one and only entry point
            home: child,
            routes: {
              '/splash':     (_) => const SplashScreen(),
              '/onboarding': (_) => const OnboardingScreen(),
              '/login':      (_) => const LoginPage(),
              '/home':       (_) => const HomePage(),
              '/push-debug': (_) => const PushDebugScreen(),
            },
          ),
        );
      },
    );
  }
}

/// Thin wrapper so the splash widget reference is stable and created once.
class _AppShell extends StatelessWidget {
  const _AppShell();

  @override
  Widget build(BuildContext context) => const SplashScreen();
}

// ─── AppLogo helper (unchanged) ───────────────────────────────────────────────
class AppLogo extends StatelessWidget {
  final double size;
  final Color? color;
  final BoxFit fit;

  const AppLogo({
    super.key,
    this.size = 120.0,
    this.color,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/app-logo.png',
      width: size,
      height: size,
      fit: fit,
      color: color,
      errorBuilder: (_, __, ___) => Icon(
        Icons.library_books_rounded,
        size: size,
        color: color ?? AppColors.primary,
      ),
    );
  }
}

// Keep old alias so nothing breaks
typedef MyApp = DigiSanchikaApp;