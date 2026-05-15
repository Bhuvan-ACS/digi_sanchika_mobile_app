import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:digi_sanchika/services/api_client.dart';
import 'package:digi_sanchika/models/shared_folder.dart';
import 'package:digi_sanchika/models/document.dart';

class SharedFoldersService {
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

  Future<List<SharedFolder>> fetchSharedFolders() async {
    try {
      final response = await _dio.get('$_sharesBasePath/shared-with-me');
      if (response.statusCode == 200) {
        final data = response.data;
        List<dynamic> foldersData = [];
        if (data is Map<String, dynamic>) {
          if (data['folders'] is List) {
            foldersData = data['folders'];
          } else if (data['items'] is List) {
            foldersData = data['items'];
          } else if (data['data'] is Map<String, dynamic> &&
              data['data']['folders'] is List) {
            foldersData = data['data']['folders'];
          }
        }
        return foldersData.map<SharedFolder>((folderJson) {
          final raw = Map<String, dynamic>.from(folderJson as Map);
          final folder =
              raw['folder'] is Map<String, dynamic>
                  ? Map<String, dynamic>.from(raw['folder'])
                  : raw;
          final sharedBy =
              raw['sharedBy'] is Map<String, dynamic>
                  ? Map<String, dynamic>.from(raw['sharedBy'])
                  : null;
          final rawCount = raw['item_count'] ??
              raw['items_count'] ??
              raw['document_count'] ??
              raw['total_files'] ??
              folder['item_count'] ??
              folder['items_count'] ??
              folder['document_count'];
          final itemCount = rawCount is int
              ? rawCount
              : (rawCount != null ? int.tryParse(rawCount.toString()) ?? -1 : -1);
          return SharedFolder(
            id: (folder['id'] ?? 0).toString(),
            name: folder['name']?.toString() ?? 'Unknown Folder',
            owner:
                sharedBy?['full_name']?.toString() ??
                sharedBy?['name']?.toString() ??
                folder['owner']?.toString() ??
                'Unknown User',
            createdAt: folder['created_at']?.toString() ?? '',
            itemCount: itemCount,
          );
        }).toList();
      }
      return [];
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching shared folders: $e');
      }
      return [];
    }
  }

  Future<Map<String, dynamic>> getSharedFolderContents(String folderId) async {
    try {
      final response = await _dio.get(
        '$_sharesBasePath/folders/$folderId/contents',
      );
      if (response.statusCode != 200) {
        return {'success': false, 'error': 'Failed to load shared contents'};
      }
      final data = response.data is Map<String, dynamic>
          ? response.data as Map<String, dynamic>
          : <String, dynamic>{};
      final documents = _mapDocuments(data['documents'] ?? []);
      final subfolders = data['folders'] ?? [];

      return {
        'success': true,
        'documents': documents,
        'folders': subfolders,
        'breadcrumbs': data['breadcrumbs'] ?? [],
        'folder': data['folder'],
        'share': data['share'],
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  List<Document> _mapDocuments(List<dynamic> data) {
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
}
