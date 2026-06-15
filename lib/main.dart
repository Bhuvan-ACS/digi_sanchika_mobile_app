import 'dart:async';

import 'package:device_preview/device_preview.dart';
import 'package:digi_sanchika/presentations/Screens/home_page.dart';
import 'package:digi_sanchika/presentations/Screens/login_page.dart';
import 'package:digi_sanchika/presentations/Screens/push_debug_screen.dart';
import 'package:digi_sanchika/services/api_service.dart';
import 'package:digi_sanchika/services/push_notifications_service.dart';
import 'package:digi_sanchika/services/token_storage.dart';
import 'package:digi_sanchika/utils/app_theme.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}

  // Backend sends data-only pushes; display a local notification ourselves.
  await PushNotificationsService.showBackgroundNotification(message);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Show UI immediately; do slow startup work in the background so we don't
  // display a black screen while waiting on network/Firebase initialization.
  PushNotificationsService.instance.attachNavigator(rootNavigatorKey);
  runApp(const DigiSanchikaApp());

  unawaited(_initServices());
}

Future<void> _initServices() async {
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {}

  final firebaseOk = await _tryInitFirebase();
  if (firebaseOk) {
    // Only register background handler when Firebase is actually configured.
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  try {
    await ApiService.initialize(
      baseUrl: dotenv.env['BASE_URL'] ?? dotenv.env['API_BASE_URL'],
    );
  } catch (e) {
    if (kDebugMode) {
      print('ApiService init failed: $e');
    }
  }

  if (kDebugMode) {
    print('Using backend: ${ApiService.currentBaseUrl}');
    print('Connected: ${ApiService.isConnected}');
  }

  // If a session exists, initialize push after the API client is ready so
  // token registration can reach the backend.
  try {
    final accessToken = await TokenStorage.getAccessToken();
    if (accessToken != null && accessToken.trim().isNotEmpty) {
      await PushNotificationsService.instance.initAfterLogin();
    }
  } catch (_) {}
}

Future<bool> _tryInitFirebase() async {
  try {
    await Firebase.initializeApp();
    return true;
  } catch (e) {
    if (kDebugMode) {
      print('Firebase init skipped/failed (missing config?): $e');
    }
    return false;
  }
}

class DigiSanchikaApp extends StatelessWidget {
  const DigiSanchikaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DevicePreview(
          enabled: false,
          tools: const [...DevicePreview.defaultTools],  builder: (context) {
        return MaterialApp(
          title: 'Digi Sanchika',
          useInheritedMediaQuery: true,
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          navigatorKey: rootNavigatorKey,
          home: const _AuthGate(),
          routes: {
            '/login': (context) => const LoginPage(),
            '/home': (context) => const HomePage(),
            '/push-debug': (context) => const PushDebugScreen(),
          },
        );
      }
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  late final Future<bool> _future;

  @override
  void initState() {
    super.initState();
    _future = _hasSession();
  }

  Future<bool> _hasSession() async {
    final token = await TokenStorage.getAccessToken();
    if (token == null || token.trim().isEmpty) return false;

    // Token exists, but may be expired/revoked. Validate once before routing
    // to Home to avoid landing on an unauthenticated app state.
    try {
      await ApiService.initialize();
      final r = await ApiService.testAuthConnection();
      if (r['authenticated'] == true) return true;
    } catch (_) {}

    try {
      await ApiService.clearTokens();
    } catch (_) {}
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _future,
      builder: (context, snapshot) {
        final hasSession = snapshot.data == true;
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return hasSession ? const HomePage() : const LoginPage();
      },
    );
  }
}

// Keep old class name as alias so nothing breaks
typedef MyApp = DigiSanchikaApp;

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
      errorBuilder: (context, error, stackTrace) {
        if (kDebugMode) {
          print('Error loading app logo: $error');
        }
        return Icon(
          Icons.library_books_rounded,
          size: size,
          color: color ?? AppColors.primary,
        );
      },
    );
  }
}
