import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:digi_sanchika/models/document.dart';
import 'package:digi_sanchika/models/shared_folder.dart';
import 'package:digi_sanchika/services/api_client.dart';
import 'package:digi_sanchika/services/token_storage.dart';

class SharedDocumentsResponse {
  final List<Document> documents;
  final List<SharedFolder> folders;

  SharedDocumentsResponse({required this.documents, required this.folders});

  factory SharedDocumentsResponse.fromJson(Map<String, dynamic> json) {
    final documents = <Document>[];
    if (json['documents'] is List) {
      for (var docJson in json['documents']) {
        try {
          final raw = Map<String, dynamic>.from(docJson as Map);
          final doc =
              raw['document'] is Map<String, dynamic>
                  ? Map<String, dynamic>.from(raw['document'])
                  : raw;
          final share =
              raw['share'] is Map<String, dynamic>
                  ? Map<String, dynamic>.from(raw['share'])
                  : <String, dynamic>{};
          final owner =
              raw['owner'] is Map<String, dynamic>
                  ? Map<String, dynamic>.from(raw['owner'])
                  : null;
          final sharedBy =
              raw['sharedBy'] is Map<String, dynamic>
                  ? Map<String, dynamic>.from(raw['sharedBy'])
                  : null;

          final filename =
              doc['name']?.toString() ??
              doc['original_filename']?.toString() ??
              doc['file_name']?.toString() ??
              'Unknown Document';
          final mimeType = doc['mime_type']?.toString();
          final fileType = mimeType != null && mimeType.isNotEmpty
              ? _extractFileTypeFromMime(mimeType, filename)
              : _extractFileType(filename);
          final docId = (doc['id'] ??
                  doc['documentId'] ??
                  doc['document_id'] ??
                  raw['documentId'] ??
                  raw['document_id'] ??
                  share['document_id'] ??
                  share['documentId'])
              ?.toString();
          if (docId == null || docId.isEmpty || docId == '0') {
            // If id is missing, skip this entry to avoid breaking actions (view/download/versions).
            continue;
          }

          final allowDownloadValue = share.containsKey('allow_download')
              ? share['allow_download']
              : (doc['allow_download'] ?? doc['allowDownload'] ?? false);
          final allowDownload = allowDownloadValue == true;

          final viaGroupRaw = share['viaGroup'];
          final viaGroup = viaGroupRaw is Map<String, dynamic>
              ? viaGroupRaw
              : (viaGroupRaw is Map ? Map<String, dynamic>.from(viaGroupRaw) : null);
          final sharedByName =
              sharedBy?['full_name']?.toString() ?? sharedBy?['name']?.toString();

          final document = Document(
            id: docId,
            name: filename,
            type: fileType,
            size:
                (doc['file_size_bytes'] ??
                        doc['file_size'] ??
                        doc['size'] ??
                        '0')
                    .toString(),
            keyword: doc['keywords']?.toString() ?? '',
            uploadDate: _formatDate(doc['created_at'] ?? doc['updated_at']),
            owner:
                owner?['full_name']?.toString() ??
                owner?['name']?.toString() ??
                sharedBy?['full_name']?.toString() ??
                sharedBy?['name']?.toString() ??
                'Unknown User',
            details: doc['remarks']?.toString() ?? '',
            classification:
                doc['classification']?.toString() ??
                doc['doc_class']?.toString() ??
                'internal',
            allowDownload: allowDownload == true,
            sharingType: 'shared',
            folder: doc['folder_path']?.toString() ?? 'Shared',
            folderId: doc['folder_id']?.toString(),
            path: filename,
            fileType: fileType,
            sharedViaGroupId: viaGroup?['id']?.toString(),
            sharedViaGroupName: viaGroup?['name']?.toString(),
            sharedViaGroupColorHex:
                (viaGroup?['color'] ?? viaGroup?['colorHex'])?.toString(),
            sharedByName: sharedByName,
          );
          documents.add(document);
        } catch (e) {
          debugPrint('Error parsing document: $e');
        }
      }
    }

    final folders = <SharedFolder>[];
    if (json['folders'] is List) {
      for (var folderJson in json['folders']) {
        try {
          final raw = Map<String, dynamic>.from(folderJson as Map);
          final folderData =
              raw['folder'] is Map<String, dynamic>
                  ? Map<String, dynamic>.from(raw['folder'])
                  : raw;
          final sharedBy =
              raw['sharedBy'] is Map<String, dynamic>
                  ? Map<String, dynamic>.from(raw['sharedBy'])
                  : null;
          final folderId = (folderData['id'] ??
                  folderData['folderId'] ??
                  folderData['folder_id'] ??
                  raw['folderId'] ??
                  raw['folder_id'])
              ?.toString();
          if (folderId == null || folderId.isEmpty || folderId == '0') {
            continue;
          }
          final folder = SharedFolder(
            id: folderId,
            name: folderData['name']?.toString() ?? 'Unknown Folder',
            owner:
                sharedBy?['full_name']?.toString() ??
                sharedBy?['name']?.toString() ??
                folderData['owner']?.toString() ??
                'Unknown User',
            createdAt: _formatDate(folderData['created_at']),
            expiresAt: _formatDate(folderData['expires_at']),
          );
          folders.add(folder);
        } catch (e) {
          debugPrint('Error parsing folder: $e');
        }
      }
    }

    return SharedDocumentsResponse(documents: documents, folders: folders);
  }

