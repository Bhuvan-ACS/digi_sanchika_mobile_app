import 'package:flutter/foundation.dart';
import 'package:digi_sanchika/services/api_client.dart';
import 'package:digi_sanchika/services/auth_service.dart';
import 'package:digi_sanchika/services/token_storage.dart';

class ApiService {
  static bool _isConnected = false;

  static String get currentBaseUrl => ApiClient.instance.baseUrl;
  static String get baseUrl => ApiClient.instance.baseUrl;
  static bool get isConnected => _isConnected;

  static Future<void> initialize({String? baseUrl}) async {
    await ApiClient.instance.initialize(baseUrl: baseUrl);
    await checkConnection();
  }

  static Future<bool> checkConnection() async {
    try {
      final dio = ApiClient.instance.dio;
      // Use an endpoint guaranteed by backend docs. 401 is still 'connected'.
      final response = await dio.get('/auth/me');
      final status = response.statusCode ?? 0;
      _isConnected = status > 0 && status < 500;
      return _isConnected;
    } catch (e) {
      if (kDebugMode) {
        print('Connection check failed: $e');
      }
      _isConnected = false;
      return false;
    }
  }

  static Future<Map<String, dynamic>> login(
    String employeeId,
    String password,
  ) async {
    return AuthService.login(employeeId: employeeId, password: password);
  }

  static Future<Map<String, dynamic>> logout() async {
    return AuthService.logout();
  }

  static Future<Map<String, dynamic>> changePassword(
    String employeeId,
    String currentPassword,
    String newPassword,
    String confirmPassword,
  ) async {
    return AuthService.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
      confirmPassword: confirmPassword,
    );
  }

  static Future<Map<String, dynamic>> getProfile() async {
    return AuthService.getProfile();
  }

  static Future<Map<String, dynamic>> passwordResetRequest(
    String employeeId,
  ) async {
    return AuthService.passwordResetRequest(employeeId);
  }

  static Future<Map<String, dynamic>> passwordRequirements() async {
    return AuthService.passwordRequirements();
  }

  static Future<String?> getAccessToken() async {
    return TokenStorage.getAccessToken();
  }

  static Future<bool> isLoggedIn() async {
    final token = await TokenStorage.getAccessToken();
    return token != null && token.isNotEmpty;
  }

  static Future<void> clearTokens() async {
    await ApiClient.instance.clearTokens();
  }

  static Future<Map<String, dynamic>> testAuthConnection() async {
    try {
      final dio = ApiClient.instance.dio;
      final response = await dio.get('/auth/me');
      return {
        'success': response.statusCode == 200,
        'statusCode': response.statusCode,
        'authenticated': response.statusCode != 401,
        'message': response.statusCode == 200
            ? 'Authenticated successfully'
            : 'Authentication failed (${response.statusCode})',
      };
    } catch (e) {
      return {'success': false, 'message': 'Connection test failed: $e'};
    }
  }
}
