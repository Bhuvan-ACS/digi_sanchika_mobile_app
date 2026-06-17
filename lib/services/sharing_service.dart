import 'dart:io';

import 'package:dio/dio.dart';
import 'package:digi_sanchika/models/folder_members.dart';
import 'package:digi_sanchika/models/group_member.dart';
import 'package:digi_sanchika/models/sharing_models.dart';
import 'package:digi_sanchika/services/api_client.dart';

class SharingService {
  Dio get _dio => ApiClient.instance.dio;

  String get _sharesBasePath {
    final base = ApiClient.instance.baseUrl;
    final uri = Uri.tryParse(base);
    final path = (uri?.path ?? '').replaceAll(RegExp(r'/+$'), '');
    return path.endsWith('/api') ? '/shares' : '/api/shares';
  }

  String get _apiPrefix {
    final base = ApiClient.instance.baseUrl;
    final uri = Uri.tryParse(base);
    final path = (uri?.path ?? '').replaceAll(RegExp(r'/+$'), '');
    return path.endsWith('/api') ? '' : '/api';
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  List<dynamic> _asList(dynamic value) => value is List ? value : const [];

  Future<List<Map<String, dynamic>>> listUsers() async {
    final response = await _dio.get('$_sharesBasePath/users');
    final map = _asMap(response.data);
    final items = response.data is List
        ? response.data as List
        : _asList(map?['users'] ?? map?['items'] ?? map?['data']);
    return items
        .map(_asMap)
        .whereType<Map<String, dynamic>>()
        .where((u) => (u['id'] ?? u['user_id'] ?? '').toString().isNotEmpty)
        .toList();
  }

  Future<SharedWithMeResult> sharedWithMe() async {
    final response = await _dio.get('$_sharesBasePath/shared-with-me');
    final map = _asMap(response.data) ?? const <String, dynamic>{};
    return SharedWithMeResult.fromJson(map);
  }

  Future<SharedWithMeResult> sharedByMe() async {
    final response = await _dio.get('$_sharesBasePath/shared-by-me');
    final map = _asMap(response.data) ?? const <String, dynamic>{};
    return SharedWithMeResult.fromJson(map);
  }

  Future<ShareGrantResult> listItemShares({
    required ShareEntityType type,
    required String entityId,
  }) async {
    final path = switch (type) {
      ShareEntityType.document => '$_sharesBasePath/documents/$entityId',
      ShareEntityType.folder => '$_sharesBasePath/folders/$entityId',
    };
    final response = await _dio.get(path);
    final data = response.data;
    if (data is List) {
      return ShareGrantResult(
        directShares: data
            .map(_asMap)
            .whereType<Map<String, dynamic>>()
            .map((e) => ShareGrant.direct(e, entityType: type))
            .where((e) => e.id.isNotEmpty)
            .toList(),
        groupShares: const [],
      );
    }
    final map = _asMap(data) ?? const <String, dynamic>{};
    final direct = _asList(map['shares'] ?? map['items'] ?? map['data'])
        .map(_asMap)
        .whereType<Map<String, dynamic>>()
        .map((e) => ShareGrant.direct(e, entityType: type))
        .where((e) => e.id.isNotEmpty)
        .toList();
    final groups = _asList(map['groupShares'] ?? map['group_shares'])
        .map(_asMap)
        .whereType<Map<String, dynamic>>()
        .map((e) => ShareGrant.group(e, entityType: type))
        .where((e) => e.id.isNotEmpty)
        .toList();
    return ShareGrantResult(directShares: direct, groupShares: groups);
  }

  Future<EffectiveAccess?> getEffectiveAccess({
    required ShareEntityType type,
    required String entityId,
  }) async {
    final path = switch (type) {
      ShareEntityType.document => '$_apiPrefix/access/documents/$entityId',
      ShareEntityType.folder => '$_apiPrefix/access/folders/$entityId',
    };
    final response = await _dio.get(path);
    if (response.statusCode != 200) return null;
    final map = _asMap(response.data);
    final access = _asMap(map?['effectiveAccess'] ?? map?['effective_access']);
    return EffectiveAccess.fromJson(access);
  }

  Future<bool> shareWithUser({
    required ShareEntityType type,
    required String entityId,
    required String sharedWithIdOrEmail,
    required bool isEmail,
    required String permission,
    required bool allowDownload,
    required bool allowEdit,
    required String collaborationLevel,
    int? expiryHours,
    int? expiryDays,
    bool noExpiry = false,
    String? message,
  }) async {
    final path = switch (type) {
      ShareEntityType.document => '$_sharesBasePath/documents/$entityId',
      ShareEntityType.folder => '$_sharesBasePath/folders/$entityId',
    };
    final response = await _dio.post(path, data: {
      if (isEmail) 'sharedWithEmail': sharedWithIdOrEmail,
      if (!isEmail) 'sharedWithId': sharedWithIdOrEmail,
      'permission': permission,
      'allowDownload': allowDownload,
      'allowEdit': allowEdit,
      'collaborationLevel': collaborationLevel,
      if (expiryHours != null) 'expiryHours': expiryHours,
      if (expiryDays != null) 'expiryDays': expiryDays,
      if (noExpiry) 'noExpiry': true,
      if (message != null && message.trim().isNotEmpty) 'message': message.trim(),
    });
    return response.statusCode == 200 || response.statusCode == 201;
  }

  Future<bool> shareWithGroup({
    required ShareEntityType type,
    required String entityId,
    required String groupId,
    required String permission,
    required bool allowDownload,
    required bool allowEdit,
    required String collaborationLevel,
    int? expiryHours,
    int? expiryDays,
    bool noExpiry = false,
  }) async {
    final path = switch (type) {
      ShareEntityType.document => '$_sharesBasePath/documents/$entityId/group',
      ShareEntityType.folder => '$_sharesBasePath/folders/$entityId/group',
    };
    final response = await _dio.post(path, data: {
      'groupId': groupId,
      'permission': permission,
      'allowDownload': allowDownload,
      'allowEdit': allowEdit,
      'collaborationLevel': collaborationLevel,
      if (expiryHours != null) 'expiryHours': expiryHours,
      if (expiryDays != null) 'expiryDays': expiryDays,
      if (noExpiry) 'noExpiry': true,
    });
    return response.statusCode == 200 || response.statusCode == 201;
  }

  Future<bool> updateShare({
    required ShareGrant grant,
    String? permission,
    bool? allowDownload,
    bool? allowEdit,
    String? collaborationLevel,
    int? expiryHours,
    int? expiryDays,
    bool noExpiry = false,
  }) async {
    final path = switch ((grant.entityType, grant.isGroup)) {
      (ShareEntityType.document, false) => '$_sharesBasePath/documents/${grant.id}',
      (ShareEntityType.folder, false) => '$_sharesBasePath/folders/${grant.id}',
      (ShareEntityType.document, true) =>
        '$_sharesBasePath/documents/group/${grant.id}',
      (ShareEntityType.folder, true) =>
        '$_sharesBasePath/folders/group/${grant.id}',
    };
    final payload = {
      if (permission != null) 'permission': permission,
      if (allowDownload != null) 'allowDownload': allowDownload,
      if (allowEdit != null) 'allowEdit': allowEdit,
      if (collaborationLevel != null) 'collaborationLevel': collaborationLevel,
      if (expiryHours != null) 'expiryHours': expiryHours,
      if (expiryDays != null) 'expiryDays': expiryDays,
      if (noExpiry) 'noExpiry': true,
    };
    if (payload.isEmpty) return false;
    final response = await _dio.patch(path, data: payload);
    return response.statusCode == 200;
  }

  Future<bool> revokeShare(ShareGrant grant) async {
    final path = switch ((grant.entityType, grant.isGroup)) {
      (ShareEntityType.document, false) =>
        '$_sharesBasePath/documents/revoke/${grant.id}',
      (ShareEntityType.folder, false) =>
        '$_sharesBasePath/folders/revoke/${grant.id}',
      (ShareEntityType.document, true) =>
        '$_sharesBasePath/documents/group/${grant.id}/revoke',
      (ShareEntityType.folder, true) =>
        '$_sharesBasePath/folders/group/${grant.id}/revoke',
    };
    final response = await _dio.post(path);
    return response.statusCode == 200 || response.statusCode == 204;
  }

  Future<List<GroupMember>> listGroupShareMembers({
    required ShareGrant grant,
  }) async {
    if (!grant.isGroup) return const [];
    final path = switch (grant.entityType) {
      ShareEntityType.document =>
        '$_sharesBasePath/documents/group/${grant.id}/members',
      ShareEntityType.folder =>
        '$_sharesBasePath/folders/group/${grant.id}/members',
    };
    final response = await _dio.get(path);
    final map = _asMap(response.data);
    final items = _asList(map?['members'] ?? map?['items'] ?? map?['data']);
    return items
        .map(_asMap)
        .whereType<Map<String, dynamic>>()
        .map(GroupMember.fromJson)
        .toList();
  }

  Future<bool> setGroupMemberOverride({
    required ShareGrant grant,
    required String userId,
    required bool accessEnabled,
    String? permission,
    bool? allowDownload,
    bool? allowEdit,
    String? collaborationLevel,
    int? expiryHours,
    int? expiryDays,
    bool inheritExpiry = false,
  }) async {
    if (!grant.isGroup) return false;
    final path = switch (grant.entityType) {
      ShareEntityType.document =>
        '$_sharesBasePath/documents/group/${grant.id}/members/$userId',
      ShareEntityType.folder =>
        '$_sharesBasePath/folders/group/${grant.id}/members/$userId',
    };
    final response = await _dio.put(path, data: {
      'accessEnabled': accessEnabled,
      if (permission != null) 'permission': permission,
      if (allowDownload != null) 'allowDownload': allowDownload,
      if (allowEdit != null) 'allowEdit': allowEdit,
      if (collaborationLevel != null) 'collaborationLevel': collaborationLevel,
      if (expiryHours != null) 'expiryHours': expiryHours,
      if (expiryDays != null) 'expiryDays': expiryDays,
      if (inheritExpiry) 'expiresAt': null,
    });
    return response.statusCode == 200 || response.statusCode == 201;
  }

  Future<bool> removeGroupMemberOverride({
    required ShareGrant grant,
    required String userId,
  }) async {
    if (!grant.isGroup) return false;
    final path = switch (grant.entityType) {
      ShareEntityType.document =>
        '$_sharesBasePath/documents/group/${grant.id}/members/$userId',
      ShareEntityType.folder =>
        '$_sharesBasePath/folders/group/${grant.id}/members/$userId',
    };
    final response = await _dio.delete(path);
    return response.statusCode == 200 || response.statusCode == 204;
  }

  Future<List<PublicLinkGrant>> listPublicLinks({
    required ShareEntityType type,
    required String entityId,
  }) async {
    final entityType = type == ShareEntityType.document ? 'document' : 'folder';
    final response = await _dio.get(
      '$_apiPrefix/public-links',
      queryParameters: {'entityType': entityType, 'entityId': entityId},
    );
    final map = _asMap(response.data);
    final items = _asList(map?['links'] ?? map?['items'] ?? map?['data']);
    return items
        .map(_asMap)
        .whereType<Map<String, dynamic>>()
        .map(PublicLinkGrant.fromJson)
        .where((e) => e.id.isNotEmpty)
        .toList();
  }

  Future<PublicLinkGrant?> createPublicLink({
    required ShareEntityType type,
    required String entityId,
    required bool allowView,
    required bool allowDownload,
    int? expiryHours,
    int? expiryDays,
    bool noExpiry = false,
  }) async {
    final response = await _dio.post('$_apiPrefix/public-links', data: {
      'entityType': type == ShareEntityType.document ? 'document' : 'folder',
      'entityId': entityId,
      'allowView': allowView,
      'allowDownload': allowDownload,
      if (expiryHours != null) 'expiryHours': expiryHours,
      if (expiryDays != null) 'expiryDays': expiryDays,
      if (noExpiry) 'noExpiry': true,
    });
    if (response.statusCode != 200 && response.statusCode != 201) return null;
    final map = _asMap(response.data);
    return map == null ? null : PublicLinkGrant.fromJson(map);
  }

  Future<bool> updatePublicLink({
    required PublicLinkGrant link,
    bool? allowView,
    bool? allowDownload,
    int? expiryHours,
    int? expiryDays,
    bool noExpiry = false,
  }) async {
    final response = await _dio.patch('$_apiPrefix/public-links/${link.id}', data: {
      if (allowView != null) 'allowView': allowView,
      if (allowDownload != null) 'allowDownload': allowDownload,
      if (expiryHours != null) 'expiryHours': expiryHours,
      if (expiryDays != null) 'expiryDays': expiryDays,
      if (noExpiry) 'noExpiry': true,
    });
    return response.statusCode == 200;
  }

  Future<bool> revokePublicLink(String linkId) async {
    final response = await _dio.post('$_apiPrefix/public-links/$linkId/revoke');
    return response.statusCode == 200 || response.statusCode == 204;
  }

  Future<Map<String, dynamic>> uploadIntoSharedFolder({
    required String folderId,
    required File file,
    String classification = 'internal',
    String? description,
  }) async {
    final fileName = file.path.split(Platform.pathSeparator).last;
    final bytes = await file.readAsBytes();
    final mimeType = _guessMime(fileName);
    final presign = await _dio.post('$_sharesBasePath/folders/$folderId/upload-url', data: {
      'fileName': fileName,
      'mimeType': mimeType,
      'fileSize': bytes.length,
      'classification': classification,
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
    });
    if (presign.statusCode != 200 && presign.statusCode != 201) {
      return {'success': false, 'message': 'Upload URL request failed'};
    }
    final data = _asMap(presign.data) ?? const <String, dynamic>{};
    final uploadUrl = (data['uploadUrl'] ?? data['url'])?.toString();
    final documentId = (data['documentId'] ?? data['document_id'] ?? data['id'])
        ?.toString();
    if (uploadUrl == null || uploadUrl.isEmpty || documentId == null) {
      return {'success': false, 'message': 'Upload response was incomplete'};
    }

    final raw = Dio(BaseOptions(validateStatus: (s) => s != null && s < 600));
    final put = await raw.put(
      uploadUrl,
      data: bytes,
      options: Options(headers: {
        'Content-Type': mimeType,
        'Content-Length': bytes.length.toString(),
      }),
    );
    if (put.statusCode != 200 && put.statusCode != 201 && put.statusCode != 204) {
      return {'success': false, 'message': 'File upload failed'};
    }

    final confirm = await _dio.post(
      '$_apiPrefix/documents/$documentId/confirm-upload',
      data: {'fileSize': bytes.length},
    );
    return {
      'success': confirm.statusCode == 200 || confirm.statusCode == 201,
      'documentId': documentId,
      'data': confirm.data,
    };
  }

  /// GET /api/shares/folders/:folderId/members
  ///
  /// Returns every user who currently has access to [folderId], together with
  /// how that access was granted (direct vs. group).
  ///
  /// Throws a [DioException] on network errors; re-throws a [StateError] if
  /// the server returns a non-200 status.
  Future<FolderMembersResponse> getFolderMembers(String folderId) async {
    assert(folderId.isNotEmpty, 'folderId must not be empty');
    final response = await _dio.get(
      '$_sharesBasePath/folders/$folderId/members',
    );
    if (response.statusCode != 200) {
      throw StateError(
        'getFolderMembers: unexpected status ${response.statusCode}',
      );
    }
    final map = _asMap(response.data) ?? const <String, dynamic>{};
    return FolderMembersResponse.fromJson(map);
  }

  String _guessMime(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return switch (ext) {
      'pdf' => 'application/pdf',
      'doc' => 'application/msword',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt' => 'application/vnd.ms-powerpoint',
      'pptx' =>
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'txt' => 'text/plain',
      'csv' => 'text/csv',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      _ => 'application/octet-stream',
    };
  }
}