  static String _extractFileType(String filename) {
    if (filename.isEmpty) return 'unknown';
    final parts = filename.split('.');
    if (parts.length > 1) {
      final ext = parts.last.toLowerCase();
      if (ext == 'pdf') return 'pdf';
      if (ext == 'doc' || ext == 'docx') return 'docx';
      if (ext == 'xls' || ext == 'xlsx') return 'xlsx';
      if (ext == 'ppt' || ext == 'pptx') return 'pptx';
      if (ext == 'jpg' || ext == 'jpeg' || ext == 'png') return 'image';
      if (ext == 'txt') return 'txt';
      if (ext == 'csv') return 'csv';
      return ext;
    }
    return 'unknown';
  }

  static String _extractFileTypeFromMime(String mimeType, String filename) {
    final type = mimeType.toLowerCase();
    if (type.contains('pdf')) return 'pdf';
    if (type.contains('word')) return 'docx';
    if (type.contains('sheet') || type.contains('excel')) return 'xlsx';
    if (type.contains('presentation') || type.contains('powerpoint')) {
      return 'pptx';
    }
    if (type.startsWith('image/')) return 'image';
    if (type.startsWith('text/')) return 'txt';
    return _extractFileType(filename);
  }

  static String _formatDate(dynamic date) {
    if (date == null) return 'Unknown';
    try {
      final dateTime = DateTime.parse(date.toString());
      return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year}';
    } catch (e) {
      final dateStr = date.toString();
      if (dateStr.contains('/')) return dateStr;
      return dateStr;
    }
  }
}

class SharedDocumentsService {
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

  Future<SharedDocumentsResponse> fetchSharedDocuments() async {
    try {
      final response = await _dio.get('$_sharesBasePath/shared-with-me');
      if (response.statusCode == 200) {
        Map<String, dynamic> data;
        if (response.data is Map<String, dynamic>) {
          data = response.data as Map<String, dynamic>;
          if (data['documents'] == null && data['items'] is List) {
            data = {'documents': data['items'], 'folders': []};
          } else if (data['documents'] == null &&
              data['data'] is Map<String, dynamic>) {
            final nested = data['data'] as Map<String, dynamic>;
            data = {
              'documents': nested['documents'] ?? nested['items'] ?? [],
              'folders': nested['folders'] ?? [],
            };
          }
        } else if (response.data is List) {
          data = {'documents': response.data, 'folders': []};
        } else {
          data = {'documents': [], 'folders': []};
        }
        return SharedDocumentsResponse.fromJson(data);
      }
      throw Exception('Failed to load shared documents');
    } catch (e) {
      debugPrint('Shared documents error: $e');
      throw Exception('An unexpected error occurred.');
    }
  }

