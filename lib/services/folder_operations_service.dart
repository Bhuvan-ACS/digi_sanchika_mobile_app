import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:digi_sanchika/services/api_client.dart';
import 'package:digi_sanchika/models/folder_tree_node.dart';

class FolderOperationsService {
  static final FolderOperationsService _instance =
      FolderOperationsService._internal();
  factory FolderOperationsService() => _instance;
  FolderOperationsService._internal();

  Dio get _dio => ApiClient.instance.dio;

  Future<Map<String, dynamic>> createFolder({
    required String name,
    String? parentId,
  }) async {
    try {
      final validation = validateFolderName(name);
      if (!validation['valid']) {
        return {'success': false, 'error': validation['error']};
      }

      final response = await _dio.post(
        '/folders',
        data: {
          'name': name,
          'parentId': parentId,
          'parent_id': parentId,
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data is Map<String, dynamic>
            ? Map<String, dynamic>.from(response.data as Map)
            : <String, dynamic>{};

        final dynamic folderObj = data['folder'] is Map
            ? Map<String, dynamic>.from(data['folder'] as Map)
            : null;
        final dynamic id = data['id'] ??
            data['folder_id'] ??
            (folderObj is Map ? folderObj['id'] : null);
        return {
          'success': true,
          'message': data['message'] ?? 'Folder created successfully',
          'folder_id': id,
          'folder': FolderTreeNode(
            id: id?.toString() ?? '',
            name: name,
            parentId: parentId,
            createdAt: DateTime.now(),
            owner: data['owner']?.toString() ?? 'Current User',
          ),
        };
      }
      return {
        'success': false,
        'error': 'Failed to create folder (${response.statusCode})',
      };
    } catch (e) {
      if (kDebugMode) {
        print('Error creating folder: $e');
      }
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteFolder(String folderId) async {
    try {
      final response = await _dio.delete('/folders/$folderId');
      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': 'Folder deleted successfully',
        };
      }
      return {
        'success': false,
        'error': 'Failed to delete folder (${response.statusCode})',
      };
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting folder: $e');
      }
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  Future<Map<String, dynamic>> getFolderInfo(String folderId) async {
    try {
      final response = await _dio.get('/folders/$folderId');
      if (response.statusCode == 200) {
        return {'success': true, 'folder': response.data};
      }
      return {'success': false, 'error': 'Failed to get folder info'};
    } catch (e) {
      if (kDebugMode) {
        print('Error getting folder info: $e');
      }
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> bulkCreateFolders(
    List<Map<String, dynamic>> folders,
  ) async {
    try {
      final response = await _dio.post(
        '/folders/bulk',
        data: {'folders': folders},
      );
      if (response.statusCode == 200) {
        return {
          'success': true,
          'data': response.data,
        };
      }
      return {
        'success': false,
        'error': 'Bulk create failed (${response.statusCode})',
      };
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  Map<String, dynamic> validateFolderName(String name) {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      return {'valid': false, 'error': 'Folder name cannot be empty'};
    }
    if (trimmedName.length > 100) {
      return {'valid': false, 'error': 'Folder name too long (max 100)'};
    }
    final invalidChars = RegExp(r'[<>:"/\\|?*]');
    if (invalidChars.hasMatch(trimmedName)) {
      return {'valid': false, 'error': 'Folder name contains invalid characters'};
    }
    return {'valid': true, 'cleanName': trimmedName};
  }
}
