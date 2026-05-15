import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:digi_sanchika/services/push_token_service.dart';
import 'package:digi_sanchika/services/token_storage.dart';
import 'package:digi_sanchika/services/api_client.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class PushDebugScreen extends StatefulWidget {
  const PushDebugScreen({super.key});

  @override
  State<PushDebugScreen> createState() => _PushDebugScreenState();
}

class _PushDebugScreenState extends State<PushDebugScreen> {
  String? _token;
  NotificationSettings? _settings;
  String? _lastMessageJson;
  String? _status;
  String? _pushStatusJson;
  bool _busy = false;

  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onOpenSub;

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _onMessageSub?.cancel();
    _onOpenSub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    await _initLocal();
    await _refreshAll();

    _onMessageSub = FirebaseMessaging.onMessage.listen((m) {
      _setLastMessage(m, source: 'onMessage (foreground)');
    });
    _onOpenSub = FirebaseMessaging.onMessageOpenedApp.listen((m) {
      _setLastMessage(m, source: 'onMessageOpenedApp (tap)');
    });
  }

  Future<void> _initLocal() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const init = InitializationSettings(android: androidInit, iOS: iosInit);
    try {
      await _local.initialize(settings: init);
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
      try {
        await android?.createNotificationChannel(channel);
      } catch (_) {}
    }
  }

  void _setStatus(String s) {
    if (!mounted) return;
    setState(() => _status = s);
  }

  void _setLastMessage(RemoteMessage m, {required String source}) {
    final data = <String, dynamic>{
      'source': source,
      'messageId': m.messageId,
      'sentTime': m.sentTime?.toIso8601String(),
      'notification': {
        'title': m.notification?.title,
        'body': m.notification?.body,
      },
      'data': m.data,
    };
    final pretty = const JsonEncoder.withIndent('  ').convert(data);
    if (!mounted) return;
    setState(() => _lastMessageJson = pretty);
  }

  Future<void> _refreshAll() async {
    try {
      final t = await _messaging.getToken();
      final s = await _messaging.getNotificationSettings();
      if (!mounted) return;
      setState(() {
        _token = t;
        _settings = s;
      });
    } catch (e) {
      _setStatus('Failed to load token/settings: $e');
    }
  }

  Future<void> _requestPermission() async {
    setState(() => _busy = true);
    try {
      await _messaging.requestPermission(alert: true, badge: true, sound: true);
      if (Platform.isAndroid) {
        final android =
            _local.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        await android?.requestNotificationsPermission();
      } else if (Platform.isIOS) {
        final ios =
            _local.resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>();
        await ios?.requestPermissions(alert: true, badge: true, sound: true);
      }
      await _refreshAll();
      _setStatus('Permission requested.');
    } catch (e) {
      _setStatus('Permission request failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyToken() async {
    final t = _token;
    if (t == null || t.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: t));
    _setStatus('Copied token to clipboard.');
  }

  Future<void> _registerToken() async {
    final t = _token;
    if (t == null || t.isEmpty) {
      _setStatus('No FCM token yet.');
      return;
    }
    setState(() => _busy = true);
    try {
      final access = await TokenStorage.getAccessToken();
      if (access == null || access.isEmpty) {
        _setStatus('Login first (no JWT/access token found).');
        return;
      }
      await PushTokenService.registerToken(token: t);
      _setStatus('Registered token with backend.');
    } catch (e) {
      _setStatus('Register failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unregisterToken() async {
    final t = _token;
    if (t == null || t.isEmpty) {
      _setStatus('No FCM token yet.');
      return;
    }
    setState(() => _busy = true);
    try {
      final access = await TokenStorage.getAccessToken();
      if (access == null || access.isEmpty) {
        _setStatus('Login first (no JWT/access token found).');
        return;
      }
      await PushTokenService.unregisterToken(token: t);
      _setStatus('Unregistered token from backend.');
    } catch (e) {
      _setStatus('Unregister failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadPushStatus() async {
    setState(() => _busy = true);
    try {
      final access = await TokenStorage.getAccessToken();
      if (access == null || access.isEmpty) {
        _setStatus('Login first (no JWT/access token found).');
        return;
      }
      final res = await ApiClient.instance.dio.get('/notifications/push-status');
      final pretty = const JsonEncoder.withIndent('  ').convert(res.data);
      if (!mounted) return;
      setState(() => _pushStatusJson = pretty);
      _setStatus('Loaded push status.');
    } catch (e) {
      _setStatus('Push status failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showLocalTest() async {
    final payload = json.encode(<String, dynamic>{
      'id': 'debug',
      'type': 'info',
      'category': 'system',
      'title': 'Local test notification',
      'message': 'If you see this, local notifications work.',
      'url': '/notifications',
    });
    setState(() => _busy = true);
    try {
      await _local.show(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: 'Local test notification',
        body: 'If you see this, local notifications work.',
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
        payload: payload,
      );
      _setStatus('Displayed local test notification.');
    } catch (e) {
      _setStatus('Local notification failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final token = _token ?? '';
    final settings = _settings;
    final perm = settings?.authorizationStatus.name ?? 'unknown';
    final canCopy = token.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Push Debug'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Permission: $perm'),
          const SizedBox(height: 8),
          Text(
            token.isEmpty ? 'Token: (none yet)' : 'Token:',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (token.isNotEmpty) ...[
            const SizedBox(height: 6),
            SelectableText(
              token,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton(
                onPressed: _busy ? null : _requestPermission,
                child: const Text('Request permission'),
              ),
              ElevatedButton(
                onPressed: _busy ? null : _refreshAll,
                child: const Text('Refresh token'),
              ),
              ElevatedButton(
                onPressed: (!_busy && canCopy) ? _copyToken : null,
                child: const Text('Copy token'),
              ),
              ElevatedButton(
                onPressed: _busy ? null : _showLocalTest,
                child: const Text('Local test'),
              ),
              ElevatedButton(
                onPressed: _busy ? null : _loadPushStatus,
                child: const Text('Push status'),
              ),
              ElevatedButton(
                onPressed: _busy ? null : _registerToken,
                child: const Text('Register (API)'),
              ),
              ElevatedButton(
                onPressed: _busy ? null : _unregisterToken,
                child: const Text('Unregister (API)'),
              ),
            ],
          ),
          if ((_status ?? '').isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              _status!,
              style: const TextStyle(color: Colors.blueGrey),
            ),
          ],
          const SizedBox(height: 20),
          const Text(
            'Backend push-status',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(8),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              _pushStatusJson ?? '(tap “Push status”)',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Last message',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(8),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              _lastMessageJson ?? '(none yet)',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Tip: Use the token above in Firebase Console → Cloud Messaging → Send test message (data-only).',
          ),
        ],
      ),
    );
  }
}
