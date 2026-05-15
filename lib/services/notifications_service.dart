import 'package:dio/dio.dart';
import 'package:digi_sanchika/services/api_client.dart';
import 'package:digi_sanchika/models/app_notification.dart';
import 'package:flutter/foundation.dart';

class NotificationsService {
  Dio get _dio => ApiClient.instance.dio;

  Future<List<AppNotification>> fetchNotifications({int? offset, int? limit}) async {
    final response = await _dio.get(
      '/notifications',
      queryParameters: {
        if (offset != null) 'offset': offset,
        if (limit != null) 'limit': limit,
      },
    );
    final status = response.statusCode ?? 0;
    if (status != 200) {
      if (kDebugMode) {
        print('⚠️ fetchNotifications failed: $status ${response.data}');
      }
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'Failed to load notifications ($status)',
      );
    }

    final data = response.data;
    final items = data is List
        ? data
        : (data['items'] ?? data['notifications'] ?? const []);
    if (items is! List) return const [];

    return items
        .whereType<Map>()
        .map((n) => AppNotification.fromJson(Map<String, dynamic>.from(n)))
        .toList();
  }

  Future<bool> markRead(String id) async {
    final response = await _dio.post('/notifications/$id/read');
    return response.statusCode == 200;
  }

  Future<bool> markAllRead() async {
    final response = await _dio.post('/notifications/read-all');
    return response.statusCode == 200;
  }

  Future<bool> deleteNotification(String id) async {
    final response = await _dio.delete('/notifications/$id');
    return response.statusCode == 200;
  }

  Future<bool> clearAll() async {
    final response = await _dio.delete('/notifications');
    return response.statusCode == 200;
  }
}
