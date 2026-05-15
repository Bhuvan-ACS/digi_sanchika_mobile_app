import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:digi_sanchika/services/api_client.dart';
import 'package:digi_sanchika/services/download_requests_service.dart';
import 'package:digi_sanchika/services/download_access_service.dart';

class FolderDownloadService {
  Dio get _dio => ApiClient.instance.dio;

  void _fdlog(String message) {
    if (!kDebugMode) return;
    print('[FolderDownload] $message');
  }

  String _apiPrefix() {
    // If baseUrl already ends with /api, don't prepend /api again.
    // Example baseUrl: https://host/api  -> prefix ""
    // Example baseUrl: https://host     -> prefix "/api"
    final base = Uri.tryParse(ApiClient.instance.baseUrl);
    final rawPath = (base?.path ?? '').trim();
    final normalized = rawPath.replaceAll(RegExp(r'/+$'), '');
    return normalized.endsWith('/api') ? '' : '/api';
  }

  Future<Response<dynamic>> _getFolderEndpoint(String folderId, String tail) {
    final path = '${_apiPrefix()}/folders/$folderId/$tail';
    _fdlog('GET $path (baseUrl=${ApiClient.instance.baseUrl})');
    return _dio.get(path);
  }

  Future<Response<List<int>>> _fetchBytesFromUrl(String url) async {
    final options = Options(responseType: ResponseType.bytes);
    final uri = Uri.tryParse(url);

    // Relative URL (or invalid) -> use authenticated dio against baseUrl.
    if (uri == null || !uri.hasScheme) {
      return _dio.get<List<int>>(url, options: options);
    }

    // Absolute URL: prefer unauthenticated raw client (S3/MinIO presigned),
    // but if it's pointing to our API host it may require bearer/cookies.
    final base = Uri.tryParse(ApiClient.instance.baseUrl);
    final sameHost = base != null &&
        base.host.isNotEmpty &&
        base.host == uri.host &&
        (base.scheme == uri.scheme || base.scheme.isEmpty);

    if (sameHost) {
      final resp = await _dio.get<List<int>>(url, options: options);
      // If auth still not allowed, fall back to raw (some backends allow it).
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        final raw = _rawDio();
        return raw.get<List<int>>(url, options: options);
      }
      return resp;
    }

