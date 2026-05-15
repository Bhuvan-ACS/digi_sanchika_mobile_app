import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:digi_sanchika/models/document.dart';
import 'package:digi_sanchika/presentations/Screens/download_requests_screen.dart';
import 'package:digi_sanchika/presentations/Screens/edit_requests_screen.dart';
import 'package:digi_sanchika/presentations/Screens/folder_screen.dart';
import 'package:digi_sanchika/presentations/Screens/notifications_screen.dart';
import 'package:digi_sanchika/presentations/Screens/document_preview_screen.dart';
import 'package:digi_sanchika/services/folder_service.dart';
import 'package:digi_sanchika/services/my_documents_service.dart';
import 'package:digi_sanchika/services/notifications_service.dart';
import 'package:digi_sanchika/services/push_token_service.dart';
import 'package:digi_sanchika/services/token_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class PushNotificationsService {
  PushNotificationsService._internal();

  static final PushNotificationsService instance =
      PushNotificationsService._internal();

  @pragma('vm:entry-point')
  static Future<void> showBackgroundNotification(RemoteMessage message) async {
    // For data-only pushes, Flutter won't show anything automatically.
    // We build a local notification ourselves.
    try {
      final accessToken = await TokenStorage.getAccessToken();
      if (accessToken == null || accessToken.isEmpty) return;
    } catch (_) {}

    final plugin = FlutterLocalNotificationsPlugin();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const init = InitializationSettings(android: androidInit, iOS: iosInit);

    try {
      await plugin.initialize(settings: init);
    } catch (_) {}

    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        'push_default',
        'Push Notifications',
        description: 'Digi Sanchika push notifications',
        importance: Importance.high,
      );
      final android =
          plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      try {
        await android?.createNotificationChannel(channel);
      } catch (_) {}
    }

    final data = message.data;
    final title = (data['title'] ?? message.notification?.title ?? 'Notification')
        .toString();
    final body =
        (data['message'] ?? data['body'] ?? message.notification?.body ?? '')
            .toString();
    final payload = json.encode(data);

    const androidDetails = AndroidNotificationDetails(
      'push_default',
      'Push Notifications',
      channelDescription: 'Digi Sanchika push notifications',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    try {
      await plugin.show(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload,
      );
    } catch (_) {}
  }

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  final NotificationsService _notificationsService = NotificationsService();

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  GlobalKey<NavigatorState>? _navigatorKey;
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onOpenSub;
  StreamSubscription<String>? _tokenRefreshSub;

  bool _initialized = false;
  String? _currentToken;
  bool _debugSmokeShown = false;

  void attachNavigator(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  Future<void> initAfterLogin() async {
    if (_initialized) return;

    // If Firebase isn't configured (missing google-services.json / options),
    // FirebaseMessaging will throw. In that case, just skip push setup.
    try {
      FirebaseMessaging.instance;
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Push notifications disabled (Firebase not initialized): $e');
      }
      return;
    }

    _initialized = true;

    await _initLocalNotifications();
    await _requestPermissions();

    await _syncToken();

    // Debug-only smoke check so you can verify on a real device that
    // local notifications are configured and showing.
    if (kDebugMode && !_debugSmokeShown) {
      _debugSmokeShown = true;
      try {
        await _local.show(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          title: 'Push ready',
          body: 'FCM + local notifications initialized',
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'push_default',
              'Push Notifications',
              channelDescription: 'Digi Sanchika push notifications',
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(),
          ),
          payload: json.encode(<String, dynamic>{
            'url': '/notifications',
            'category': 'system',
            'type': 'info',
            'title': 'Push ready',
            'message': 'FCM + local notifications initialized',
          }),
        );
      } catch (_) {}
    }
    _tokenRefreshSub = _messaging.onTokenRefresh.listen((token) async {
      _currentToken = token;
      await PushTokenService.registerToken(token: token);
    });

    _onMessageSub = FirebaseMessaging.onMessage.listen((message) async {
      await _showForegroundNotification(message);
    });

    _onOpenSub = FirebaseMessaging.onMessageOpenedApp.listen((message) async {
      await _handleOpen(message);
    });

    try {
      final initial = await _messaging.getInitialMessage();
      if (initial != null) {
        // Delay slightly to allow navigator to settle.
        scheduleMicrotask(() => _handleOpen(initial));
      }
    } catch (_) {}
  }

  Future<void> disposeOnLogout() async {
    final token = _currentToken;
    if (token != null && token.isNotEmpty) {
      await PushTokenService.unregisterToken(token: token);
    }

    await _onMessageSub?.cancel();
    await _onOpenSub?.cancel();
    await _tokenRefreshSub?.cancel();
    _onMessageSub = null;
    _onOpenSub = null;
    _tokenRefreshSub = null;
    _currentToken = null;
    _initialized = false;
  }

  Future<void> _syncToken() async {
    try {
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) return;
      _currentToken = token;
      await PushTokenService.registerToken(token: token);
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ FCM getToken failed: $e');
      }
    }
  }

  Future<void> _requestPermissions() async {
    try {
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        announcement: false,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
      );
    } catch (_) {}

    // On Android 13+ (API 33+), notifications require a runtime permission.
    // firebase_messaging's requestPermission is effectively iOS-only, so we also
    // request via flutter_local_notifications to reliably trigger the prompt.
    if (Platform.isAndroid) {
      try {
        final android =
            _local.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        await android?.requestNotificationsPermission();
      } catch (_) {}
    } else if (Platform.isIOS) {
      try {
        final ios =
            _local.resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>();
        await ios?.requestPermissions(alert: true, badge: true, sound: true);
      } catch (_) {}
    }
  }

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const init = InitializationSettings(android: androidInit, iOS: iosInit);
    await _local.initialize(
      settings: init,
      onDidReceiveNotificationResponse: (resp) async {
        final raw = resp.payload;
        if (raw == null || raw.isEmpty) return;
        try {
          final map = json.decode(raw);
          if (map is Map<String, dynamic>) {
            await _handleDataOpen(map);
          }
        } catch (_) {}
      },
    );

    // Handle the case where the app was launched by tapping a local notification
    // while it was terminated. This is important because our backend sends
    // data-only FCM messages, so we often create local notifications ourselves.
    try {
      final launchDetails = await _local.getNotificationAppLaunchDetails();
      final didLaunch = launchDetails?.didNotificationLaunchApp == true;
      if (didLaunch) {
        final response = launchDetails?.notificationResponse;
        final raw =
            response?.payload ?? (launchDetails as dynamic).payload as String?;
        if (raw != null && raw.isNotEmpty) {
          scheduleMicrotask(() async {
            try {
              final map = json.decode(raw);
              if (map is Map<String, dynamic>) {
                await _handleDataOpen(map);
              }
            } catch (_) {}
          });
        }
      }
    } catch (_) {}

    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        'push_default',
        'Push Notifications',
        description: 'Digi Sanchika push notifications',
        importance: Importance.high,
      );
      final android =
          _local.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(channel);
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    // If user isn't logged in, ignore (prevents showing push on login screen in some edge cases).
    final token = await TokenStorage.getAccessToken();
    if (token == null || token.isEmpty) return;

    final title = message.notification?.title ??
        message.data['title']?.toString() ??
        'Notification';
    final body =
        message.notification?.body ??
        message.data['message']?.toString() ??
        message.data['body']?.toString() ??
        '';

    final payload = json.encode(message.data);

    const androidDetails = AndroidNotificationDetails(
      'push_default',
      'Push Notifications',
      channelDescription: 'Digi Sanchika push notifications',
      importance: Importance.high,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    await _local.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }

  Future<void> _handleOpen(RemoteMessage message) async {
    final token = await TokenStorage.getAccessToken();
    if (token == null || token.isEmpty) {
      // Not logged in yet; safest fallback is to do nothing.
      return;
    }
    await _handleDataOpen(message.data);
  }

  Future<void> _handleDataOpen(Map<String, dynamic> data) async {
    final nav = _navigatorKey?.currentState;
    if (nav == null) return;

    final target = (data['target'] ?? '').toString().toLowerCase().trim();
    final category = (data['category'] ?? '').toString().toLowerCase().trim();
    final entityType =
        (data['entityType'] ?? data['entity_type'] ?? '').toString().toLowerCase().trim();
    final url = (data['url'] ?? '').toString().trim();

    final entityId =
        (data['entityId'] ?? data['entity_id'] ?? '').toString().trim();
    final notificationId = (data['id'] ??
            data['notificationId'] ??
            data['notification_id'] ??
            '')
        .toString()
        .trim();

    String resolvedTarget = target;
    if (resolvedTarget.isEmpty) {
      if (entityType.isNotEmpty) {
        resolvedTarget = entityType;
      } else if (category == 'download') {
        resolvedTarget = 'download_request';
      } else if (url.startsWith('/notifications')) {
        resolvedTarget = 'notifications';
      } else {
        resolvedTarget = 'notifications';
      }
    }

    // Default: open notifications list.
    Future<void> openNotifications() async {
      nav.push(
        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
      );
    }

    try {
      switch (resolvedTarget) {
        case 'notifications':
        case '':
          await openNotifications();
          break;

        case 'download_request':
          nav.push(
            MaterialPageRoute(builder: (_) => const DownloadRequestsScreen()),
          );
          break;

        case 'edit_request':
          nav.push(
            MaterialPageRoute(builder: (_) => const EditRequestsScreen()),
          );
          break;

        case 'folder':
          if (entityId.isEmpty) {
            await openNotifications();
            break;
          }
          final res = await FolderService.getFolderContents(entityId);
          final folderName =
              res['folderName']?.toString() ?? res['folder_name']?.toString() ?? 'Folder';
          nav.push(
            MaterialPageRoute(
              builder: (_) => FolderScreen(
                folderId: entityId,
                folderName: folderName,
              ),
            ),
          );
          break;

        case 'document':
          if (entityId.isEmpty) {
            await openNotifications();
            break;
          }
          final details = await MyDocumentsService.getDocumentDetails(entityId);
          final raw = details['details'];
          Map<String, dynamic> m = {};
          if (raw is Map<String, dynamic>) {
            m = raw;
          }

          final doc = Document(
            id: entityId,
            name: (m['name'] ?? m['file_name'] ?? m['original_filename'] ?? 'Document').toString(),
            type: (m['type'] ?? m['mime_type'] ?? '').toString(),
            size: (m['size'] ?? m['file_size'] ?? m['file_size_bytes'] ?? '').toString(),
            keyword: (m['keywords'] ?? m['keyword'] ?? '').toString(),
            uploadDate: (m['created_at'] ?? m['upload_date'] ?? '').toString(),
            owner: (m['owner']?['name'] ?? m['owner'] ?? 'Unknown').toString(),
            details: (m['details'] ?? '').toString(),
            classification: (m['classification'] ?? 'General').toString(),
            allowDownload: m['allowDownload'] != false,
            isPublishedToLibrary: m['isPublishedToLibrary'] == true || m['is_published_to_library'] == true,
            sharingType: (m['sharingType'] ?? m['sharing_type'] ?? 'private').toString(),
            folder: (m['folder'] ?? m['folder_name'] ?? 'General').toString(),
            folderId: (m['folderId'] ?? m['folder_id'])?.toString(),
            path: (m['path'] ?? m['filename'] ?? '').toString(),
            fileType: (m['fileType'] ?? m['file_type'] ?? '').toString(),
          );

          final fileType = doc.fileType.isNotEmpty
              ? doc.fileType
              : (doc.type.isNotEmpty ? doc.type : 'PDF');

          nav.push(
            MaterialPageRoute(
              builder: (_) => DocumentPreviewScreen(
                document: doc,
                fileType: fileType,
              ),
            ),
          );
          break;

        default:
          await openNotifications();
          break;
      }
    } catch (_) {
      await openNotifications();
    } finally {
      if (notificationId.isNotEmpty) {
        try {
          await _notificationsService.markRead(notificationId);
        } catch (_) {}
      }
    }
  }
}
