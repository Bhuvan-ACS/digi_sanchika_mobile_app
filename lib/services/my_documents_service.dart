import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:digi_sanchika/services/api_client.dart';
import 'package:digi_sanchika/models/document.dart';
import 'package:digi_sanchika/models/folder.dart';
import 'package:digi_sanchika/services/versions_service.dart';

class MyDocumentsService {
  static final MyDocumentsService _instance = MyDocumentsService._internal();

  static Dio _rawDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        followRedirects: true,
      ),
    );
  }

  factory MyDocumentsService() => _instance;
  MyDocumentsService._internal();

  static Future<Map<String, dynamic>> fetchMyDocuments({
    String? folderId,
  }) async {
    try {
      final dio = ApiClient.instance.dio;
      final response = await dio.get(
        '/documents',
        queryParameters: folderId != null ? {'folderId': folderId} : null,
      );

      if (response.statusCode == 200) {
        final responseData = response.data;
        List<dynamic> docsRaw = [];
        List<dynamic> foldersRaw = [];
        if (responseData is Map<String, dynamic>) {
          docsRaw =
              responseData['documents'] ??
              responseData['items'] ??
              responseData['data'] ??
              [];
          foldersRaw = responseData['folders'] ?? [];
        } else if (responseData is List) {
          docsRaw = responseData;
        }
        final documents = _mapBackendDocuments(docsRaw);
        final folders = _mapBackendFolders(foldersRaw, folderId);

        return {
          'success': true,
          'documents': documents,
          'folders': folders,
          'total': documents.length,
        };
      }
      return {
        'success': false,
        'error': 'Failed to load documents (${response.statusCode})',
      };
    } catch (e) {
      return {'success': false, 'error': 'Exception: $e'};
    }
  }

  static Future<Map<String, dynamic>> deleteDocument(String documentId) async {
    try {
      final dio = ApiClient.instance.dio;
      final response = await dio.delete('/documents/$documentId');
      final status = response.statusCode ?? 0;
      if (status == 200 || status == 202 || status == 204) {
        return {
          'success': true,
          'statusCode': status,
          'message': 'Document deleted successfully',
        };
      }
      return {
        'success': false,
        'statusCode': status,
        'error': 'Failed to delete document ($status)',
        'data': response.data,
      };
    } catch (e) {
      return {'success': false, 'error': 'Exception: $e'};
    }
  }

  static Future<Map<String, dynamic>> createFolder({
    required String folderName,
    String? parentFolderId,
  }) async {
    try {
      final dio = ApiClient.instance.dio;
      final response = await dio.post(
        '/folders',
        data: {
          'name': folderName,
          'parentId': parentFolderId,
          'parent_id': parentFolderId,
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Server responds `{ folder: {...} }`; older builds sent it bare.
        final raw = response.data;
        final data = raw is Map && raw['folder'] is Map ? raw['folder'] : raw;
        final folder = Folder(
          id: data['id'].toString(),
          name: data['name'] ?? folderName,
          documents: [],
          createdAt:
              DateTime.tryParse(data['created_at']?.toString() ?? '') ??
              DateTime.now(),
          owner: data['owner']?.toString() ?? 'User',
        );
        return {
          'success': true,
          'folder': folder,
          'message': 'Folder created successfully',
        };
      }
      return {
        'success': false,
        'error': 'Failed to create folder (${response.statusCode})',
      };
    } catch (e) {
      return {'success': false, 'error': 'Exception: $e'};
    }
  }

  static Future<Map<String, dynamic>> deleteFolder(String folderId) async {
    try {
      final dio = ApiClient.instance.dio;
      final response = await dio.delete('/folders/$folderId');
      if (response.statusCode == 200) {
        return {'success': true, 'message': 'Folder deleted successfully'};
      }
      return {
        'success': false,
        'error': 'Failed to delete folder (${response.statusCode})',
      };
    } catch (e) {
      return {'success': false, 'error': 'Exception: $e'};
    }
  }

  static Future<Map<String, dynamic>> downloadDocumentVersion({
    required String documentId,
    required String versionNumber,
  }) async {
    try {
      final service = VersionsService();
      final result = await service.downloadVersionBytes(
        documentId: documentId,
        version: versionNumber,
      );
      if (result['success'] == true) {
        return {
          'success': true,
          'data': result['bytes'],
          'filename': result['filename'],
          'mimeType': result['mimeType'],
        };
      }
      return {'success': false, 'error': result['error'] ?? 'Download failed'};
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> downloadDocument(
    String documentId,
  ) async {
    try {
      final dio = ApiClient.instance.dio;
      final urlResponse = await dio.get('/documents/$documentId/download-url');
      if (kDebugMode) {
        print('📥 download-url status: ${urlResponse.statusCode}');
        print('📥 download-url data: ${urlResponse.data}');
      }
      if (urlResponse.statusCode == 200) {
        final urlData = urlResponse.data;
        final url = urlData is Map<String, dynamic> ? urlData['url'] : urlData;
        if (url == null) {
          return {'success': false, 'error': 'Download URL missing'};
        }
        if (kDebugMode) {
          print('📥 download-url resolved: $url');
        }
        final raw = _rawDio();
        final response = await raw.get(
          url.toString(),
          options: Options(
            responseType: ResponseType.bytes,
            headers: {"Accept": "*/*"},
          ),
        );
        if (kDebugMode) {
          final bytes = response.data is List<int>
              ? response.data as List<int>
              : <int>[];
          final head = bytes.take(16).toList();
          final headAscii = bytes.isNotEmpty
              ? String.fromCharCodes(head.map((b) => b < 32 ? 46 : b))
              : '';
          print('📥 file status: ${response.statusCode}');
          print(
            '📥 file content-type: ${response.headers.value('content-type')}',
          );
          print('📥 file bytes: ${bytes.length}');
          print('📥 file head bytes: $head');
          print('📥 file head ascii: $headAscii');
        }
        if (response.statusCode == 200) {
          return {
            'success': true,
            'data': response.data,
            'filename': _extractFilename(response),
          };
        }
      } else if (urlResponse.statusCode == 403) {
        final data = urlResponse.data;
        final requiresApproval =
            data is Map<String, dynamic> && data['requiresApproval'] == true;
        if (requiresApproval) {
          return {
            'success': false,
            'requiresApproval': true,
            'error': 'Download requires approval',
          };
        }
      }
      return {'success': false, 'error': 'Download failed'};
    } catch (e) {
      return {'success': false, 'error': 'Exception: $e'};
    }
  }

  static String _extractFilename(Response response) {
    final contentDisposition = response.headers.value('content-disposition');
    if (contentDisposition != null) {
      final match = RegExp(
        r'filename="([^"]+)"',
      ).firstMatch(contentDisposition);
      if (match != null) return match.group(1) ?? 'document';
    }
    return 'document';
  }

  static Future<Map<String, dynamic>> getDocumentVersions(
    String documentId,
  ) async {
    try {
      final service = VersionsService();
      final versions = await service.listVersions(documentId);
      return {
        'success': true,
        'versions': versions.map((v) {
          return {
            'version': v.version,
            'name': v.name,
            'mime_type': v.mimeType,
            'file_size_bytes': v.fileSizeBytes,
            'content_hash': v.contentHash,
            'classification': v.classification,
            'keywords': v.keywords,
            'remarks': v.remarks,
            'change_note': v.changeNote,
            'created_by': v.createdBy,
            'author_name': v.authorName,
            'created_at': v.createdAt,
          };
        }).toList(),
      };
    } catch (e) {
      return {'success': false, 'error': 'Exception: $e', 'versions': []};
    }
  }

  static Future<Map<String, dynamic>> getDocumentDetails(
    String documentId,
  ) async {
    try {
      final dio = ApiClient.instance.dio;
      final response = await dio.get('/documents/$documentId');
      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map<String, dynamic> && data['document'] != null) {
          return {'success': true, 'details': data['document']};
        }
        return {'success': true, 'details': data};
      }
      return {
        'success': false,
        'error': 'Failed to get details (${response.statusCode})',
      };
    } catch (e) {
      return {'success': false, 'error': 'Exception: $e'};
    }
  }

  /// Backend scopes are `my | shared | library | all`; older callers pass
  /// `mine`, so normalise before sending.
  static String _searchScope(String scope) {
    switch (scope) {
      case 'shared':
      case 'library':
      case 'all':
        return scope;
      default:
        return 'my';
    }
  }

  static String? _errorMessage(dynamic data) {
    if (data is Map && data['error'] != null) return data['error'].toString();
    return null;
  }

  /// Reads `{ results: [ { documentId, score | rank, chunkPreview? } ] }`.
  static List<Map<String, dynamic>> _parseSearchResults(dynamic data) {
    final results = data is Map ? data['results'] : null;
    if (results is! List) return [];
    final out = <Map<String, dynamic>>[];
    for (final r in results) {
      if (r is! Map) continue;
      final m = Map<String, dynamic>.from(r);
      final id = (m['documentId'] ?? m['document_id'] ?? '').toString();
      if (id.isEmpty) continue;
      out.add({
        'documentId': id,
        'score': m['score'] ?? m['rank'],
        'chunkPreview': m['chunkPreview'] ?? m['chunk_preview'],
      });
    }
    return out;
  }

  /// Search endpoints return ids only; fetch each document for display.
  static Future<List<Document>> _resolveDocuments(List<String> ids) async {
    final details = await Future.wait(ids.map(getDocumentDetails));
    final raw = details
        .where((d) => d['success'] == true && d['details'] is Map)
        .map((d) => d['details'])
        .toList();
    return _mapBackendDocuments(raw);
  }

  /// POST /search/keyword. Returns `results` (ids + rank) and the resolved
  /// `documents` in rank order.
  static Future<Map<String, dynamic>> keywordSearch({
    required String query,
    String scope = 'my',
    int limit = 25,
    bool resolveDocuments = true,
  }) async {
    final q = query.trim();
    if (q.isEmpty) {
      return {'success': true, 'results': [], 'documents': <Document>[]};
    }
    try {
      final dio = ApiClient.instance.dio;
      final response = await dio.post(
        '/search/keyword',
        data: {'query': q, 'scope': _searchScope(scope), 'limit': limit},
      );
      if (response.statusCode == 200) {
        final results = _parseSearchResults(response.data);
        final documents = resolveDocuments
            ? await _resolveDocuments(
                results.map((r) => r['documentId'] as String).toList(),
              )
            : <Document>[];
        return {'success': true, 'results': results, 'documents': documents};
      }
      return {
        'success': false,
        'error':
            _errorMessage(response.data) ??
            'Search failed (${response.statusCode})',
      };
    } catch (e) {
      return {'success': false, 'error': 'Exception: $e'};
    }
  }

  /// AI search. Tries semantic v2 (`/search/semantic`); when v2 is switched
  /// off on the server it uses legacy v1 (`/ai/semantic-search`), and when
  /// semantic search is disabled altogether it falls back to keyword search.
  ///
  /// Returns `{ success, results: [{documentId, score, chunkPreview}],
  /// mode: 'semantic' | 'legacy' | 'keyword', pendingEmbeddings? }`.
  static Future<Map<String, dynamic>> semanticSearch({
    required String query,
    String scope = 'my',
    int limit = 10,
    Map<String, dynamic>? filters,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return {'success': true, 'results': [], 'mode': 'semantic'};
    final apiScope = _searchScope(scope);
    try {
      final dio = ApiClient.instance.dio;
      final response = await dio.post(
        '/search/semantic',
        data: {
          'query': q,
          'scope': apiScope,
          'limit': limit,
          if (filters != null && filters.isNotEmpty) 'filters': filters,
        },
      );
      if (response.statusCode == 200) {
        return {
          'success': true,
          'results': _parseSearchResults(response.data),
          'mode': 'semantic',
        };
      }

      final error = _errorMessage(response.data) ?? '';
      if (response.statusCode == 400 && error.contains('v2 is disabled')) {
        return _legacySemanticSearch(query: q, scope: apiScope, limit: limit);
      }
      if (response.statusCode == 400 &&
          error.contains('Semantic search is disabled')) {
        return _keywordFallback(query: q, scope: apiScope, limit: limit);
      }
      return {
        'success': false,
        'error': error.isNotEmpty
            ? error
            : 'Semantic search failed (${response.statusCode})',
      };
    } catch (e) {
      return {'success': false, 'error': 'Exception: $e'};
    }
  }

  static Future<Map<String, dynamic>> _legacySemanticSearch({
    required String query,
    required String scope,
    required int limit,
  }) async {
    final dio = ApiClient.instance.dio;
    final response = await dio.post(
      '/ai/semantic-search',
      data: {'query': query, 'scope': scope, 'limit': limit},
    );
    if (response.statusCode == 200) {
      final data = response.data;
      return {
        'success': true,
        'results': _parseSearchResults(data),
        'mode': 'legacy',
        'pendingEmbeddings': data is Map ? data['pendingEmbeddings'] ?? 0 : 0,
      };
    }
    final error = _errorMessage(response.data) ?? '';
    if (response.statusCode == 400 &&
        error.contains('Semantic search is disabled')) {
      return _keywordFallback(query: query, scope: scope, limit: limit);
    }
    return {
      'success': false,
      'error': error.isNotEmpty
          ? error
          : 'Semantic search failed (${response.statusCode})',
    };
  }

  static Future<Map<String, dynamic>> _keywordFallback({
    required String query,
    required String scope,
    required int limit,
  }) async {
    final keyword = await keywordSearch(
      query: query,
      scope: scope,
      limit: limit,
      resolveDocuments: false,
    );
    return {...keyword, 'mode': 'keyword'};
  }

  /// GET /ai/status: which AI features are on, providers and backfill.
  static Future<Map<String, dynamic>?> getAiStatus() async {
    try {
      final dio = ApiClient.instance.dio;
      final response = await dio.get('/ai/status');
      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> isSemanticSearchAvailable() async {
    final status = await getAiStatus();
    if (status == null) return false;
    return status['globalEnabled'] == true &&
        status['semanticSearchEnabled'] == true &&
        status['semanticProviderReady'] == true;
  }

  // Kept for backward compat
  static Future<Map<String, dynamic>> enhancedSearch({
    required Map<String, dynamic> criteria,
    required String scope,
  }) async {
    final query =
        criteria['query']?.toString() ?? criteria['text']?.toString() ?? '';
    return keywordSearch(query: query, scope: scope);
  }

  static Future<Map<String, dynamic>> getUsersForSharing() async {
    try {
      final dio = ApiClient.instance.dio;
      Response response;
      try {
        response = await dio.get('/shares/users');
      } catch (_) {
        response = await dio.get('/users');
      }
      if (response.statusCode == 200) {
        final users = response.data as List;
        return {'success': true, 'users': users};
      }
      return {
        'success': false,
        'error': 'Failed to get users (${response.statusCode})',
      };
    } catch (e) {
      return {'success': false, 'error': 'Exception: $e'};
    }
  }

  static Future<Map<String, dynamic>> shareDocument({
    required String documentId,
    required List<String> userIds,
  }) async {
    try {
      final dio = ApiClient.instance.dio;
      bool allOk = true;
      List<String> errors = [];
      for (final userId in userIds) {
        final response = await dio.post(
          '/shares/documents/$documentId',
          data: {'sharedWithId': userId},
        );
        if (response.statusCode != 200 && response.statusCode != 201) {
          allOk = false;
          errors.add('User $userId -> ${response.statusCode}');
        }
      }
      return {
        'success': allOk,
        'message': allOk
            ? 'Document shared successfully'
            : 'Some shares failed',
        if (errors.isNotEmpty) 'errors': errors,
      };
    } catch (e) {
      if (kDebugMode) print('Share document error: $e');
      return {'success': false, 'error': 'Exception: $e'};
    }
  }

  static Future<Map<String, dynamic>> shareFolder({
    required String folderId,
    required List<String> userIds,
  }) async {
    try {
      final dio = ApiClient.instance.dio;
      bool allOk = true;
      List<String> errors = [];
      for (final userId in userIds) {
        final response = await dio.post(
          '/shares/folders/$folderId',
          data: {'sharedWithId': userId},
        );
        if (response.statusCode != 200 && response.statusCode != 201) {
          allOk = false;
          errors.add('User $userId -> ${response.statusCode}');
        }
      }
      return {
        'success': allOk,
        'message': allOk ? 'Folder shared successfully' : 'Some shares failed',
        if (errors.isNotEmpty) 'errors': errors,
      };
    } catch (e) {
      if (kDebugMode) print('Share folder error: $e');
      return {'success': false, 'error': 'Exception: $e'};
    }
  }

  static List<Document> _mapBackendDocuments(List<dynamic> backendDocs) {
    final List<Document> documents = [];

    for (var docJson in backendDocs) {
      try {
        final docData = Map<String, dynamic>.from(docJson);
        final filename =
            docData['name']?.toString() ??
            docData['original_filename']?.toString() ??
            docData['file_name']?.toString() ??
            '';
        final mimeType = docData['mime_type']?.toString();
        final fileType = mimeType != null && mimeType.isNotEmpty
            ? _extractFileTypeFromMime(mimeType, filename)
            : _extractFileType(filename);
        // "Public" for the mobile Document Library means "published to library",
        // not the document's classification level.
        final isPublishedToLibrary =
            docData['is_published_to_library'] == true ||
            docData['isPublishedToLibrary'] == true ||
            docData['is_public'] == true;
        final sharingType = isPublishedToLibrary ? 'Public' : 'Private';

        documents.add(
          Document(
            id: docData['id']?.toString() ?? '',
            name: filename.isNotEmpty ? filename : 'Untitled Document',
            type: fileType,
            size: _getFileSize(docData),
            keyword: docData['keywords']?.toString() ?? '',
            uploadDate: _formatUploadDate(
              docData['created_at'] ?? docData['updated_at'],
            ),
            owner:
                docData['owner']?['name']?.toString() ??
                docData['owner']?.toString() ??
                'Unknown',
            details: docData['remarks']?.toString() ?? '',
            classification:
                docData['classification']?.toString() ??
                docData['doc_class']?.toString() ??
                'internal',
            allowDownload: docData['allow_download'] == true,
            isPublishedToLibrary: isPublishedToLibrary,
            sharingType: sharingType,
            folder: docData['folder_path']?.toString() ?? 'Home',
            folderId: docData['folder_id']?.toString(),
            path: filename,
            fileType: fileType,
          ),
        );
      } catch (e) {
        if (kDebugMode) {
          print('Error mapping document: $e');
        }
      }
    }

    return documents;
  }

  static List<Folder> _mapBackendFolders(
    List<dynamic> backendFolders,
    String? parentId,
  ) {
    final List<Folder> folders = [];

    for (var folderJson in backendFolders) {
      try {
        final folderData = Map<String, dynamic>.from(folderJson);
        folders.add(
          Folder(
            id: folderData['id']?.toString() ?? '',
            name: folderData['name']?.toString() ?? 'Unnamed Folder',
            documents: [],
            parentId: parentId,
            createdAt:
                DateTime.tryParse(folderData['created_at']?.toString() ?? '') ??
                DateTime.now(),
            owner: folderData['owner']?.toString() ?? 'User',
          ),
        );
      } catch (e) {
        if (kDebugMode) {
          print('Error mapping folder: $e');
        }
      }
    }

    return folders;
  }

  static String _extractFileType(String filename) {
    if (filename.isEmpty) return 'unknown';
    final parts = filename.split('.');
    if (parts.length < 2) return 'unknown';

    final extension = parts.last.toLowerCase();
    final typeMap = {
      'pdf': 'PDF',
      'doc': 'DOC',
      'docx': 'DOCX',
      'xls': 'XLS',
      'xlsx': 'XLSX',
      'ppt': 'PPT',
      'pptx': 'PPTX',
      'txt': 'TXT',
      'csv': 'CSV',
      'jpg': 'JPG',
      'jpeg': 'JPEG',
      'jfif': 'JPG',
      'png': 'PNG',
      'zip': 'ZIP',
      'rar': 'RAR',
    };

    return typeMap[extension] ?? extension.toUpperCase();
  }

  static String _getFileSize(Map<String, dynamic> docData) {
    final sizeValue =
        docData['file_size_bytes'] ??
        docData['file_size'] ??
        docData['size'] ??
        docData['fileSize'];
    if (sizeValue != null) {
      try {
        final int sizeInBytes = int.tryParse(sizeValue.toString()) ?? 0;
        if (sizeInBytes == 0) return '0 KB';

        const int kb = 1024;
        const int mb = kb * 1024;
        const int gb = mb * 1024;

        if (sizeInBytes >= gb) {
          return '${(sizeInBytes / gb).toStringAsFixed(1)} GB';
        } else if (sizeInBytes >= mb) {
          return '${(sizeInBytes / mb).toStringAsFixed(1)} MB';
        } else if (sizeInBytes >= kb) {
          return '${(sizeInBytes / kb).toStringAsFixed(1)} KB';
        } else {
          return '$sizeInBytes B';
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error parsing file size: $e');
        }
      }
    }
    return 'Unknown Size';
  }

  static String _formatUploadDate(dynamic dateValue) {
    if (dateValue == null) return DateTime.now().toString();
    try {
      final dateStr = dateValue.toString();
      if (dateStr.contains('T')) {
        final dateTime = DateTime.parse(dateStr);
        return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year}';
      }
      return dateStr;
    } catch (e) {
      return dateValue.toString();
    }
  }

  static String _extractFileTypeFromMime(String mimeType, String filename) {
    final type = mimeType.toLowerCase();
    if (type.contains('pdf')) return 'PDF';
    if (type.contains('word')) return 'DOCX';
    if (type.contains('sheet') || type.contains('excel')) return 'XLSX';
    if (type.contains('presentation') || type.contains('powerpoint')) {
      return 'PPTX';
    }
    if (type.startsWith('image/')) return 'IMAGE';
    if (type.startsWith('text/')) return 'TXT';
    return _extractFileType(filename);
  }
}
