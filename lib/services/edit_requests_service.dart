import 'package:dio/dio.dart';
import 'package:digi_sanchika/services/api_client.dart';
import 'package:digi_sanchika/models/edit_request.dart';

class EditRequestsService {
  Dio get _dio => ApiClient.instance.dio;

  Future<Map<String, dynamic>> createRequest({
    required String documentId,
    String? reason,
  }) async {
    final response = await _dio.post(
      '/edit-requests',
      data: {'documentId': documentId, 'document_id': documentId, 'reason': reason},
    );
    if (response.statusCode == 200) {
      return {'success': true, 'data': response.data};
    }
    return {'success': false, 'message': 'Request failed'};
  }

  Future<List<EditRequest>> myRequests() async {
    final response = await _dio.get('/edit-requests/my-requests');
    if (response.statusCode == 200) {
      final data = response.data;
      final items = data is List ? data : (data['items'] ?? data['requests'] ?? []);
      return items.map<EditRequest>((r) => EditRequest.fromJson(r)).toList();
    }
    return [];
  }

  Future<List<EditRequest>> pendingApprovals() async {
    final response = await _dio.get('/edit-requests/pending-approvals');
    if (response.statusCode == 200) {
      final data = response.data;
      final items = data is List ? data : (data['items'] ?? data['requests'] ?? []);
      return items.map<EditRequest>((r) => EditRequest.fromJson(r)).toList();
    }
    return [];
  }

  Future<bool> approve(
    String id, {
    String? reviewNotes,
    int? expiresInHours,
  }) async {
    final response = await _dio.post(
      '/edit-requests/$id/approve',
      data: {
        if (reviewNotes != null && reviewNotes.trim().isNotEmpty)
          'reviewNotes': reviewNotes.trim(),
        if (expiresInHours != null) 'expiresInHours': expiresInHours,
        if (expiresInHours != null) 'expires_in_hours': expiresInHours,
      },
    );
    return response.statusCode == 200;
  }

  Future<bool> reject(String id, {String? reviewNotes}) async {
    final response = await _dio.post(
      '/edit-requests/$id/reject',
      data: {
        if (reviewNotes != null && reviewNotes.trim().isNotEmpty)
          'reviewNotes': reviewNotes.trim(),
      },
    );
    return response.statusCode == 200;
  }

  Future<bool> revokeAuthorization(String id) async {
    final response = await _dio.post('/edit-requests/authorization/$id/revoke');
    return response.statusCode == 200;
  }

  Future<Map<String, dynamic>> checkEditAccess(String documentId) async {
    final response = await _dio.get('/editor/$documentId/access');
    if (response.statusCode == 200) {
      return {'success': true, 'data': response.data};
    }
    return {'success': false, 'message': 'Access check failed'};
  }

  Future<Map<String, dynamic>> startEditSession(String documentId) async {
    final response = await _dio.post('/editor/$documentId/session');
    if (response.statusCode == 200) {
      return {'success': true, 'data': response.data};
    }
    return {'success': false, 'message': 'Session start failed'};
  }

  Future<bool> endEditSession(String sessionId) async {
    final response = await _dio.post('/editor/session/$sessionId/end');
    return response.statusCode == 200;
  }
}
