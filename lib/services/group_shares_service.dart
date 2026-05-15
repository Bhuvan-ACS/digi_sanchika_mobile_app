import 'package:dio/dio.dart';
import 'package:digi_sanchika/services/api_client.dart';

class GroupSharesService {
  Dio get _dio => ApiClient.instance.dio;

  String get _sharesBasePath {
    final base = ApiClient.instance.baseUrl;
    final uri = Uri.tryParse(base);
    final basePath = (uri?.path ?? '').trim();
    final normalized = basePath.endsWith('/')
        ? basePath.substring(0, basePath.length - 1)
        : basePath;
    return normalized.endsWith('/api') ? '/shares' : '/api/shares';
  }

  Future<Map<String, dynamic>?> shareDocumentWithGroup({
    required String documentId,
    required String groupId,
    String permission = 'view',
    bool allowDownload = false,
    bool allowEdit = false,
    bool? noExpiry,
    int? expiryHours,
    int? expiryDays,
  }) async {
    final resp = await _dio.post(
      '$_sharesBasePath/documents/$documentId/group',
      data: {
        'groupId': groupId,
        'permission': permission,
        'allowDownload': allowDownload,
        'allowEdit': allowEdit,
        if (noExpiry == true) 'noExpiry': true,
        if (expiryHours != null) 'expiryHours': expiryHours,
        if (expiryDays != null) 'expiryDays': expiryDays,
      },
    );
    if (resp.statusCode != 201 && resp.statusCode != 200) return null;
    if (resp.data is Map) return Map<String, dynamic>.from(resp.data as Map);
    return null;
  }

  Future<bool> updateDocumentGroupShare({
    required String groupShareId,
    String? permission,
    bool? allowDownload,
    bool? allowEdit,
  }) async {
    final resp = await _dio.patch(
      '$_sharesBasePath/documents/group/$groupShareId',
      data: {
        if (permission != null) 'permission': permission,
        if (allowDownload != null) 'allowDownload': allowDownload,
        if (allowEdit != null) 'allowEdit': allowEdit,
      },
    );
    return resp.statusCode == 200;
  }

  Future<bool> revokeDocumentGroupShare(String groupShareId) async {
    final resp =
        await _dio.post('$_sharesBasePath/documents/group/$groupShareId/revoke');
    return resp.statusCode == 200;
  }

  Future<bool> setDocumentOverride({
    required String groupShareId,
    required String userId,
    String? permission,
    bool? allowDownload,
    bool? allowEdit,
  }) async {
    final resp = await _dio.post(
      '$_sharesBasePath/documents/group/$groupShareId/override',
      data: {
        'userId': userId,
        if (permission != null) 'permission': permission,
        if (allowDownload != null) 'allowDownload': allowDownload,
        if (allowEdit != null) 'allowEdit': allowEdit,
      },
    );
    return resp.statusCode == 200;
  }

  Future<bool> removeDocumentOverride({
    required String groupShareId,
    required String userId,
  }) async {
    final resp = await _dio.delete(
      '$_sharesBasePath/documents/group/$groupShareId/override/$userId',
    );
    return resp.statusCode == 200;
  }

  Future<Map<String, dynamic>?> shareFolderWithGroup({
    required String folderId,
    required String groupId,
    String permission = 'view',
    bool allowDownload = false,
    bool allowEdit = false,
    bool? noExpiry,
    int? expiryHours,
    int? expiryDays,
  }) async {
    final resp = await _dio.post(
      '$_sharesBasePath/folders/$folderId/group',
      data: {
        'groupId': groupId,
        'permission': permission,
        'allowDownload': allowDownload,
        'allowEdit': allowEdit,
        if (noExpiry == true) 'noExpiry': true,
        if (expiryHours != null) 'expiryHours': expiryHours,
        if (expiryDays != null) 'expiryDays': expiryDays,
      },
    );
    if (resp.statusCode != 201 && resp.statusCode != 200) return null;
    if (resp.data is Map) return Map<String, dynamic>.from(resp.data as Map);
    return null;
  }

  Future<bool> updateFolderGroupShare({
    required String groupShareId,
    String? permission,
    bool? allowDownload,
    bool? allowEdit,
  }) async {
    final resp = await _dio.patch(
      '$_sharesBasePath/folders/group/$groupShareId',
      data: {
        if (permission != null) 'permission': permission,
        if (allowDownload != null) 'allowDownload': allowDownload,
        if (allowEdit != null) 'allowEdit': allowEdit,
      },
    );
    return resp.statusCode == 200;
  }

  Future<bool> revokeFolderGroupShare(String groupShareId) async {
    final resp =
        await _dio.post('$_sharesBasePath/folders/group/$groupShareId/revoke');
    return resp.statusCode == 200;
  }

  Future<bool> setFolderOverride({
    required String groupShareId,
    required String userId,
    String? permission,
    bool? allowDownload,
    bool? allowEdit,
  }) async {
    final resp = await _dio.post(
      '$_sharesBasePath/folders/group/$groupShareId/override',
      data: {
        'userId': userId,
        if (permission != null) 'permission': permission,
        if (allowDownload != null) 'allowDownload': allowDownload,
        if (allowEdit != null) 'allowEdit': allowEdit,
      },
    );
    return resp.statusCode == 200;
  }

  Future<bool> removeFolderOverride({
    required String groupShareId,
    required String userId,
  }) async {
    final resp = await _dio.delete(
      '$_sharesBasePath/folders/group/$groupShareId/override/$userId',
    );
    return resp.statusCode == 200;
  }
}

