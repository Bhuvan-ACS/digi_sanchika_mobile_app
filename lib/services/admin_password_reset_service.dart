import 'package:dio/dio.dart';
import 'package:digi_sanchika/models/password_reset_request.dart';
import 'package:digi_sanchika/services/api_client.dart';

class AdminPasswordResetService {
  Dio get _dio => ApiClient.instance.dio;

  Future<({List<PasswordResetRequest> requests, int total})> listRequests({
    String status = 'pending',
    int limit = 50,
    int offset = 0,
  }) async {
    final resp = await _dio.get(
      '/admin/password-reset-requests',
      queryParameters: {
        'status': status,
        'limit': limit,
        'offset': offset,
      },
    );
    if (resp.statusCode != 200) {
      return (requests: const <PasswordResetRequest>[], total: 0);
    }
    final data = resp.data;
    final map = data is Map ? Map<String, dynamic>.from(data) : null;
    final raw = map?['requests'] ?? map?['items'] ?? const [];
    final totalRaw = map?['total'] ?? raw is List ? raw.length : 0;
    final total = totalRaw is int ? totalRaw : int.tryParse(totalRaw.toString()) ?? 0;
    if (raw is! List) {
      return (requests: const <PasswordResetRequest>[], total: total);
    }
    final items = raw
        .whereType<dynamic>()
        .map((e) => e is Map ? PasswordResetRequest.fromJson(Map<String, dynamic>.from(e)) : null)
        .whereType<PasswordResetRequest>()
        .where((r) => r.id.isNotEmpty)
        .toList();
    return (requests: items, total: total);
  }

  Future<Map<String, dynamic>> resetFromRequest(
    String requestId, {
    required String newPassword,
    bool forceChangeOnLogin = true,
  }) async {
    final resp = await _dio.post(
      '/admin/password-reset-requests/$requestId/reset',
      data: {
        'newPassword': newPassword,
        'forceChangeOnLogin': forceChangeOnLogin,
      },
      options: Options(validateStatus: (s) => s != null && s < 500),
    );

    if (resp.statusCode == 200) {
      return {'success': true, 'data': resp.data};
    }

    final msg = _extractMessage(resp.data) ?? 'Reset failed (${resp.statusCode})';
    return {'success': false, 'message': msg, 'statusCode': resp.statusCode, 'data': resp.data};
  }

  Future<Map<String, dynamic>> rejectRequest(
    String requestId, {
    String? note,
  }) async {
    final resp = await _dio.post(
      '/admin/password-reset-requests/$requestId/reject',
      data: {
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
      options: Options(validateStatus: (s) => s != null && s < 500),
    );
    if (resp.statusCode == 200) {
      return {'success': true, 'data': resp.data};
    }
    final msg = _extractMessage(resp.data) ?? 'Reject failed (${resp.statusCode})';
    return {'success': false, 'message': msg, 'statusCode': resp.statusCode, 'data': resp.data};
  }

  String? _extractMessage(dynamic data) {
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
}