    final raw = _rawDio();
    return raw.get<List<int>>(url, options: options);
  }

  Dio _rawDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(minutes: 2),
        sendTimeout: const Duration(minutes: 2),
        followRedirects: true,
        validateStatus: (s) => s != null && s < 600,
      ),
    );
  }

  String _safeName(String name) {
    final trimmed = name.trim().isEmpty ? 'folder' : name.trim();
    return trimmed.replaceAll(RegExp(r'[^\w\.\- ]+'), '_');
  }

  Future<Directory> _downloadBaseDir() async {
    // Keep consistent with current app behavior: application docs dir.
    return getApplicationDocumentsDirectory();
  }

  Future<File> _zipDirectory({
    required Directory directory,
    required String zipFileName,
  }) async {
    final base = await _downloadBaseDir();
    final safe = _safeName(zipFileName.endsWith('.zip') ? zipFileName : '$zipFileName.zip');
    final zipPath = p.join(base.path, safe);
    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    encoder.addDirectory(directory);
    encoder.close();
    return File(zipPath);
  }

  Future<List<Map<String, dynamic>>> _listSubfolders(String folderId) async {
    try {
      final resp = await _dio.get(
        '/folders',
        queryParameters: {'parentId': folderId},
      );
      if (resp.statusCode != 200) return const [];
      final data = resp.data;
      final raw = data is List
          ? data
          : (data is Map ? (data['folders'] ?? data['items'] ?? []) : []);
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> _listDocuments(String folderId) async {
    try {
      final resp = await _dio.get(
        '/documents',
        queryParameters: {'folderId': folderId},
      );
      if (resp.statusCode != 200) return const [];
      final data = resp.data;
      final raw = data is List
          ? data
          : (data is Map ? (data['documents'] ?? data['items'] ?? data['data'] ?? []) : []);
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<Map<String, dynamic>> _downloadFolderRecursively({
    required String folderId,
    required String folderName,
  }) async {
    final base = await _downloadBaseDir();
    final rootDirName = _safeName(folderName);
    final rootDir = Directory(p.join(base.path, rootDirName));
    if (!await rootDir.exists()) {
      await rootDir.create(recursive: true);
    }

    int downloaded = 0;
    int failed = 0;

    Future<void> walk(String currentFolderId, String relPath) async {
      final folders = await _listSubfolders(currentFolderId);
      final docs = await _listDocuments(currentFolderId);

      for (final doc in docs) {
        final docId = (doc['id'] ?? doc['documentId'] ?? doc['document_id'])?.toString() ?? '';
        if (docId.isEmpty) continue;
        final name = (doc['name'] ??
                doc['original_filename'] ??
                doc['file_name'] ??
                'document')
            .toString();
        final safeFileName = _safeName(name);

        try {
          final res = await DownloadAccessService.downloadBytesWithAccess(
            documentId: docId,
          );
          if (res['success'] == true && res['bytes'] is List<int>) {
            final outFilePath = p.join(rootDir.path, relPath, safeFileName);
            final outDir = Directory(p.dirname(outFilePath));
            if (!await outDir.exists()) {
              await outDir.create(recursive: true);
            }
            await File(outFilePath).writeAsBytes(res['bytes'] as List<int>, flush: true);
            downloaded += 1;
          } else {
            failed += 1;
          }
        } catch (_) {
          failed += 1;
        }
      }

      for (final f in folders) {
        final id = (f['id'] ?? f['folderId'] ?? f['folder_id'])?.toString() ?? '';
        if (id.isEmpty) continue;
        final name = (f['name'] ?? 'Folder').toString();
        final nextRel = p.join(relPath, _safeName(name));
        await walk(id, nextRel);
      }
    }

    await walk(folderId, '');

    if (downloaded == 0) {
      return {
        'success': false,
        'error': 'Failed to download folder',
        'downloaded': downloaded,
        'failed': failed,
      };
    }

    return {
      'success': true,
      'folderPath': rootDir.path,
      'rootName': rootDirName,
      'downloaded': downloaded,
      'failed': failed,
    };
  }

  Future<Map<String, dynamic>> _getZipUrl(String folderId) async {
    try {
      final resp = await _getFolderEndpoint(folderId, 'download-url');
      if (resp.statusCode == 200) {
        final data = resp.data is Map ? Map<String, dynamic>.from(resp.data) : {};
        final url = data['url']?.toString();
        final fileName =
            data['fileName']?.toString() ?? data['filename']?.toString();
        if (url == null || url.isEmpty) {
          return {'success': false, 'error': 'Missing download url'};
        }
        return {
          'success': true,
          'url': url,
          'fileName': fileName,
        };
      }

      if (resp.statusCode == 403) {
        final data = resp.data is Map ? Map<String, dynamic>.from(resp.data) : {};
        final requiresApproval = data['requiresApproval'] == true;
        return {
          'success': false,
          'requiresApproval': requiresApproval,
          'error': data['error']?.toString() ?? 'Access denied',
          'fileName': data['fileName']?.toString(),
        };
      }

      if (resp.statusCode == 401) {
        return {'success': false, 'error': 'Authentication required'};
      }

      // If backend doesn't implement folder download endpoints, fall back to client-side behavior.
      if (resp.statusCode == 404) {
        return {
          'success': false,
          'notSupported': true,
          'error': 'Folder zip endpoint not supported (404)',
          'statusCode': resp.statusCode,
          'data': resp.data,
        };
      }

      String? serverMsg;
      if (resp.data is Map) {
        final map = Map<String, dynamic>.from(resp.data as Map);
        serverMsg =
            (map['error'] ?? map['message'] ?? map['detail'])?.toString();
      }
      _fdlog('download-url failed status=${resp.statusCode} data=${resp.data}');
      return {
        'success': false,
        'error': serverMsg != null && serverMsg.isNotEmpty
            ? 'Failed to get download url (${resp.statusCode}): $serverMsg'
            : 'Failed to get download url (${resp.statusCode})',
        'statusCode': resp.statusCode,
        'data': resp.data,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _getManifest(String folderId) async {
    try {
      final resp = await _getFolderEndpoint(folderId, 'download-manifest');
      if (resp.statusCode == 200) {
        final data = resp.data is Map ? Map<String, dynamic>.from(resp.data) : {};
        return {
          'success': true,
          'data': data,
        };
      }

      if (resp.statusCode == 403) {
        final data = resp.data is Map ? Map<String, dynamic>.from(resp.data) : {};
        final requiresApproval = data['requiresApproval'] == true;
        return {
          'success': false,
          'requiresApproval': requiresApproval,
          'error': data['error']?.toString() ?? 'Access denied',
          'rootName': data['rootName']?.toString(),
        };
      }

      if (resp.statusCode == 401) {
        return {'success': false, 'error': 'Authentication required'};
      }

      if (resp.statusCode == 404) {
        return {
          'success': false,
          'notSupported': true,
          'error': 'Folder manifest endpoint not supported (404)',
          'statusCode': resp.statusCode,
          'data': resp.data,
        };
      }

      String? serverMsg;
      if (resp.data is Map) {
        final map = Map<String, dynamic>.from(resp.data as Map);
        serverMsg =
            (map['error'] ?? map['message'] ?? map['detail'])?.toString();
      }
      _fdlog('manifest failed status=${resp.statusCode} data=${resp.data}');
      return {
        'success': false,
        'error': serverMsg != null && serverMsg.isNotEmpty
            ? 'Failed to get manifest (${resp.statusCode}): $serverMsg'
            : 'Failed to get manifest (${resp.statusCode})',
        'statusCode': resp.statusCode,
        'data': resp.data,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>?> _redeemApprovedFolderRequestIfAny(
    String folderId, {
    String? mode,
  }) async {
    try {
      final req = DownloadRequestsService();
      final mine = await req.myRequests();
      final approved = mine.where((r) {
        final type = (r.targetType ?? '').toLowerCase();
        return (type == 'folder' || r.folderId?.isNotEmpty == true) &&
            r.folderId == folderId &&
            r.status.toLowerCase() == 'approved';
      }).toList();
      if (approved.isEmpty) return null;
      final latest = approved.first;
      final used = await req.useTokenAuthenticated(latest.id, mode: mode);
      if (used['success'] == true && used['data'] is Map) {
        return Map<String, dynamic>.from(used['data'] as Map);
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>> _downloadZipFromUrl({
    required String url,
    required String fileName,
  }) async {
    try {
      final resp = await _fetchBytesFromUrl(url);
      if (resp.statusCode != 200 && resp.statusCode != 201) {
        return {
          'success': false,
          'error': 'Download failed (${resp.statusCode})',
        };
      }

      final bytes = resp.data;
      if (bytes == null || bytes.isEmpty) {
        return {'success': false, 'error': 'Downloaded zip is empty'};
      }

      final base = await _downloadBaseDir();
      final safe = _safeName(fileName.isEmpty ? 'folder.zip' : fileName);
      final filePath = p.join(base.path, safe);
      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);

      return {'success': true, 'filePath': filePath, 'filename': safe};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _downloadFromManifest(Map<String, dynamic> data) async {
    final rootName = (data['rootName'] ?? data['fileName'] ?? 'Folder').toString();
    final filesRaw = data['files'];
    final files = filesRaw is List ? filesRaw : const [];

    if (files.isEmpty) {
      return {'success': false, 'error': 'No files in folder'};
    }

    final base = await _downloadBaseDir();
    final rootDirName = _safeName(rootName);
    final rootDir = Directory(p.join(base.path, rootDirName));
    if (!await rootDir.exists()) {
      await rootDir.create(recursive: true);
    }

    int downloaded = 0;
    int failed = 0;

    for (final f in files) {
      if (f is! Map) continue;
      final map = Map<String, dynamic>.from(f);
      final relPath = (map['path'] ?? map['name'] ?? '').toString();
      final url = map['url']?.toString();
      if (url == null || url.isEmpty) continue;

      final normalized = relPath.replaceAll('\\', '/');
      final outPath = normalized.isEmpty
          ? _safeName(map['documentId']?.toString() ?? 'file')
          : normalized;

      final outFilePath = p.joinAll([rootDir.path, ...p.split(outPath)]);
      final outDir = Directory(p.dirname(outFilePath));
      if (!await outDir.exists()) {
        await outDir.create(recursive: true);
      }

      try {
        final resp = await _fetchBytesFromUrl(url);
        if (resp.statusCode == 200 || resp.statusCode == 201) {
          final bytes = resp.data;
          if (bytes != null && bytes.isNotEmpty) {
            await File(outFilePath).writeAsBytes(bytes, flush: true);
            downloaded += 1;
          } else {
            failed += 1;
          }
        } else {
          failed += 1;
        }
      } catch (e) {
        failed += 1;
        if (kDebugMode) {
          print('Folder download file failed: $e');
        }
      }
    }

    if (downloaded == 0) {
      return {
        'success': false,
        'error': 'Failed to download folder files',
        'downloaded': downloaded,
        'failed': failed,
      };
    }

    return {
      'success': true,
      'folderPath': rootDir.path,
      'rootName': rootDirName,
      'downloaded': downloaded,
      'failed': failed,
    };
  }

  Future<Map<String, dynamic>> downloadFolderAsZipWithAccess({
    required String folderId,
    String reason = 'Need offline copy',
    String? folderNameHint,
  }) async {
    final zip = await _getZipUrl(folderId);
    if (zip['success'] == true) {
      return _downloadZipFromUrl(
        url: zip['url'] as String,
        fileName: (zip['fileName'] ?? 'Folder.zip').toString(),
      );
    }

    if (zip['notSupported'] == true || zip['statusCode'] == 404) {
      // Backend doesn't support folder zip endpoint -> download folder contents and zip locally.
      final files = await downloadFolderFilesWithAccess(
        folderId: folderId,
        reason: reason,
        folderNameHint: folderNameHint,
      );
      if (files['success'] == true && files['folderPath'] != null) {
        final dir = Directory(files['folderPath'].toString());
        final root = (files['rootName'] ?? folderNameHint ?? 'Folder').toString();
        final zipFile = await _zipDirectory(directory: dir, zipFileName: '$root.zip');
        return {
          'success': true,
          'filePath': zipFile.path,
          'filename': p.basename(zipFile.path),
          'downloaded': files['downloaded'],
          'failed': files['failed'],
          'clientSideZip': true,
        };
      }
      return files;
    }

    if (zip['requiresApproval'] == true) {
      final redeemed = await _redeemApprovedFolderRequestIfAny(folderId, mode: 'zip');
      if (redeemed != null) {
        // Approved via token. Backend may return either a zip url or a manifest.
        final url = redeemed['downloadUrl'] ?? redeemed['download_url'] ?? redeemed['url'];
        if (url != null) {
          return _downloadZipFromUrl(
            url: url.toString(),
            fileName: (redeemed['fileName'] ?? redeemed['filename'] ?? 'Folder.zip')
                .toString(),
          );
        }
        return _downloadFromManifest(redeemed);
      }

      final req = DownloadRequestsService();
      final res = await req.createRequest(
        folderId: folderId,
        reason: reason,
      );
      return {
        'success': false,
        'requiresApproval': true,
        'requestCreated': res['success'] == true,
        'message': res['message'],
      };
    }

    return {'success': false, 'error': zip['error']?.toString()};
  }

  Future<Map<String, dynamic>> downloadFolderFilesWithAccess({
    required String folderId,
    String reason = 'Need offline copy',
    String? folderNameHint,
  }) async {
    final manifest = await _getManifest(folderId);
    if (manifest['success'] == true) {
      return _downloadFromManifest(
        Map<String, dynamic>.from(manifest['data'] as Map),
      );
    }

    if (manifest['notSupported'] == true || manifest['statusCode'] == 404) {
      // Backend doesn't support manifest endpoint -> fall back to recursive listing + per-doc downloads.
      final name = folderNameHint ?? 'Folder';
      return _downloadFolderRecursively(folderId: folderId, folderName: name);
    }

    if (manifest['requiresApproval'] == true) {
      final redeemed = await _redeemApprovedFolderRequestIfAny(folderId);
      if (redeemed != null) {
        return _downloadFromManifest(redeemed);
      }

      final req = DownloadRequestsService();
      final res = await req.createRequest(
        folderId: folderId,
        reason: reason,
      );
      return {
        'success': false,
        'requiresApproval': true,
        'requestCreated': res['success'] == true,
        'message': res['message'],
      };
    }

    return {'success': false, 'error': manifest['error']?.toString()};
  }
}
