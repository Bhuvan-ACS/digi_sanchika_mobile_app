import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:digi_sanchika/services/api_client.dart';

class PushTokenService {
  static Dio get _dio => ApiClient.instance.dio;

  static Future<void> registerToken({
    required String token,
  }) async {
    try {
      final payload = await _buildPayload(token: token);
      await _dio.post('/notifications/fcm/register', data: payload);
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Push token register failed: $e');
      }
    }
  }

  static Future<void> unregisterToken({
    required String token,
  }) async {
    try {
      await _dio.delete('/notifications/fcm/unregister', data: {'token': token});
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Push token unregister failed: $e');
      }
    }
  }

  static Future<Map<String, dynamic>> _buildPayload({
    required String token,
  }) async {
    String platform = 'unknown';
    String? deviceLabel;
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        platform = 'android';
        final a = await info.androidInfo;
        final manufacturer = (a.manufacturer).trim();
        final model = (a.model).trim();
        deviceLabel =
            [manufacturer, model].where((s) => s.isNotEmpty).join(' ');
      } else if (Platform.isIOS) {
        platform = 'ios';
        final i = await info.iosInfo;
        final name = (i.name).trim();
        final model = (i.model).trim();
        deviceLabel = [name, model].where((s) => s.isNotEmpty).join(' ');
      }
    } catch (_) {}

    String? appVersion;
    try {
      final pkg = await PackageInfo.fromPlatform();
      appVersion = '${pkg.version}+${pkg.buildNumber}';
    } catch (_) {}

    return {
      'token': token,
      'platform': platform,
      if (deviceLabel != null && deviceLabel.isNotEmpty)
        'deviceLabel': deviceLabel,
      if (appVersion != null && appVersion.isNotEmpty) 'appVersion': appVersion,
    };
  }
}
