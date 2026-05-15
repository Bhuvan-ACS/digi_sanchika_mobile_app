import 'package:dio/dio.dart';
import 'package:digi_sanchika/services/api_client.dart';

enum ShareEntityType { document, folder }

class SharesService {
  Dio get _dio => ApiClient.instance.dio;

  String get _sharesBasePath {
    // Some deployments use `baseUrl = https://host/api` (common in this repo),
    // while others use `baseUrl = https://host`. Make sharing calls work for both.
    final base = ApiClient.instance.baseUrl;
    final uri = Uri.tryParse(base);
    final basePath = (uri?.path ?? '').trim();
    final normalized = basePath.endsWith('/')
        ? basePath.substring(0, basePath.length - 1)
        : basePath;
    return normalized.endsWith('/api') ? '/shares' : '/api/shares';
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  List<dynamic> _asList(dynamic value) {
    if (value is List) return value;
    return const [];
  }

  Future<List<Map<String, dynamic>>> getUsers() async {
    final response = await _dio.get('$_sharesBasePath/users');
    if (response.statusCode != 200) return const [];
    final data = response.data;
    if (data is List) {
      return data
          .map((e) => _asMap(e) ?? const <String, dynamic>{})
          .where((m) => m.isNotEmpty)
          .toList();
    }
    final map = _asMap(data);
    if (map == null) return const [];
    final items = _asList(map['users'] ?? map['items'] ?? map['data']);
    return items
        .map((e) => _asMap(e) ?? const <String, dynamic>{})
        .where((m) => m.isNotEmpty)
        .toList();
  }

  Future<List<Map<String, dynamic>>> listShares({
    required ShareEntityType type,
    required String entityId,
  }) async {
    final path = switch (type) {
      ShareEntityType.document => '$_sharesBasePath/documents/$entityId',
      ShareEntityType.folder => '$_sharesBasePath/folders/$entityId',
    };
    final response = await _dio.get(path);
    if (response.statusCode != 200) return const [];

    final data = response.data;
    if (data is List) {
      return data
          .map((e) => _asMap(e) ?? const <String, dynamic>{})
          .where((m) => m.isNotEmpty)
          .toList();
    }
    final map = _asMap(data);
    if (map == null) return const [];
    final items = _asList(map['items'] ?? map['shares'] ?? map['data']);
    return items
        .map((e) => _asMap(e) ?? const <String, dynamic>{})
        .where((m) => m.isNotEmpty)
        .toList();
  }

  Future<bool> share({
    required ShareEntityType type,
    required String entityId,
    required String sharedWithIdOrEmail,
    bool isEmail = false,
    String permission = 'view',
    int? expiryDays,
    int? expiryHours,
    bool allowDownload = true,
    bool allowEdit = false,
    String? message,
  }) async {
    final path = switch (type) {
      ShareEntityType.document => '$_sharesBasePath/documents/$entityId',
      ShareEntityType.folder => '$_sharesBasePath/folders/$entityId',
    };

    final payload = <String, dynamic>{
      if (isEmail) 'sharedWithEmail': sharedWithIdOrEmail,
      if (!isEmail) 'sharedWithId': sharedWithIdOrEmail,
      'permission': permission,
      if (expiryDays != null) 'expiryDays': expiryDays,
      if (expiryDays != null) 'expiry_days': expiryDays,
      if (expiryHours != null) 'expiryHours': expiryHours,
      if (expiryHours != null) 'expiry_hours': expiryHours,
      'allowDownload': allowDownload,
      'allow_download': allowDownload,
      'allowEdit': allowEdit,
      'allow_edit': allowEdit,
      if (message != null && message.trim().isNotEmpty) 'message': message,
    };

    final response = await _dio.post(path, data: payload);
    return response.statusCode == 200 || response.statusCode == 201;
  }

  Future<bool> updateShare({
    required ShareEntityType type,
    required String shareId,
    bool? allowDownload,
    bool? allowEdit,
  }) async {
    final path = switch (type) {
      ShareEntityType.document => '$_sharesBasePath/documents/$shareId',
      ShareEntityType.folder => '$_sharesBasePath/folders/$shareId',
    };
    final payload = <String, dynamic>{
      if (allowDownload != null) 'allowDownload': allowDownload,
      if (allowDownload != null) 'allow_download': allowDownload,
      if (allowEdit != null) 'allowEdit': allowEdit,
      if (allowEdit != null) 'allow_edit': allowEdit,
    };
    final response = await _dio.patch(path, data: payload);
    return response.statusCode == 200;
  }

  Future<bool> revokeShare({
    required ShareEntityType type,
    required String shareId,
  }) async {
    final path = switch (type) {
      ShareEntityType.document =>
        '$_sharesBasePath/documents/revoke/$shareId',
      ShareEntityType.folder => '$_sharesBasePath/folders/revoke/$shareId',
    };
    final response = await _dio.post(path);
    return response.statusCode == 200 || response.statusCode == 204;
  }
}