  Future<Map<String, dynamic>> downloadDocument(String documentId) async {
    try {
      final urlResponse = await _dio.get('/documents/$documentId/download-url');
      if (kDebugMode) {
        print('📥 shared download-url status: ${urlResponse.statusCode}');
        print('📥 shared download-url data: ${urlResponse.data}');
      }
      if (urlResponse.statusCode == 200) {
        final urlData = urlResponse.data;
        final url = urlData is Map<String, dynamic> ? urlData['url'] : urlData;
        if (url == null) {
          return {'success': false, 'error': 'Download URL missing'};
        }
        if (kDebugMode) {
          print('📥 shared download-url resolved: $url');
        }
        final response = await _dio.get(
          url.toString(),
          options: Options(responseType: ResponseType.bytes),
        );
        if (kDebugMode) {
          final bytes = response.data is List<int>
              ? response.data as List<int>
              : <int>[];
          final head = bytes.take(16).toList();
          final headAscii = bytes.isNotEmpty
              ? String.fromCharCodes(head.map((b) => b < 32 ? 46 : b))
              : '';
          print('📥 shared file status: ${response.statusCode}');
          print('📥 shared file content-type: ${response.headers.value('content-type')}');
          print('📥 shared file bytes: ${bytes.length}');
          print('📥 shared file head bytes: $head');
          print('📥 shared file head ascii: $headAscii');
        }
        if (response.statusCode == 200) {
          return {
            'success': true,
            'fileData': response.data,
            'filename': _extractFilename(response),
            'contentType': response.headers.value('content-type'),
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
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> getDocumentDetails(String documentId) async {
    try {
      final response = await _dio.get('/documents/$documentId');
      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map<String, dynamic> && data['document'] != null) {
          return {
            'success': true,
            'data': data['document'],
            'message': 'Document details retrieved',
          };
        }
        return {
          'success': true,
          'data': response.data,
          'message': 'Document details retrieved',
        };
      }
      return {
        'success': false,
        'error': 'Failed to get details',
        'message': 'Unable to retrieve document details',
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
        'message': 'Error getting document details',
      };
    }
  }

  Future<Map<String, dynamic>> getDocumentVersions(String documentId) async {
    try {
      final response = await _dio.get('/versions/$documentId');
      if (response.statusCode == 200) {
        final data = response.data;
        List<dynamic> versions = [];
        if (data is Map<String, dynamic>) {
          if (data['versions'] is List) {
            versions = data['versions'];
          } else if (data['items'] is List) {
            versions = data['items'];
          } else if (data['data'] is List) {
            versions = data['data'];
          } else if (data['data'] is Map<String, dynamic> &&
              data['data']['versions'] is List) {
            versions = data['data']['versions'];
          }
        } else if (data is List) {
          versions = data;
        }
        return {
          'success': true,
          'versions': versions,
          'message': 'Document versions retrieved',
        };
      }
      return {
        'success': false,
        'error': 'Failed to get versions',
        'message': 'Unable to retrieve document versions',
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
        'message': 'Error getting document versions',
      };
    }
  }

  Future<bool> isLoggedIn() async {
    final token = await TokenStorage.getAccessToken();
    return token != null && token.isNotEmpty;
  }

  bool get isConnected => true;

  String _extractFilename(Response response) {
    final contentDisposition = response.headers.value('content-disposition');
    if (contentDisposition != null) {
      final match =
          RegExp(r'filename="([^"]+)"').firstMatch(contentDisposition);
      if (match != null) return match.group(1) ?? 'document';
    }
    return 'document';
  }
}
