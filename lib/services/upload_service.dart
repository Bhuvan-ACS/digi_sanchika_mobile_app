import 'dart:io';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http_parser/http_parser.dart';

import 'package:digi_sanchika/services/api_client.dart';

class UploadService {
  static Dio get _dio => ApiClient.instance.dio;

  static bool _isEffectivelyEmptyJsonList(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return true;
    return trimmed == '[]' || trimmed.toLowerCase() == 'null';
  }

  static List<dynamic>? _tryDecodeJsonList(String value) {
    try {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      final decoded = jsonDecode(trimmed);
      return decoded is List ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static Dio _rawDio() {
    // Raw client for presigned S3/MinIO PUTs (no auth interceptors/cookies).
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

  static void _ulog(String message) {
    if (!kDebugMode) return;
    // Keep logs grep-friendly for backend team.
    print('[Upload] $message');
  }

  static String _sanitizePresignedUrl(String url) {
    // Presigned URLs include credentials/signatures in the query string.
    // Keep scheme/host/path and only query keys (values masked).
    try {
      final uri = Uri.parse(url);
      if (uri.queryParameters.isEmpty) return url;
      final keys = uri.queryParameters.keys.toList()..sort();
      final masked = <String, String>{for (final k in keys) k: '***'};
      return uri.replace(queryParameters: masked).toString();
    } catch (_) {
      return url;
    }
  }

  static bool _isSuccessfulPutStatus(int? status) {
    // S3/MinIO typically returns 200 or 204; accept 201 too.
    return status == 200 || status == 201 || status == 204;
  }

  static Future<Response<dynamic>> _putPresignedBytes({
    required String uploadUrl,
    required List<int> bytes,
    required String contentType,
    required String tag,
  }) async {
    final raw = _rawDio();
    final safeUrl = _sanitizePresignedUrl(uploadUrl);
    _ulog(
      '$tag PUT presigned url=$safeUrl bytes=${bytes.length} contentType=$contentType',
    );

    final started = DateTime.now();
    final resp = await raw.put(
      uploadUrl,
      data: bytes,
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'Content-Type': contentType,
          'Content-Length': bytes.length.toString(),
        },
      ),
    );
    final elapsedMs = DateTime.now().difference(started).inMilliseconds;
    _ulog('$tag PUT status=${resp.statusCode} elapsedMs=$elapsedMs');
    return resp;
  }

  static MediaType? _getMediaTypeForFile(File file) {
    final fileName = file.path.split('/').last.toLowerCase();
    final extension = fileName.split('.').last;

    switch (extension) {
      case 'pdf':
        return MediaType('application', 'pdf');
      case 'doc':
        return MediaType('application', 'msword');
      case 'docx':
        return MediaType(
          'application',
          'vnd.openxmlformats-officedocument.wordprocessingml.document',
        );
      case 'xls':
        return MediaType('application', 'vnd.ms-excel');
      case 'xlsx':
        return MediaType(
          'application',
          'vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
      case 'ppt':
        return MediaType('application', 'vnd.ms-powerpoint');
      case 'pptx':
        return MediaType(
          'application',
          'vnd.openxmlformats-officedocument.presentationml.presentation',
        );
      case 'txt':
        return MediaType('text', 'plain');
      case 'csv':
        return MediaType('text', 'csv');
      case 'jpg':
      case 'jpeg':
        return MediaType('image', 'jpeg');
      case 'png':
        return MediaType('image', 'png');
      case 'gif':
        return MediaType('image', 'gif');
      case 'bmp':
        return MediaType('image', 'bmp');
      case 'webp':
        return MediaType('image', 'webp');
      case 'svg':
        return MediaType('image', 'svg+xml');
      case 'tiff':
      case 'tif':
        return MediaType('image', 'tiff');
      case 'ico':
        return MediaType('image', 'x-icon');
      case 'mp3':
        return MediaType('audio', 'mpeg');
      case 'wav':
        return MediaType('audio', 'wav');
      case 'ogg':
        return MediaType('audio', 'ogg');
      case 'm4a':
        return MediaType('audio', 'mp4');
      case 'flac':
        return MediaType('audio', 'flac');
      case 'mp4':
        return MediaType('video', 'mp4');
      case 'avi':
        return MediaType('video', 'x-msvideo');
      case 'mov':
        return MediaType('video', 'quicktime');
      case 'wmv':
        return MediaType('video', 'x-ms-wmv');
      case 'flv':
        return MediaType('video', 'x-flv');
      case 'mkv':
        return MediaType('video', 'x-matroska');
      case 'webm':
        return MediaType('video', 'webm');
      case 'zip':
        return MediaType('application', 'zip');
      case 'rar':
        return MediaType('application', 'x-rar-compressed');
      case '7z':
        return MediaType('application', 'x-7z-compressed');
      case 'tar':
        return MediaType('application', 'x-tar');
      case 'gz':
        return MediaType('application', 'gzip');
      case 'json':
        return MediaType('application', 'json');
      case 'xml':
        return MediaType('application', 'xml');
      default:
        return MediaType('application', 'octet-stream');
    }
  }

  static Map<String, dynamic> _validateFileForUpload(File file) {
    final fileName = file.path.split('/').last;
    final exists = file.existsSync();
    final fileSize = exists ? file.lengthSync() : 0;

    if (!exists) {
      return {'valid': false, 'message': 'File does not exist: $fileName'};
    }
    if (fileSize > 500 * 1024 * 1024) {
      return {'valid': false, 'message': 'File exceeds 500MB limit: $fileName'};
    }

    return {
      'valid': true,
      'fileName': fileName,
      'fileSize': fileSize,
      'mediaType': _getMediaTypeForFile(file),
    };
  }

  static Future<Map<String, dynamic>> uploadSingleFile({
    required File file,
    required String keywords,
    required String remarks,
    required String docClass,
    required bool allowDownload,
    required String sharing,
    required String folderId,
    String specificUsers = '[]',
    String isNewVersion = 'false',
    String existingDocumentId = '',
  }) async {
    final traceId = DateTime.now().microsecondsSinceEpoch.toString();

    try {
      _ulog(
        'trace=$traceId START single file=${file.path} class=$docClass sharing=$sharing folderId=$folderId allowDownload=$allowDownload',
      );

      final validation = _validateFileForUpload(file);
      if (validation['valid'] != true) {
        _ulog('trace=$traceId VALIDATION failed: ${validation['message']}');
        return {'success': false, 'message': validation['message']};
      }

      final fileName = validation['fileName'] as String;
      final fileSize = validation['fileSize'] as int;
      final mediaType = validation['mediaType'] as MediaType?;
      final contentType = mediaType?.mimeType ?? 'application/octet-stream';

      _ulog(
        'trace=$traceId fileName=$fileName size=$fileSize mime=$contentType',
      );

      final keywordList = keywords
          .split(',')
          .map((k) => k.trim())
          .where((k) => k.isNotEmpty)
          .toList();

      final Map<String, dynamic> presignPayload = {
        'fileName': fileName,
        'mimeType': contentType,
        'classification': docClass,
        'classification_level': docClass,
        'classificationLevel': docClass,
        'security_level': docClass,
        'fileSize': fileSize,
        'description': remarks,
        'keywords': keywordList,
        'remarks': remarks,
        'allowDownload': allowDownload,
        'allow_download': allowDownload,
        if (isNewVersion.isNotEmpty) 'isNewVersion': isNewVersion,
        if (isNewVersion.isNotEmpty) 'is_new_version': isNewVersion,
        if (existingDocumentId.isNotEmpty)
          'existingDocumentId': existingDocumentId,
        if (existingDocumentId.isNotEmpty)
          'existing_document_id': existingDocumentId,
      };
      if (folderId.isNotEmpty) {
        presignPayload['folderId'] = folderId;
        presignPayload['folder_id'] = folderId;
      }

      Response presignResponse;
      presignResponse = await _dio.post(
        '/documents/upload-url',
        data: presignPayload,
      );
      _ulog(
        'trace=$traceId POST /documents/upload-url status=${presignResponse.statusCode} data=${presignResponse.data}',
      );

      if (presignResponse.statusCode != 200) {
        return {
          'success': false,
          'message': 'Failed to get upload URL (${presignResponse.statusCode})',
          'statusCode': presignResponse.statusCode,
          'error': presignResponse.data,
        };
      }

      final data = presignResponse.data;
      final uploadUrl =
          (data is Map ? (data['uploadUrl'] ?? data['url']) : null)?.toString();
      final documentId =
          (data is Map ? (data['documentId'] ?? data['id']) : null)?.toString();

      if (uploadUrl == null || uploadUrl.isEmpty) {
        return {'success': false, 'message': 'Upload URL missing'};
      }
      _ulog(
        'trace=$traceId presignedUrl=${_sanitizePresignedUrl(uploadUrl)} documentId=$documentId',
      );

      final bytes = await file.readAsBytes();
      final putResp = await _putPresignedBytes(
        uploadUrl: uploadUrl,
        bytes: bytes,
        contentType: contentType,
        tag: 'trace=$traceId',
      );

      if (!_isSuccessfulPutStatus(putResp.statusCode)) {
        _ulog(
          'trace=$traceId PUT FAILED status=${putResp.statusCode} body=${putResp.data}',
        );
        return {
          'success': false,
          'message': 'Upload failed: PUT ${putResp.statusCode}',
          'statusCode': putResp.statusCode,
          'error': putResp.data,
        };
      }

      if (documentId != null && documentId.isNotEmpty) {
        try {
          final confirm = await _dio.post(
            '/documents/$documentId/confirm-upload',
            data: {'fileSize': fileSize},
          );
          _ulog(
            'trace=$traceId POST /documents/$documentId/confirm-upload status=${confirm.statusCode} data=${confirm.data}',
          );
        } catch (e) {
          _ulog('trace=$traceId WARN confirm-upload failed (non-fatal): $e');
        }
      }

      _ulog('trace=$traceId END success documentId=$documentId');
      return {
        'success': true,
        'message': 'Upload successful',
        'document_id': documentId,
        'file_results': [
          {
            'fileName': fileName,
            'documentId': documentId,
            'success': true,
            'error': null,
          },
        ],
        'uploaded_items': [
          {
            'document_id': documentId,
            'file_name': fileName,
            'original_name': fileName,
          },
        ],
        'data': data,
      };
    } on DioException catch (e) {
      _ulog(
        'trace=$traceId ERROR dio-exception status=${e.response?.statusCode} path=${e.requestOptions.path} msg=${e.message}',
      );
      if (e.response?.data != null)
        _ulog('trace=$traceId ERROR response data=${e.response?.data}');
      return {
        'success': false,
        'message': 'Upload error: ${e.message}',
        'statusCode': e.response?.statusCode,
        'error': e.response?.data,
      };
    } catch (e) {
      _ulog('trace=$traceId ERROR exception: $e');
      return {'success': false, 'message': 'Upload error: $e'};
    }
  }

  static Future<Map<String, dynamic>> uploadMultipleFiles({
    required List<File> files,
    required String keywords,
    required String remarks,
    required String docClass,
    required bool allowDownload,
    required String sharing,
    required String folderId,
    String specificUsers = '[]',
    bool preserveStructure = false,
  }) async {
    final traceId = DateTime.now().microsecondsSinceEpoch.toString();

    try {
      _ulog(
        'trace=$traceId START multi count=${files.length} class=$docClass sharing=$sharing folderId=$folderId allowDownload=$allowDownload',
      );

      final validFiles = <Map<String, dynamic>>[];
      final skippedDetails = <Map<String, String>>[];
      for (final file in files) {
        final validation = _validateFileForUpload(file);
        if (validation['valid'] == true) {
          validFiles.add({
            'file': file,
            'fileName': validation['fileName'],
            'fileSize': validation['fileSize'],
            'mediaType': validation['mediaType'],
          });
        } else {
          _ulog(
            'trace=$traceId SKIP invalid file=${file.path} reason=${validation['message']}',
          );
          skippedDetails.add({
            'file':
                validation['fileName']?.toString() ?? file.path.split('/').last,
            'reason': validation['message']?.toString() ?? 'Invalid file',
          });
        }
      }

      if (validFiles.isEmpty) {
        return {'success': false, 'message': 'No valid files to upload'};
      }

      final keywordList = keywords
          .split(',')
          .map((k) => k.trim())
          .where((k) => k.isNotEmpty)
          .toList();

      final Map<String, dynamic> presignPayload = {
        'files': validFiles
            .map(
              (f) => {
                'fileName': f['fileName'],
                'mimeType':
                    (f['mediaType'] as MediaType?)?.mimeType ??
                    'application/octet-stream',
                'fileSize': f['fileSize'],
              },
            )
            .toList(),
        'classification': docClass,
        'classification_level': docClass,
        'classificationLevel': docClass,
        'security_level': docClass,
        'description': remarks,
        'keywords': keywordList,
        'remarks': remarks,
        'allowDownload': allowDownload,
        'allow_download': allowDownload,
        if (preserveStructure) 'preserveStructure': true,
        if (preserveStructure) 'preserve_structure': true,
      };
      if (folderId.isNotEmpty) {
        presignPayload['folderId'] = folderId;
        presignPayload['folder_id'] = folderId;
      }

      Response presignResponse;
      presignResponse = await _dio.post(
        '/documents/bulk-upload-urls',
        data: presignPayload,
      );
      _ulog(
        'trace=$traceId POST /documents/bulk-upload-urls status=${presignResponse.statusCode}',
      );

      if (presignResponse.statusCode != 200) {
        return {
          'success': false,
          'message':
              'Failed to get upload URLs (${presignResponse.statusCode})',
          'statusCode': presignResponse.statusCode,
          'error': presignResponse.data,
        };
      }

      final data = presignResponse.data;
      // Backend commonly returns: { results:[{fileName, uploadUrl, documentId}], errors:[{fileName,error}] }
      final uploads = data is Map
          ? (data['results'] ??
                data['uploads'] ??
                data['items'] ??
                data['data'] ??
                [])
          : [];
      final serverErrors = data is Map ? (data['errors'] ?? []) : [];

      final uploadsList = uploads is List ? uploads : const [];
      final uploadByName = <String, Map<String, dynamic>>{};
      for (final u in uploadsList) {
        if (u is! Map) continue;
        final um = Map<String, dynamic>.from(u);
        final name = (um['fileName'] ?? um['file_name'] ?? '').toString();
        if (name.isEmpty) continue;
        uploadByName[name] = um;
      }

      final uploadedFiles = <String>[];
      final failedFiles = <String>[];
      final failedDetails = <Map<String, String>>[];
      final fileResults = <Map<String, dynamic>>[];

      for (final s in skippedDetails) {
        failedFiles.add(s['file'] ?? 'unknown');
        failedDetails.add(s);
        fileResults.add({
          'fileName': s['file'],
          'documentId': null,
          'success': false,
          'error': s['reason'],
        });
      }

      if (serverErrors is List) {
        for (final e in serverErrors) {
          if (e is! Map) continue;
          final em = Map<String, dynamic>.from(e);
          final fileName =
              (em['fileName'] ?? em['file_name'] ?? em['file'] ?? '')
                  .toString();
          if (fileName.isEmpty) continue;
          final reason = (em['error'] ?? em['message'] ?? 'Upload not allowed')
              .toString();
          failedFiles.add(fileName);
          failedDetails.add({'file': fileName, 'reason': reason});
          fileResults.add({
            'fileName': fileName,
            'documentId': null,
            'success': false,
            'error': reason,
          });
        }
      }

      for (var i = 0; i < validFiles.length; i++) {
        final fileMeta = validFiles[i];
        final fileName = (fileMeta['fileName'] as String?) ?? 'unknown';

        // Prefer mapping by filename; fall back to index if the server preserves ordering.
        final byName = uploadByName[fileName];
        final byIndex = (uploadsList.length > i && uploadsList[i] is Map)
            ? Map<String, dynamic>.from(uploadsList[i] as Map)
            : null;
        final uploadMeta = byName ?? byIndex;

        final uploadUrl = uploadMeta != null
            ? (uploadMeta['uploadUrl'] ?? uploadMeta['url'])?.toString()
            : null;
        final documentId = uploadMeta != null
            ? (uploadMeta['documentId'] ?? uploadMeta['id'])?.toString()
            : null;

        if (uploadUrl == null || uploadUrl.isEmpty) {
          _ulog(
            'trace=$traceId file=$fileName ERROR missing uploadUrl from bulk metadata',
          );
          failedFiles.add(fileName);
          failedDetails.add({'file': fileName, 'reason': 'Missing upload URL'});
          fileResults.add({
            'fileName': fileName,
            'documentId': documentId,
            'success': false,
            'error': 'Missing upload URL',
          });
          continue;
        }

        try {
          final file = fileMeta['file'] as File;
          final bytes = await file.readAsBytes();
          final contentType =
              (fileMeta['mediaType'] as MediaType?)?.mimeType ??
              'application/octet-stream';

          final putResp = await _putPresignedBytes(
            uploadUrl: uploadUrl,
            bytes: bytes,
            contentType: contentType,
            tag: 'trace=$traceId file=$fileName',
          );

          if (!_isSuccessfulPutStatus(putResp.statusCode)) {
            failedFiles.add(fileName);
            final reason = 'Upload failed (PUT ${putResp.statusCode})';
            failedDetails.add({'file': fileName, 'reason': reason});
            fileResults.add({
              'fileName': fileName,
              'documentId': documentId,
              'success': false,
              'error': reason,
            });
            continue;
          }

          if (documentId != null && documentId.isNotEmpty) {
            try {
              final confirm = await _dio.post(
                '/documents/$documentId/confirm-upload',
                data: {'fileSize': fileMeta['fileSize']},
              );
              _ulog(
                'trace=$traceId POST /documents/$documentId/confirm-upload status=${confirm.statusCode}',
              );
            } catch (e) {
              _ulog(
                'trace=$traceId WARN confirm-upload failed (non-fatal) docId=$documentId err=$e',
              );
            }
          }

          uploadedFiles.add(fileName);
          fileResults.add({
            'fileName': fileName,
            'documentId': documentId,
            'success': true,
            'error': null,
          });
        } catch (e) {
          _ulog('trace=$traceId file=$fileName ERROR upload exception: $e');
          failedFiles.add(fileName);
          failedDetails.add({'file': fileName, 'reason': e.toString()});
          fileResults.add({
            'fileName': fileName,
            'documentId': documentId,
            'success': false,
            'error': e.toString(),
          });
        }
      }

      _ulog(
        'trace=$traceId END multi uploaded=${uploadedFiles.length} failed=${failedFiles.length}',
      );
      return {
        'success': failedFiles.isEmpty,
        'message': failedFiles.isEmpty ? 'Upload successful' : 'Partial upload',
        'uploaded_files': uploadedFiles,
        'failed_files': failedFiles,
        'failed_details': failedDetails,
        'file_results': fileResults,
        'uploaded_items': uploadsList
            .whereType<Map>()
            .map<Map<String, dynamic>>(
              (upload) => {
                'document_id': upload['documentId'] ?? upload['id'],
                'file_name': upload['fileName'] ?? upload['file_name'],
                'original_name': upload['fileName'] ?? upload['file_name'],
              },
            )
            .toList(),
        'data': data,
      };
    } on DioException catch (e) {
      _ulog(
        'trace=$traceId ERROR multi dio-exception status=${e.response?.statusCode} path=${e.requestOptions.path} msg=${e.message}',
      );
      if (e.response?.data != null)
        _ulog('trace=$traceId ERROR response data=${e.response?.data}');
      return {
        'success': false,
        'message': 'Upload error: ${e.message}',
        'statusCode': e.response?.statusCode,
        'error': e.response?.data,
      };
    } catch (e) {
      _ulog('trace=$traceId ERROR multi exception: $e');
      return {'success': false, 'message': 'Upload error: $e'};
    }
  }
}
