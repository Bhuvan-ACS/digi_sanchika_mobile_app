import 'package:flutter/foundation.dart';
import 'package:digi_sanchika/services/api_service.dart';

class ProfileService {
  static Future<Map<String, dynamic>> getUserProfile() async {
    try {
      if (!ApiService.isConnected) {
        // Don't block profile loading on a stale connectivity flag.
        await ApiService.checkConnection();
      }

      final response = await ApiService.getProfile();
      if (response['success'] == true && response['data'] != null) {
        return {'success': true, 'data': response['data']};
      }
      return {
        'success': false,
        'message': response['message'] ?? 'Failed to fetch profile',
        'statusCode': response['statusCode'],
      };
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching profile: $e');
      }
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
}
