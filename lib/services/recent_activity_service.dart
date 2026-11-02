import 'package:dio/dio.dart';
import 'package:digi_sanchika/services/api_client.dart';
import 'package:digi_sanchika/models/recent_activity.dart';
import 'package:flutter/foundation.dart';

class RecentActivityService {
  Dio get _dio => ApiClient.instance.dio;

  /// Most recent actions by the logged-in user, newest first.
  Future<List<RecentActivity>> fetchRecentActivity({int limit = 10}) async {
    final response = await _dio.get(
      '/user/recent-activity',
      // The API returns 500 for a negative limit, so never send one.
      queryParameters: {'limit': limit > 0 ? limit : 10},
    );
    final status = response.statusCode ?? 0;
    if (status != 200) {
      if (kDebugMode) {
        print('⚠️ fetchRecentActivity failed: $status ${response.data}');
      }
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'Failed to load recent activity ($status)',
      );
    }

    final data = response.data;
    final items = data is Map ? (data['activity'] ?? const []) : const [];
    return (items as List)
        .whereType<Map>()
        .map((e) => RecentActivity.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
