import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:digi_sanchika/services/api_client.dart';
import 'package:digi_sanchika/models/folder.dart';
import 'package:digi_sanchika/models/document.dart';

class ShareUser {
  final String id;
  final String? name;
  final String? email;
  final String? employeeId;
  final String? department;
  final String? avatarUrl;
  bool isSelected;

  ShareUser({
    required this.id,
    this.name,
    this.email,
    this.employeeId,
    this.department,
    this.avatarUrl,
    this.isSelected = false,
  });

  factory ShareUser.fromJson(Map<String, dynamic> json) {
    return ShareUser(
      id: json['id']?.toString() ?? json['user_id']?.toString() ?? 'unknown',
      name:
          json['name'] ??
          json['username'] ??
          json['full_name'] ??
          json['display_name'] ??
          'Unknown User',
      email: json['email'] ?? json['email_address'],
      employeeId: json['employee_id']?.toString() ?? json['emp_id']?.toString(),
      department: json['department'] ?? json['dept'] ?? json['dept_name'],
      avatarUrl:
          json['avatar_url'] ?? json['profile_picture'] ?? json['avatar'],
    );
  }
}

class FolderService {
  static Dio get _dio => ApiClient.instance.dio;

  static Future<Map<String, dynamic>> getFolderContents(String folderId) async {
    try {
      final response = await _dio.get(
        '/documents',
        queryParameters: {'folderId': folderId},
      );
      if (response.statusCode == 200) {
        final data = response.data;
        final documents = _mapDocuments(data['documents'] ?? data['items'] ?? []);
        final subfolders = _mapFolders(data['folders'] ?? [], folderId);
        return {
          'success': true,
          'documents': documents,
          'subfolders': subfolders,
          'folderName': data['folder_name'] ?? 'Folder',
        };
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error getting folder contents: $e');
      }
    }
    return {'success': false, 'error': 'Failed to load folder contents'};
  }

  static Future<List<ShareUser>> getUsersForSharing() async {
    try {
      Response response;
      try {
        response = await _dio.get('/shares/users');
      } catch (_) {
        response = await _dio.get('/users');
      }

      if (response.statusCode == 200) {
        final data = response.data;
        List<dynamic> usersList = [];
        if (data is List) {
          usersList = data;
        } else if (data is Map<String, dynamic>) {
          usersList =
              data['users'] ??
              data['data'] ??
              data['members'] ??
              data['results'] ??
              [];
        }
        return usersList.map((u) => ShareUser.fromJson(u)).toList();
      }
      return [];
    } catch (e) {
      if (kDebugMode) {
        print('Error getting users: $e');
      }
      return [];
    }
  }

  static Future<Map<String, dynamic>> shareDocument({
    required String documentId,
    required List<String> userIds,
    String permission = 'view',
    String? message,
  }) async {
    try {
      bool allOk = true;
      List<String> errors = [];
      for (final userId in userIds) {
        final response = await _dio.post(
          '/shares/documents/$documentId',
          data: {
            'sharedWithId': userId,
            'permission': permission,
            if (message != null) 'message': message,
          },
        );
        if (response.statusCode != 200 && response.statusCode != 201) {
          allOk = false;
          errors.add('User $userId -> ${response.statusCode}');
        }
      }
      return {
        'success': allOk,
        'message':
            allOk ? 'Document shared successfully' : 'Some shares failed',
        if (errors.isNotEmpty) 'errors': errors,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error sharing document',
        'error': e.toString(),
      };
    }
  }

  static Future<List<ShareUser>> getDocumentSharedUsers(
    String documentId,
  ) async {
    try {
      final response = await _dio.get('/shares/documents/$documentId');
      if (response.statusCode == 200) {
        final data = response.data;
        List<dynamic> usersList = [];
        if (data is List) {
          usersList = data;
        } else if (data is Map<String, dynamic>) {
          usersList =
              data['shared_with'] ??
              data['users'] ??
              data['items'] ??
              [];
        }
        return usersList.map((u) => ShareUser.fromJson(u)).toList();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error getting shared users: $e');
      }
    }
    return [];
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
        owner:
            map['owner']?['name']?.toString() ??
            map['owner']?.toString() ??
            'Unknown',
        details: map['remarks']?.toString() ?? '',
        classification:
            map['classification']?.toString() ??
            map['doc_class']?.toString() ??
            'internal',
        allowDownload: map['allow_download'] ?? true,
        sharingType: map['is_public'] == true ? 'Public' : 'Private',
        folder: map['folder_path']?.toString() ?? 'Home',
        folderId: map['folder_id']?.toString(),
        path: filename.toString(),
        fileType: fileType,
      );
    }).toList();
  }

  static List<Folder> _mapFolders(List<dynamic> data, String? parentId) {
    return data.map((folder) {
      final map = Map<String, dynamic>.from(folder);
      return Folder(
        name: map['name']?.toString() ?? 'Unnamed',
        id: map['id'].toString(),
        owner: map['owner']?.toString() ?? 'User',
        documents: [],
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
            DateTime.now(),
        parentId: parentId,
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
