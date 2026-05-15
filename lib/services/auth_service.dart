import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:digi_sanchika/services/api_client.dart';
import 'package:digi_sanchika/services/push_notifications_service.dart';
import 'package:digi_sanchika/services/token_storage.dart';

class AuthService {
  static Future<Map<String, dynamic>> login({
    required String employeeId,
    required String password,
  }) async {
    try {
      final dio = ApiClient.instance.dio;

      String? extractMessage(dynamic data) {
        if (data == null) return null;
        if (data is String) {
          final s = data.trim();
          return s.isEmpty ? null : s;
        }
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          final msg =
              map['message'] ??
              map['error'] ??
              map['detail'] ??
              map['msg'] ??
              map['description'];
          final s = msg?.toString().trim();
          return (s == null || s.isEmpty) ? null : s;
        }
        return data.toString();
      }

      final response = await dio.post(
        '/auth/login',
        data: {
          // Be permissive: different backends use different keys.
          'email': employeeId,
          'employeeId': employeeId,
          'employee_id': employeeId,
          'username': employeeId,
          'password': password,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : <String, dynamic>{};

        final access =
            data['accessToken'] ?? data['access_token'] ?? data['token'];
        final refresh =
            data['refreshToken'] ?? data['refresh_token'] ?? data['refresh'];

        if (access is String && access.isNotEmpty) {
          await TokenStorage.saveAccessToken(access);
        }
        if (refresh is String && refresh.isNotEmpty) {
          await TokenStorage.saveRefreshToken(refresh);
        }

        return {
          'success': true,
          'data': data,
          'message': data['message'] ?? 'Login successful',
        };
      }

      if (response.statusCode == 429) {
        final retryAfterHeader = response.headers.value('retry-after');
        final retryAfterSeconds = int.tryParse(retryAfterHeader ?? '');
        return {
          'success': false,
          'message':
              'Too many attempts. Please wait a moment and try again.',
          'statusCode': response.statusCode,
          'retryAfterSeconds': retryAfterSeconds,
          'data': response.data,
        };
      }
      if (response.statusCode == 401) {
        // Avoid exposing raw status codes to users; show a helpful message.
        final m = (extractMessage(response.data) ?? '').trim();
        return {
          'success': false,
          'message': m.isNotEmpty ? m : 'Invalid credentials',
          'statusCode': response.statusCode,
        };
      }
      return {
        'success': false,
        'message':
            extractMessage(response.data) ??
            'Login failed (${response.statusCode})',
        'statusCode': response.statusCode,
        'data': response.data,
      };
    } on DioException catch (e) {
      final response = e.response;
      if (response?.statusCode == 429) {
        final retryAfterHeader = response?.headers.value('retry-after');
        final retryAfterSeconds = int.tryParse(retryAfterHeader ?? '');
        return {
          'success': false,
          'message':
              'Too many attempts. Please wait a moment and try again.',
          'statusCode': response?.statusCode,
          'retryAfterSeconds': retryAfterSeconds,
          'data': response?.data,
        };
      }
      if (response?.statusCode == 401) {
        String? extractMessage(dynamic data) {
          if (data == null) return null;
          if (data is String) {
            final s = data.trim();
            return s.isEmpty ? null : s;
          }
          if (data is Map) {
            final map = Map<String, dynamic>.from(data);
            final msg =
                map['message'] ??
                map['error'] ??
                map['detail'] ??
                map['msg'] ??
                map['description'];
            final s = msg?.toString().trim();
            return (s == null || s.isEmpty) ? null : s;
          }
          return data.toString();
        }

        final m = (extractMessage(response?.data) ?? '').trim();
        return {
          'success': false,
          'message': m.isNotEmpty ? m : 'Invalid credentials',
          'statusCode': response?.statusCode,
        };
      }
      String? extractMessage(dynamic data) {
        if (data == null) return null;
        if (data is String) {
          final s = data.trim();
          return s.isEmpty ? null : s;
        }
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          final msg =
              map['message'] ??
              map['error'] ??
              map['detail'] ??
              map['msg'] ??
              map['description'];
          final s = msg?.toString().trim();
          return (s == null || s.isEmpty) ? null : s;
        }
        return data.toString();
      }

      final msg = extractMessage(response?.data) ?? e.message;
      return {
        'success': false,
        'message': msg ?? 'Login failed',
        'statusCode': response?.statusCode,
        'data': response?.data,
      };
    } catch (e) {
      return {'success': false, 'message': 'Error: $e'};
    }
  }

  static Future<Map<String, dynamic>> logout() async {
    try {
      final dio = ApiClient.instance.dio;
      await dio.post('/auth/logout');
      await PushNotificationsService.instance.disposeOnLogout();
      await ApiClient.instance.clearTokens();
      return {'success': true, 'message': 'Logout successful'};
    } catch (e) {
      try {
        await PushNotificationsService.instance.disposeOnLogout();
      } catch (_) {}
      await ApiClient.instance.clearTokens();
      return {'success': false, 'message': 'Logout failed: $e'};
    }
  }

  static Future<Map<String, dynamic>> getProfile() async {
    try {
      final dio = ApiClient.instance.dio;
      final response = await dio.get('/auth/me');
      if (response.statusCode == 200) {
        final data = response.data;
        return {'success': true, 'data': data};
      }
      return {
        'success': false,
        'message': 'Failed to load profile',
        'statusCode': response.statusCode,
      };
    } catch (e) {
      return {'success': false, 'message': 'Error: $e'};
    }
  }

  static Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    try {
      final dio = ApiClient.instance.dio;
      final response = await dio.post(
        '/auth/change-password',
        data: {
          // New contract (camelCase)
          'currentPassword': currentPassword,
          'newPassword': newPassword,
          // Some backends accept confirm; keep sending for compatibility.
          'confirmPassword': confirmPassword,

          // Legacy contract (snake_case)
          'current_password': currentPassword,
          'new_password': newPassword,
          'confirm_new_password': confirmPassword,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : <String, dynamic>{};
        return {
          'success': true,
          'message': data['message'] ?? 'Password changed successfully',
          'data': data,
        };
      }

      String? messageFrom(dynamic data) {
        if (data == null) return null;
        if (data is String) return data.trim().isEmpty ? null : data.trim();
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          final msg = map['message'] ?? map['error'] ?? map['detail'];
          final s = msg?.toString().trim();
          return (s == null || s.isEmpty) ? null : s;
        }
        return data.toString();
      }

      return {
        'success': false,
        'message':
            messageFrom(response.data) ?? 'Password change failed',
        'statusCode': response.statusCode,
        'data': response.data,
      };
    } on DioException catch (e) {
      final response = e.response;
      String? extract(dynamic data) {
        if (data == null) return null;
        if (data is String) return data.trim().isEmpty ? null : data.trim();
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          final msg = map['message'] ?? map['error'] ?? map['detail'];
          final s = msg?.toString().trim();
          if (s != null && s.isNotEmpty) return s;
          final details = map['details'];
          if (details is List && details.isNotEmpty) {
            return details.map((e) => e.toString()).join('\n');
          }
        }
        return data.toString();
      }

      final msg = extract(response?.data) ?? e.message;
      return {
        'success': false,
        'message': msg ?? 'Password change failed',
        'statusCode': response?.statusCode,
        'data': response?.data,
      };
    } catch (e) {
      return {'success': false, 'message': 'Error: $e'};
    }
  }

  static Future<Map<String, dynamic>> passwordResetRequest(
    String employeeId,
  ) async {
    try {
      final dio = ApiClient.instance.dio;
      final response = await dio.post(
        '/auth/password-reset-request',
        data: {
          // New contract: { email }
          'email': employeeId,
        },
      );
      if (response.statusCode == 200) {
        return {'success': true, 'message': 'Request submitted'};
      }
      return {
        'success': false,
        'message': 'Request failed',
        'statusCode': response.statusCode,
      };
    } catch (e) {
      return {'success': false, 'message': 'Error: $e'};
    }
  }

  static Future<Map<String, dynamic>> passwordRequirements() async {
    try {
      final dio = ApiClient.instance.dio;
      final response = await dio.get('/auth/password-requirements');
      if (response.statusCode == 200) {
        return {'success': true, 'data': response.data};
      }
      return {
        'success': false,
        'message': 'Failed to load requirements',
        'statusCode': response.statusCode,
      };
    } catch (e) {
      if (kDebugMode) {
        print('Password requirements error: $e');
      }
      return {'success': false, 'message': 'Error: $e'};
    }
  }
}
