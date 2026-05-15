import 'package:dio/dio.dart';
import 'package:digi_sanchika/services/api_client.dart';
import 'package:digi_sanchika/models/document.dart';

class SharedBrowseService {
  static Dio get _dio => ApiClient.instance.dio;

  static String get _sharesBasePath {
    final base = ApiClient.instance.baseUrl;
    final uri = Uri.tryParse(base);
    final basePath = (uri?.path ?? '').trim();
    final normalized = basePath.endsWith('/')
        ? basePath.substring(0, basePath.length - 1)
        : basePath;
    return normalized.endsWith('/api') ? '/shares' : '/api/shares';
  }

  static Future<Map<String, dynamic>> getSharedFolderContents({
    String? folderId,
  }) async {
    try {
      if (folderId == null || folderId.isEmpty) {
        return {'success': false, 'error': 'Missing folder id'};
      }
      final response = await _dio.get('$_sharesBasePath/folders/$folderId/contents');
      if (response.statusCode == 200) {
        final data = response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : <String, dynamic>{};
        final documents = _mapDocuments(data['documents'] ?? []);
        final folders = data['folders'] ?? [];

        return {
          'success': true,
          'documents': documents,
          'folders': folders,
          'breadcrumbs': data['breadcrumbs'] ?? [],
          'folder': data['folder'],
          'share': data['share'],
        };
      }

      // Fallback for legacy behavior (non-shared endpoints)
      final docsResponse = await _dio.get(
        '/documents',
        queryParameters: {'folderId': folderId},
      );
      final foldersResponse = await _dio.get(
        '/folders',
        queryParameters: {'parentId': folderId},
      );
      final docsData = docsResponse.data is Map<String, dynamic>
          ? (docsResponse.data['documents'] ?? docsResponse.data['items'] ?? [])
          : (docsResponse.data is List ? docsResponse.data : []);
      final documents = _mapDocuments(docsData);
      final folders = foldersResponse.data is List
          ? foldersResponse.data
          : (foldersResponse.data['items'] ??
              foldersResponse.data['folders'] ??
              []);

      return {
        'success': true,
        'documents': documents,
        'folders': folders,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static List<Document> _mapDocuments(List<dynamic> data) {
    return data.map((doc) {
      final map = Map<String, dynamic>.from(doc);
      final filename =
          map['name']?.toString() ??
          map['original_filename']?.toString() ??
          map['file_name']?.toString() ??
          'Document';
      final mimeType = map['mime_type']?.toString();
      final fileType = mimeType != null && mimeType.isNotEmpty
          ? _extractFileTypeFromMime(mimeType, filename.toString())
          : _extractFileType(filename.toString());
      return Document(
        id: map['id'].toString(),
        name: filename.toString(),
        type: fileType,
        size:
            (map['file_size_bytes'] ??
                    map['file_size'] ??
                    map['size'] ??
                    0)
                .toString(),
        keyword: map['keywords']?.toString() ?? '',
        uploadDate:
            map['created_at']?.toString() ??
            map['updated_at']?.toString() ??
            '',
        owner: map['owner']?['name']?.toString() ?? 'Unknown',
        details: map['remarks']?.toString() ?? '',
        classification:
            map['classification']?.toString() ??
            map['doc_class']?.toString() ??
            'internal',
        allowDownload: map['allow_download'] ?? true,
        sharingType: 'shared',
        folder: map['folder_path']?.toString() ?? 'Home',
        folderId: map['folder_id']?.toString(),
        path: filename.toString(),
        fileType: fileType,
      );
    }).toList();
  }

  static String _extractFileType(String filename) {
    final ext = filename.toLowerCase().split('.').last;
    switch (ext) {
      case 'pdf':
        return 'PDF';
      case 'doc':
      case 'docx':
        return 'DOCX';
      case 'xls':
      case 'xlsx':
        return 'XLSX';
      case 'ppt':
      case 'pptx':
        return 'PPTX';
      case 'txt':
        return 'TXT';
      default:
        return ext.toUpperCase();
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
