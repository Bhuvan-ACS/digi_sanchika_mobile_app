import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:digi_sanchika/models/document.dart';
import 'package:digi_sanchika/services/api_client.dart';
import 'package:digi_sanchika/local_storage.dart';
import 'package:digi_sanchika/services/versions_service.dart';

class DocumentLibraryService {
  static final DocumentLibraryService _instance =
      DocumentLibraryService._internal();

  Dio _rawDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        followRedirects: true,
      ),
    );
  }

  factory DocumentLibraryService() => _instance;

  DocumentLibraryService._internal();

  Dio get _dio => ApiClient.instance.dio;

  Future<List<Document>> fetchLibraryDocuments() async {
    try {
      if (!ApiClient.instance.baseUrl.isNotEmpty) {
        return await LocalStorageService.loadDocuments(isPublic: true);
      }

      final response = await _dio.get('/library');
      if (response.statusCode == 200) {
        final data = response.data;
        List<dynamic> list = [];
        if (data is List) {
          list = data;
        } else if (data is Map<String, dynamic>) {
          if (data['documents'] is List) {
            list = data['documents'];
          } else if (data['items'] is List) {
            list = data['items'];
          } else if (data['results'] is List) {
            list = data['results'];
          } else if (data['data'] is List) {
            list = data['data'];
          } else if (data['data'] is Map<String, dynamic> &&
              data['data']['documents'] is List) {
            list = data['data']['documents'];
          }
        }
        final documents = _convertToDocumentList(list);
        await LocalStorageService.saveDocuments(documents, isPublic: true);
        return documents;
      }
      return await LocalStorageService.loadDocuments(isPublic: true);
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching library docs: $e');
      }
      return await LocalStorageService.loadDocuments(isPublic: true);
    }
  }

  Future<Map<String, dynamic>> getDocumentDetails(String documentId) async {
    try {
      final response = await _dio.get('/documents/$documentId');
      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map<String, dynamic> && data['document'] != null) {
          return {'success': true, 'data': data['document']};
        }
        return {'success': true, 'data': data};
      }
      return {
        'success': false,
        'error': 'Failed to fetch details: ${response.statusCode}',
        'data': null,
      };
    } catch (e) {
      return {'success': false, 'error': 'Error fetching details: $e'};
    }
  }

  Future<Map<String, dynamic>> getDocumentVersions(String documentId) async {
    try {
      final service = VersionsService();
      final versions = await service.listVersions(documentId);
      return {
        'success': true,
        'document_name': null,
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
      return {'success': false, 'error': 'Error fetching versions: $e'};
    }
  }

  Future<Map<String, dynamic>> getViewUrl(String documentId) async {
    try {
      final response = await _dio.get('/documents/$documentId/view-url');
      if (response.statusCode == 200) {
        return {'success': true, 'data': response.data};
      }
      return {'success': false, 'error': 'Failed to get view URL'};
    } catch (e) {
      return {'success': false, 'error': 'View URL error: $e'};
    }
  }

  Future<Map<String, dynamic>> getDownloadUrl(String documentId) async {
    try {
      final response = await _dio.get('/documents/$documentId/download-url');
      if (response.statusCode == 200) {
        return {'success': true, 'data': response.data};
      }
      if (response.statusCode == 403) {
        final data = response.data;
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
      return {'success': false, 'error': 'Failed to get download URL'};
    } catch (e) {
      return {'success': false, 'error': 'Download URL error: $e'};
    }
  }

  Future<Map<String, dynamic>> downloadDocument(
    String documentId,
    String filename,
  ) async {
    try {
      final urlResult = await getDownloadUrl(documentId);
      if (urlResult['success'] != true) {
        return {'success': false, 'error': urlResult['error']};
      }

      final data = urlResult['data'];
      final url = data is Map<String, dynamic> ? data['url'] : data;
      if (url == null) {
        return {'success': false, 'error': 'Download URL missing'};
      }

      final raw = _rawDio();
      final response = await raw.get(
        url.toString(),
        options: Options(
          responseType: ResponseType.bytes,
          headers: {"Accept": "*/*"},
        ),
      );
      if (response.statusCode == 200) {
        return {
          'success': true,
          'data': response.data,
          'filename': filename,
          'contentType': response.headers.value('content-type'),
        };
      }
      return {'success': false, 'error': 'Download failed'};
    } catch (e) {
      return {'success': false, 'error': 'Download error: $e'};
    }
  }

  Future<Map<String, dynamic>> publishDocument(String documentId) async {
    try {
      final response = await _dio.post('/documents/$documentId/publish');
      if (response.statusCode == 200) {
        return {'success': true, 'message': 'Published'};
      }
      return {'success': false, 'message': 'Publish failed'};
    } catch (e) {
      return {'success': false, 'message': 'Publish error: $e'};
    }
  }

  Future<Map<String, dynamic>> unpublishDocument(String documentId) async {
    try {
      final response = await _dio.post('/documents/$documentId/unpublish');
      if (response.statusCode == 200) {
        return {'success': true, 'message': 'Unpublished'};
      }
      return {'success': false, 'message': 'Unpublish failed'};
    } catch (e) {
      return {'success': false, 'message': 'Unpublish error: $e'};
    }
  }

  List<Document> _convertToDocumentList(List<dynamic> data) {
    return data.map((docJson) {
      final rawMap = Map<String, dynamic>.from(docJson as Map);
      final map = rawMap['document'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(rawMap['document'])
          : rawMap;
      final ownerMap = rawMap['owner'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(rawMap['owner'])
          : null;
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
        size: _formatFileSize(
          map['file_size_bytes'] ?? map['file_size'] ?? map['size'] ?? 0,
        ),
        keyword: map['keywords']?.toString() ?? '',
        uploadDate:
            map['created_at']?.toString() ??
            map['updated_at']?.toString() ??
            DateTime.now().toString(),
        owner:
            ownerMap?['full_name']?.toString() ??
            ownerMap?['name']?.toString() ??
            map['owner']?.toString() ??
            '',
        details: map['remarks']?.toString() ?? '',
        classification:
            map['classification']?.toString() ??
            map['doc_class']?.toString() ??
            'public',
        allowDownload: map['allow_download'] ?? true,
        // Items returned from `/library` are "published to library". Do not infer from
        // `classification` (classification is a security label, not a publish flag).
        isPublishedToLibrary: true,
        sharingType: 'Public',
        folder: map['folder_path']?.toString() ?? 'Home',
        folderId: map['folder_id']?.toString(),
        path: filename.toString(),
        fileType: fileType,
      );
    }).toList();
  }

  String _extractFileType(String filename) {
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
      case 'jpg':
      case 'jpeg':
      case 'jfif':
      case 'png':
      case 'gif':
        return 'IMAGE';
      default:
        return ext.toUpperCase();
    }
  }

  String _extractFileTypeFromMime(String mimeType, String filename) {
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

  String _formatFileSize(dynamic size) {
    try {
      final bytes = int.tryParse(size.toString()) ?? 0;
      if (bytes < 1024) return '$bytes B';
      if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
      if (bytes < 1073741824) {
        return '${(bytes / 1048576).toStringAsFixed(1)} MB';
      }
      return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
    } catch (e) {
      return 'Unknown size';
    }
  }
}
