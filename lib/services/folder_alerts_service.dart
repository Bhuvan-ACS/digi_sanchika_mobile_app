import 'package:dio/dio.dart';
import 'package:digi_sanchika/models/folder_alert.dart';
import 'package:digi_sanchika/services/api_client.dart';

class FolderAlertsService {
  Dio get _dio => ApiClient.instance.dio;

  String get _foldersBasePath {
    final base = ApiClient.instance.baseUrl;
    final uri = Uri.tryParse(base);
    final basePath = (uri?.path ?? '').trim();
    final normalized = basePath.endsWith('/')
        ? basePath.substring(0, basePath.length - 1)
        : basePath;
    return normalized.endsWith('/api') ? '/folders' : '/api/folders';
  }

  Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  List<dynamic> _asList(dynamic v) => v is List ? v : const [];

  Future<List<FolderAlert>> listMyAlerts() async {
    final resp = await _dio.get('$_foldersBasePath/my-alerts');
    if (resp.statusCode != 200) return const [];
    final map = _asMap(resp.data);
    if (map == null) return const [];
    final items = _asList(map['alerts'] ?? map['items'] ?? map['data']);
    return items
        .map((e) => _asMap(e))
        .whereType<Map<String, dynamic>>()
        .map(FolderAlert.fromJson)
        .toList();
  }

  Future<FolderAlert?> getAlert(String folderId) async {
    final resp = await _dio.get('$_foldersBasePath/$folderId/alert');
    if (resp.statusCode != 200) return null;
    final map = _asMap(resp.data);
    if (map == null) return null;
    final alertMap = _asMap(map['alert']);
    if (alertMap == null) return null;
    if (alertMap.isEmpty) return null;
    return FolderAlert.fromJson(alertMap);
  }

  Future<FolderAlert?> upsertAlert(
    String folderId, {
    bool? onAdd,
    bool? onDelete,
    bool? onShare,
    bool? onEdit,
  }) async {
    final resp = await _dio.put(
      '$_foldersBasePath/$folderId/alert',
      data: {
        if (onAdd != null) 'onAdd': onAdd,
        if (onDelete != null) 'onDelete': onDelete,
        if (onShare != null) 'onShare': onShare,
        if (onEdit != null) 'onEdit': onEdit,
      },
    );
    if (resp.statusCode != 200) return null;
    final map = _asMap(resp.data);
    final alertMap = map == null ? null : _asMap(map['alert']);
    if (alertMap == null) return null;
    return FolderAlert.fromJson(alertMap);
  }

  Future<bool> deleteAlert(String folderId) async {
    final resp = await _dio.delete('$_foldersBasePath/$folderId/alert');
    return resp.statusCode == 200;
  }
}

