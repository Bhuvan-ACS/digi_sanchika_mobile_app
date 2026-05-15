import 'package:dio/dio.dart';
import 'package:digi_sanchika/models/version_info.dart';
import 'package:digi_sanchika/models/version_view_asset.dart';
import 'package:digi_sanchika/services/api_client.dart';

class VersionsService {
  Dio get _dio => ApiClient.instance.dio;

  String _versionsPrefix() {
    final base = ApiClient.instance.baseUrl.trim();
    final uri = Uri.tryParse(base);
    if (uri == null) return '/api/versions';
    final path = uri.path.replaceAll(RegExp(r'/+$'), '');
    // Many deployments use baseUrl ending with `/api`.
    if (path.toLowerCase().endsWith('/api')) return '/versions';
    return '/api/versions';
  }

  Dio _rawDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 60),
        followRedirects: true,
        validateStatus: (s) => s != null && s < 600,
      ),
    );
  }

  String _extractFilenameFromHeaders(Response response) {
    final cd = response.headers.value('content-disposition');
    if (cd == null) return 'document';
    final match = RegExp(r'filename=\"?([^\";]+)\"?').firstMatch(cd);
    return match?.group(1) ?? 'document';
  }

  Future<List<VersionInfo>> listVersions(String documentId) async {
    final p = _versionsPrefix();
    final resp = await _dio.get('$p/$documentId');
    if (resp.statusCode == 200) {
      final data = resp.data;
      final versions = data is Map
          ? (data['versions'] is List ? data['versions'] as List : <dynamic>[])
          : (data is List ? data : <dynamic>[]);
      return versions
          .whereType<dynamic>()
          .map((v) => v is Map
              ? VersionInfo.fromJson(Map<String, dynamic>.from(v))
              : VersionInfo.fromJson(<String, dynamic>{'version': v.toString()}))
          .toList();
    }
    return [];
  }

  Future<VersionInfo?> getVersion(
    String documentId,
    String version,
  ) async {
    final p = _versionsPrefix();
    final resp = await _dio.get('$p/$documentId/$version');
    if (resp.statusCode == 200) {
      final data = resp.data;
      final map = data is Map
          ? (data['version'] is Map ? data['version'] : data)
          : null;
      if (map is Map) {
        return VersionInfo.fromJson(Map<String, dynamic>.from(map));
      }
    }
    return null;
  }

  Future<VersionViewAsset?> getViewAsset({
    required String documentId,
    required String version,
    bool original = false,
  }) async {
    final p = _versionsPrefix();
    final resp = await _dio.get(
      '$p/$documentId/$version/view-url',
      queryParameters: {'original': original},
    );
    if (resp.statusCode == 200) {
      final data = resp.data is Map
          ? Map<String, dynamic>.from(resp.data as Map)
          : <String, dynamic>{'url': resp.data?.toString()};
      final url = data['url']?.toString() ?? '';
      if (url.isEmpty) return null;
      return VersionViewAsset.fromJson(data);
    }
    return null;
  }

  Future<Map<String, dynamic>> downloadVersionBytes({
    required String documentId,
    required String version,
    bool original = false,
  }) async {
    try {
      final asset = await getViewAsset(
        documentId: documentId,
        version: version,
        original: original,
      );
      if (asset == null || asset.url.isEmpty) {
        return {'success': false, 'error': 'Version view URL missing'};
      }

      if (asset.conversionStatus == 'pending' ||
          asset.conversionStatus == 'converting') {
        return {
          'success': false,
          'conversionStatus': asset.conversionStatus,
          'error': 'Version is still converting',
        };
      }
      if (asset.conversionStatus == 'failed') {
        return {
          'success': false,
          'conversionStatus': asset.conversionStatus,
          'error': asset.conversionError ?? 'Conversion failed',
        };
      }

      final raw = _rawDio();
      final fileResp = await raw.get(
        asset.url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Accept': '*/*'},
        ),
      );
      if (fileResp.statusCode == 200) {
        final bytes = fileResp.data;
        final list = bytes is List<int>
            ? bytes
            : (bytes is List ? bytes.cast<int>() : <int>[]);
        return {
          'success': true,
          'bytes': list,
          'filename': _extractFilenameFromHeaders(fileResp),
          'mimeType': fileResp.headers.value('content-type') ?? asset.mimeType,
          'isPdf': asset.isPdf,
        };
      }
      return {
        'success': false,
        'error': 'Download failed (${fileResp.statusCode})',
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<VersionInfo?> snapshot(String documentId, {String? changeNote}) async {
    final p = _versionsPrefix();
    final resp = await _dio.post(
      '$p/$documentId/snapshot',
      data: changeNote != null && changeNote.trim().isNotEmpty
          ? {'changeNote': changeNote.trim()}
          : <String, dynamic>{},
    );
    if (resp.statusCode == 200) {
      final data = resp.data;
      final map = data is Map ? data['snapshot'] ?? data['version'] ?? data : null;
      if (map is Map) {
        return VersionInfo.fromJson(Map<String, dynamic>.from(map));
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> compareText({
    required String documentId,
    required String versionFrom,
    required String versionTo,
  }) async {
    final p = _versionsPrefix();
    final resp = await _dio.get(
      '$p/$documentId/compare/$versionFrom/$versionTo',
    );
    if (resp.statusCode == 200) {
      return resp.data is Map ? Map<String, dynamic>.from(resp.data as Map) : {'diff': resp.data};
    }
    return null;
  }

  Future<Map<String, dynamic>?> comparePdf({
    required String documentId,
    required String versionFrom,
    required String versionTo,
  }) async {
    final p = _versionsPrefix();
    final resp = await _dio.get(
      '$p/$documentId/compare-pdf/$versionFrom/$versionTo',
    );
    if (resp.statusCode == 200) {
      return resp.data is Map ? Map<String, dynamic>.from(resp.data as Map) : null;
    }
    return null;
  }

  Future<Map<String, dynamic>> restore({
    required String documentId,
    required String sourceVersion,
    String? reason,
  }) async {
    final p = _versionsPrefix();
    final resp = await _dio.post(
      '$p/$documentId/restore',
      data: {
        'sourceVersion': sourceVersion,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
    if (resp.statusCode == 200) {
      return resp.data is Map ? Map<String, dynamic>.from(resp.data as Map) : {'success': true};
    }
    return {
      'success': false,
      'message': 'Restore failed (${resp.statusCode})',
      'data': resp.data,
    };
  }

  // Comments (stubbed backend)
  Future<List<dynamic>> listComments({
    required String documentId,
    required String versionTo,
    String? versionFrom,
  }) async {
    final p = _versionsPrefix();
    final resp = await _dio.get(
      '$p/$documentId/comments/$versionTo',
      queryParameters: {
        if (versionFrom != null && versionFrom.trim().isNotEmpty)
          'versionFrom': versionFrom.trim(),
      },
    );
    if (resp.statusCode == 200) {
      final data = resp.data;
      if (data is Map && data['comments'] is List) return data['comments'] as List;
      if (data is List) return data;
    }
    return [];
  }

  Future<Map<String, dynamic>?> addComment({
    required String documentId,
    required String version,
    required String comment,
  }) async {
    final p = _versionsPrefix();
    final resp = await _dio.post(
      '$p/$documentId/comments',
      data: {'version': version, 'comment': comment},
    );
    if (resp.statusCode == 200) {
      return resp.data is Map ? Map<String, dynamic>.from(resp.data as Map) : {'comment': resp.data};
    }
    return null;
  }

  Future<bool> resolveComment(String commentId) async {
    final p = _versionsPrefix();
    final resp = await _dio.post('$p/comments/$commentId/resolve');
    return resp.statusCode == 200;
  }

  Future<bool> deleteComment(String commentId) async {
    final p = _versionsPrefix();
    final resp = await _dio.delete('$p/comments/$commentId');
    return resp.statusCode == 200;
  }
}
