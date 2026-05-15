import 'package:dio/dio.dart';
import 'package:digi_sanchika/services/api_client.dart';
import 'package:digi_sanchika/services/download_requests_service.dart';

class DownloadAccessService {
  static Dio _rawDio() {
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

  static String _extractFilenameFromHeaders(Response response) {
    final cd = response.headers.value('content-disposition');
    if (cd == null) return 'document';
    final match = RegExp(r'filename=\"?([^\";]+)\"?').firstMatch(cd);
    return match?.group(1) ?? 'document';
  }

  static String? _extractUrl(dynamic data) {
    if (data == null) return null;
    if (data is String) return data;
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final url = map['downloadUrl'] ?? map['download_url'] ?? map['url'];
      return url?.toString();
    }
    return null;
  }

  static bool _isRequiresApprovalResponse(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data['requiresApproval'] == true ||
          data['requires_approval'] == true;
    }
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      return map['requiresApproval'] == true || map['requires_approval'] == true;
    }
    return false;
  }

  static bool _isApprovedStatus(String status) {
    final s = status.trim().toLowerCase();
    return s == 'approved' || s == 'approve' || s == 'granted';
  }

  static int _parseIsoOrEmptyToEpoch(String? iso) {
    if (iso == null || iso.trim().isEmpty) return 0;
    try {
      return DateTime.parse(iso).millisecondsSinceEpoch;
    } catch (_) {
      return 0;
    }
  }

  static Future<Response<dynamic>> _fetchBytes(String url) async {
    final options =
        Options(responseType: ResponseType.bytes, headers: {'Accept': '*/*'});
    final uri = Uri.tryParse(url);

    // Relative URL -> use bearer-enabled client.
    if (uri == null || !uri.hasScheme) {
      return ApiClient.instance.dio.get(url, options: options);
    }

    // Absolute URL: try raw first for presigned links.
    final raw = _rawDio();
    final rawResp = await raw.get(url, options: options);
    if (rawResp.statusCode == 401 || rawResp.statusCode == 403) {
      // Might be an API URL that still needs bearer/cookies.
      return ApiClient.instance.dio.get(url, options: options);
    }
    return rawResp;
  }

  /// Attempts direct download via `GET /documents/:id/download-url`.
  /// If approval is required (403 with `requiresApproval: true`), tries to redeem an existing approved request
  /// via `POST /download-requests/:id/use-token`.
  ///
  /// Returns:
  /// - `{ success:true, bytes, filename, contentType }`
  /// - `{ success:false, requiresApproval:true }` (caller should create a request)
  /// - `{ success:false, error }`
  static Future<Map<String, dynamic>> downloadBytesWithAccess({
    required String documentId,
  }) async {
    try {
      final dio = ApiClient.instance.dio;
      final urlResp = await dio.get('/documents/$documentId/download-url');
      final status = urlResp.statusCode ?? 0;
      if (status == 200) {
        final url = _extractUrl(urlResp.data);
        if (url == null || url.isEmpty) {
          return {'success': false, 'error': 'Download URL missing'};
        }
        final fileResp = await _fetchBytes(url);
        if (fileResp.statusCode == 200) {
          final bytes = fileResp.data;
          final list = bytes is List<int> ? bytes : (bytes is List ? bytes.cast<int>() : <int>[]);
          return {
            'success': true,
            'bytes': list,
            'filename': _extractFilenameFromHeaders(fileResp),
            'contentType': fileResp.headers.value('content-type'),
          };
        }
        return {'success': false, 'error': 'Download failed (${fileResp.statusCode})'};
      }

      if (status == 403 && _isRequiresApprovalResponse(urlResp.data)) {
        // Try existing approved request -> redeem token -> download.
        final reqService = DownloadRequestsService();
        final requests = await reqService.myRequests();
        final approvedForDoc = requests
            .where((r) => r.documentId == documentId && _isApprovedStatus(r.status))
            .toList()
          ..sort((a, b) {
            final aTs = _parseIsoOrEmptyToEpoch(a.approvedAt) != 0
                ? _parseIsoOrEmptyToEpoch(a.approvedAt)
                : _parseIsoOrEmptyToEpoch(a.createdAt);
            final bTs = _parseIsoOrEmptyToEpoch(b.approvedAt) != 0
                ? _parseIsoOrEmptyToEpoch(b.approvedAt)
                : _parseIsoOrEmptyToEpoch(b.createdAt);
            return bTs.compareTo(aTs);
          });

        if (approvedForDoc.isNotEmpty) {
          final use = await reqService.useTokenAuthenticated(approvedForDoc.first.id);
          if (use['success'] == true) {
            final url = _extractUrl(use['data']);
            if (url != null && url.isNotEmpty) {
              final fileResp = await _fetchBytes(url);
              if (fileResp.statusCode == 200) {
                final bytes = fileResp.data;
                final list = bytes is List<int>
                    ? bytes
                    : (bytes is List ? bytes.cast<int>() : <int>[]);
                return {
                  'success': true,
                  'bytes': list,
                  'filename': _extractFilenameFromHeaders(fileResp),
                  'contentType': fileResp.headers.value('content-type'),
                  'usedToken': true,
                };
              }
            }
          }
        }

        return {'success': false, 'requiresApproval': true};
      }

      return {'success': false, 'error': 'Download not allowed (${status})'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
}
