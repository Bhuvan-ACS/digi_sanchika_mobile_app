import 'package:dio/dio.dart';
import 'package:digi_sanchika/services/api_client.dart';
import 'package:digi_sanchika/models/download_request.dart';

class DownloadRequestsService {
  Dio get _dio => ApiClient.instance.dio;

  Future<bool> approve(String id, {String? reviewNotes}) async {
    final response = await _dio.post(
      '/download-requests/$id/approve',
      data: {
        if (reviewNotes != null && reviewNotes.trim().isNotEmpty)
          'reviewNotes': reviewNotes.trim(),
      },
    );
    return response.statusCode == 200;
  }

  Future<Map<String, dynamic>> createRequest({
    String? documentId,
    String? folderId,
    String? reason,
  }) async {
    if ((documentId == null || documentId.trim().isEmpty) &&
        (folderId == null || folderId.trim().isEmpty)) {
      return {'success': false, 'message': 'documentId or folderId is required'};
    }

    final response = await _dio.post(
      '/download-requests',
      data: {
        if (documentId != null && documentId.trim().isNotEmpty) ...{
          'documentId': documentId,
          'document_id': documentId,
        },
        if (folderId != null && folderId.trim().isNotEmpty) ...{
          'folderId': folderId,
          'folder_id': folderId,
        },
        'reason': reason,
      },
    );
    if (response.statusCode == 200) {
      return {'success': true, 'data': response.data};
    }
    return {'success': false, 'message': 'Request failed'};
  }

  Future<List<DownloadRequest>> myRequests() async {
    final response = await _dio.get('/download-requests/my-requests');
    if (response.statusCode == 200) {
      final data = response.data;
      final items = data is List ? data : (data['items'] ?? data['requests'] ?? []);
      return items.map<DownloadRequest>((r) => DownloadRequest.fromJson(r)).toList();
    }
    return [];
  }

  Future<List<DownloadRequest>> pendingApprovals() async {
    final response = await _dio.get('/download-requests/pending-approvals');
    if (response.statusCode == 200) {
      final data = response.data;
      final items = data is List ? data : (data['items'] ?? data['requests'] ?? []);
      return items.map<DownloadRequest>((r) => DownloadRequest.fromJson(r)).toList();
    }
    return [];
  }

  Future<bool> reject(String id, {String? reviewNotes}) async {
    final response = await _dio.post(
      '/download-requests/$id/reject',
      data: {
        if (reviewNotes != null && reviewNotes.trim().isNotEmpty)
          'reviewNotes': reviewNotes.trim(),
      },
    );
    return response.statusCode == 200;
  }

  Future<Map<String, dynamic>> useTokenAuthenticated(
    String id, {
    String? mode,
  }) async {
    final response = await _dio.post(
      '/download-requests/$id/use-token',
      data: {
        if (mode != null && mode.trim().isNotEmpty) 'mode': mode.trim(),
      },
    );
    if (response.statusCode == 200) {
      return {'success': true, 'data': response.data};
    }
    return {'success': false, 'message': 'Token use failed'};
  }

  Future<Map<String, dynamic>> useTokenUnauthenticated(
    String token, {
    String? mode,
  }) async {
    final response = await _dio.get(
      '/download-requests/token/$token',
      queryParameters: {
        if (mode != null && mode.trim().isNotEmpty) 'mode': mode.trim(),
      },
    );
    if (response.statusCode == 200) {
      return {'success': true, 'data': response.data};
    }
    return {'success': false, 'message': 'Token use failed'};
  }

  String? _extractUrl(dynamic data) {
    if (data == null) return null;
    if (data is String) return data;
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final url = map['downloadUrl'] ?? map['download_url'] ?? map['url'];
      return url?.toString();
    }
    return null;
  }

  Future<String?> redeemDownloadUrlByRequestId(String id, {String? mode}) async {
    final result = await useTokenAuthenticated(id, mode: mode);
    if (result['success'] == true) {
      return _extractUrl(result['data']);
    }
    return null;
  }
}
