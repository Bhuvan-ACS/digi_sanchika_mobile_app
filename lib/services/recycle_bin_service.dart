import 'package:dio/dio.dart';
import 'package:digi_sanchika/services/api_client.dart';
import 'package:digi_sanchika/models/recycle_bin_item.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';

class RecycleBinService {
  Dio get _dio => ApiClient.instance.dio;

  String _normalizeEntityType(String type) {
    final t = type.trim().toLowerCase();
    if (t.contains('folder')) return 'folder';
    if (t.contains('document')) return 'document';
    if (t.isEmpty) return 'document';
    return t;
  }

  String _stripHtml(String html) {
    // Extract content from <pre> if present (common for Express error pages).
    final pre = RegExp(
      r'<pre>([\s\S]*?)</pre>',
      caseSensitive: false,
    ).firstMatch(html);
    if (pre != null) {
      return pre.group(1)?.replaceAll(RegExp(r'<[^>]+>'), '').trim() ?? '';
    }

    // Extract <title> if present.
    final title = RegExp(
      r'<title>([\s\S]*?)</title>',
      caseSensitive: false,
    ).firstMatch(html);
    if (title != null) {
      final t = title.group(1)?.replaceAll(RegExp(r'<[^>]+>'), '').trim() ?? '';
      if (t.isNotEmpty) return t;
    }

    // Fallback: remove tags and compress whitespace.
    return html
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String? _messageFromResponseData(dynamic data) {
    if (data == null) return null;

    if (data is String) {
      final s = data.trim();
      if (s.isEmpty) return null;
      final lower = s.toLowerCase();
      if (lower.contains('<!doctype html') || lower.contains('<html')) {
        final stripped = _stripHtml(s);
        return stripped.isEmpty
            ? 'Server returned an HTML error page'
            : stripped;
      }
      return s;
    }

    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final msg =
          map['message']?.toString() ??
          map['error']?.toString() ??
          map['detail']?.toString() ??
          map['errors']?.toString();
      final m = msg?.trim();
      return (m == null || m.isEmpty) ? null : m;
    }

    return data.toString();
  }

  Future<Map<String, dynamic>> _requestOk({
    required String method,
    required String path,
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final resp = await _dio.request(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(
          method: method,
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      final d = resp.data;
      final isHttpOk =
          resp.statusCode == 200 ||
          resp.statusCode == 201 ||
          resp.statusCode == 202 ||
          resp.statusCode == 204;

      // Some backends return HTTP 200 but carry failure in the payload.
      if (isHttpOk && d is Map) {
        final map = Map<String, dynamic>.from(d);
        final success = map['success'];
        final ok = map['ok'];
        final status = map['status']?.toString().toLowerCase();
        final hasError =
            (map['error']?.toString().trim().isNotEmpty == true) ||
            (map['errors']?.toString().trim().isNotEmpty == true);

        if (success == false ||
            ok == false ||
            status == 'error' ||
            status == 'failed' ||
            hasError) {
          final msg = map['message']?.toString() ?? map['error']?.toString();
          return {
            'success': false,
            'message': msg ?? 'Request failed (${resp.statusCode})',
            'statusCode': resp.statusCode,
            'data': map,
          };
        }
      }

      if (isHttpOk) {
        return {
          'success': true,
          'statusCode': resp.statusCode,
          'method': method,
          'path': path,
          if (queryParameters != null && queryParameters.isNotEmpty)
            'queryParameters': queryParameters,
          if (d != null) 'data': d,
        };
      }

      final msg = d is Map<String, dynamic>
          ? (d['message']?.toString() ??
                d['error']?.toString() ??
                d['detail']?.toString())
          : _messageFromResponseData(d);
      return {
        'success': false,
        'message': msg ?? 'Request failed (${resp.statusCode})',
        'statusCode': resp.statusCode,
        'method': method,
        'path': path,
        if (queryParameters != null && queryParameters.isNotEmpty)
          'queryParameters': queryParameters,
      };
    } catch (e) {
      return {
        'success': false,
        'message': e.toString(),
        'method': method,
        'path': path,
        if (queryParameters != null && queryParameters.isNotEmpty)
          'queryParameters': queryParameters,
      };
    }
  }

  bool _stillInBin(
    List<RecycleBinItem> items, {
    required String entityId,
    String? recordId,
  }) {
    final rid = recordId?.trim() ?? '';
    if (rid.isNotEmpty) {
      return items.any((i) => (i.recordId ?? '').trim() == rid);
    }
    return items.any((i) => i.entityId.trim() == entityId.trim());
  }

  Future<List<RecycleBinItem>> listRecycleBin() async {
    List<dynamic> extractList(dynamic data) {
      if (data == null) return const [];

      if (data is String) {
        try {
          final decoded = jsonDecode(data);
          return extractList(decoded);
        } catch (_) {
          return const [];
        }
      }

      if (data is List) return data;

      if (data is Map) {
        // New contract: { documents: [...], folders: [...] }
        final docs = data['documents'];
        final folders = data['folders'];
        if (docs is List || folders is List) {
          final merged = <dynamic>[];
          if (docs is List) {
            for (final d in docs) {
              if (d is Map) {
                merged.add({
                  ...Map<String, dynamic>.from(d),
                  'entityType': 'document',
                  'entityId': (d['id'] ?? d['document_id'] ?? d['documentId'])
                      ?.toString(),
                });
              } else {
                merged.add(d);
              }
            }
          }
          if (folders is List) {
            for (final f in folders) {
              if (f is Map) {
                merged.add({
                  ...Map<String, dynamic>.from(f),
                  'entityType': 'folder',
                  'entityId': (f['id'] ?? f['folder_id'] ?? f['folderId'])
                      ?.toString(),
                });
              } else {
                merged.add(f);
              }
            }
          }
          if (merged.isNotEmpty) return merged;
        }

        dynamic pick(dynamic v) => v;

        const preferredKeys = [
          'items',
          'results',
          'data',
          'recycleBin',
          'recycle_bin',
          'recyclebin',
          'bin',
          'trash',
          'deleted',
          'documents',
          'folders',
        ];

        for (final k in preferredKeys) {
          final v = pick(data[k]);
          if (v is List) return v;
        }

        // Some APIs nest payloads: { success: true, data: { items: [] } }
        for (final k in preferredKeys) {
          final v = pick(data[k]);
          if (v is Map) {
            final inner = extractList(v);
            if (inner.isNotEmpty) return inner;
          }
        }

        // As a last resort, find the first list anywhere (depth-limited).
        for (final entry in data.entries) {
          final v = entry.value;
          if (v is List) return v;
          if (v is Map) {
            final inner = extractList(v);
            if (inner.isNotEmpty) return inner;
          }
        }
      }

      return const [];
    }

    Future<List<RecycleBinItem>> fetch(
      String path, {
      Map<String, dynamic>? queryParameters,
    }) async {
      final response = await _dio.get(
        path,
        queryParameters: queryParameters,
        options: Options(validateStatus: (s) => s != null && s < 500),
      );
      if (response.statusCode == 200) {
        final rawItems = extractList(response.data);
        final mapped = <RecycleBinItem>[];
        for (final i in rawItems) {
          if (i is Map<String, dynamic>) {
            mapped.add(RecycleBinItem.fromJson(i));
          } else if (i is Map) {
            mapped.add(RecycleBinItem.fromJson(Map<String, dynamic>.from(i)));
          }
        }
        return mapped.where((e) => e.entityId.isNotEmpty).toList();
      }
      return [];
    }

    // Original backend contract:
    // GET /api/recycle-bin?scope=mine|all
    final mine = await fetch(
      '/recycle-bin',
      queryParameters: {'scope': 'mine'},
    );
    if (mine.isNotEmpty) return mine;

    final all = await fetch('/recycle-bin', queryParameters: {'scope': 'all'});
    if (all.isNotEmpty) return all;

    // Some backends ignore scope; try unscoped as a final fallback.
    final unscoped = await fetch('/recycle-bin');
    if (unscoped.isNotEmpty) return unscoped;

    if (kDebugMode) {
      debugPrint(
        'RecycleBinService: no items returned from any known endpoint',
      );
    }
    return const [];
  }

  /// Move an entity to recycle bin (soft delete).
  ///
  /// Tries multiple backend shapes/paths to be compatible with older deployments.
  Future<Map<String, dynamic>> moveToRecycleBin({
    required String entityType,
    required String entityId,
  }) async {
    final payloadCamel = {'entityType': entityType, 'entityId': entityId};
    final payloadSnake = {'entity_type': entityType, 'entity_id': entityId};

    String? lastMessage;
    int? lastStatus;

    Future<bool> attempt({
      required String method,
      required String path,
      Map<String, dynamic>? data,
      Map<String, dynamic>? queryParameters,
    }) async {
      try {
        final resp = await _dio.request(
          path,
          data: data,
          queryParameters: queryParameters,
          options: Options(
            method: method,
            validateStatus: (s) => s != null && s < 500,
          ),
        );
        lastStatus = resp.statusCode;
        final d = resp.data;
        lastMessage = d is Map<String, dynamic>
            ? (d['message']?.toString() ?? d['error']?.toString())
            : null;
        return resp.statusCode == 200 ||
            resp.statusCode == 201 ||
            resp.statusCode == 204;
      } catch (e) {
        lastMessage = e.toString();
        return false;
      }
    }

    final attempts = <Future<bool>>[
      // Common patterns (POST)
      attempt(method: 'POST', path: '/recycle-bin', data: payloadCamel),
      attempt(method: 'POST', path: '/recycle-bin', data: payloadSnake),
      attempt(method: 'POST', path: '/recycle-bin/move', data: payloadCamel),
      attempt(method: 'POST', path: '/recycle-bin/move', data: payloadSnake),
      attempt(method: 'POST', path: '/recycle-bin/trash', data: payloadCamel),
      attempt(method: 'POST', path: '/recycle-bin/trash', data: payloadSnake),

      // Some APIs use query params instead of body
      attempt(
        method: 'POST',
        path: '/recycle-bin/move',
        queryParameters: payloadCamel,
      ),

      // PUT/PATCH variants
      attempt(method: 'PUT', path: '/recycle-bin', data: payloadCamel),
      attempt(method: 'PUT', path: '/recycle-bin', data: payloadSnake),
      attempt(method: 'PATCH', path: '/recycle-bin', data: payloadCamel),
      attempt(method: 'PATCH', path: '/recycle-bin', data: payloadSnake),

      // Legacy patterns (no dash)
      attempt(method: 'POST', path: '/recyclebin', data: payloadCamel),
      attempt(method: 'POST', path: '/recyclebin', data: payloadSnake),
      attempt(method: 'POST', path: '/recyclebin/move', data: payloadCamel),
      attempt(method: 'POST', path: '/recyclebin/move', data: payloadSnake),

      // Very legacy: generic trash route
      attempt(method: 'POST', path: '/trash', data: payloadCamel),
      attempt(method: 'POST', path: '/trash', data: payloadSnake),
      attempt(method: 'POST', path: '/trash/move', data: payloadCamel),
      attempt(method: 'POST', path: '/trash/move', data: payloadSnake),
    ];

    for (final f in attempts) {
      final ok = await f;
      if (ok) return {'success': true};
    }

    final msg =
        lastMessage ??
        (lastStatus != null
            ? 'Move to recycle bin failed ($lastStatus)'
            : 'Move to recycle bin failed');
    return {'success': false, 'message': msg};
  }

  /// Move to recycle bin via document delete as a compatibility fallback.
  ///
  /// Some backends implement soft-delete on `DELETE /documents/:id` and derive
  /// recycle bin list from that, rather than exposing a dedicated move endpoint.
  Future<Map<String, dynamic>> moveToRecycleBinViaDocumentDelete({
    required String documentId,
  }) async {
    try {
      final resp = await _dio.delete(
        '/documents/$documentId',
        options: Options(validateStatus: (s) => s != null && s < 500),
      );
      if (resp.statusCode == 200 || resp.statusCode == 204) {
        return {'success': true};
      }
      final d = resp.data;
      final msg = d is Map<String, dynamic>
          ? (d['message']?.toString() ?? d['error']?.toString())
          : null;
      return {
        'success': false,
        'message': msg ?? 'Delete failed (${resp.statusCode})',
      };
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<bool> restoreItem({
    required String entityType,
    required String entityId,
  }) async {
    final result = await restoreItemFlexible(
      entityType: entityType,
      entityId: entityId,
    );
    return result['success'] == true;
  }

  Future<bool> deletePermanently({
    required String entityType,
    required String entityId,
  }) async {
    final result = await deletePermanentlyFlexible(
      entityType: entityType,
      entityId: entityId,
    );
    return result['success'] == true;
  }

  Future<Map<String, dynamic>> restoreItemFlexible({
    required String entityType,
    required String entityId,
    String? recordId,
  }) async {
    final normalizedType = _normalizeEntityType(entityType);
    final idCandidates = <String>{
      if (recordId != null && recordId.trim().isNotEmpty) recordId.trim(),
      entityId,
    }.toList();

    Map<String, dynamic>? lastFailure;

    // Original backend contract:
    // POST /api/recycle-bin/restore
    for (final id in idCandidates) {
      final payloads = <Map<String, dynamic>>[
        // Most common: bin entry id only
        {'id': id},
        {'recordId': id},
        {'recycleBinId': id},
        {'binId': id},
        {'trashId': id},
        {
          'ids': [id],
        },

        // Some backends accept entity references
        {'entityType': normalizedType, 'entityId': entityId},
        {'entity_type': normalizedType, 'entity_id': entityId},
        if (recordId != null && recordId.trim().isNotEmpty)
          {
            'entityType': normalizedType,
            'entityId': entityId,
            'recordId': recordId.trim(),
          },
      ];
      final attempts = <Future<Map<String, dynamic>>>[
        for (final p in payloads)
          _requestOk(method: 'POST', path: '/recycle-bin/restore', data: p),
      ];

      for (final f in attempts) {
        final r = await f;
        if (r['success'] == true) {
          // Some servers return HTTP 202 (Accepted) for async deletes/restores.
          // In that case the item may not disappear immediately from the list.
          if (r['statusCode'] == 202) return r;
          // Verify it actually disappears from the recycle bin before returning success.
          bool stillThere = true;
          for (final delayMs in [250, 800, 1500]) {
            await Future.delayed(Duration(milliseconds: delayMs));
            final refreshed = await listRecycleBin();
            stillThere = _stillInBin(
              refreshed,
              entityId: entityId,
              recordId: recordId,
            );
            if (!stillThere) break;
          }
          if (!stillThere) return r;
          lastFailure = {
            'success': false,
            'message': 'Restore did not persist',
            'method': r['method'],
            'path': r['path'],
            if (r['queryParameters'] != null)
              'queryParameters': r['queryParameters'],
          };
          continue;
        }
        lastFailure = r;
      }
    }

    return {
      'success': false,
      'message': () {
        final m = lastFailure?['message']?.toString().trim();
        if (m == null || m.isEmpty) return 'Restore failed';
        // Avoid dumping full HTML into the UI.
        if (m.toLowerCase().contains('<!doctype html') ||
            m.toLowerCase().contains('<html')) {
          return 'Restore failed: server returned an HTML error page';
        }
        return m;
      }(),
      if (lastFailure?['method'] != null) 'method': lastFailure?['method'],
      if (lastFailure?['path'] != null) 'path': lastFailure?['path'],
      if (lastFailure?['queryParameters'] != null)
        'queryParameters': lastFailure?['queryParameters'],
      if (lastFailure?['statusCode'] != null)
        'statusCode': lastFailure?['statusCode'],
    };
  }

  Future<Map<String, dynamic>> deletePermanentlyFlexible({
    required String entityType,
    required String entityId,
    String? recordId,
  }) async {
    final normalizedType = _normalizeEntityType(entityType);
    final typeCandidates = <String>{
      normalizedType,
      entityType.trim(),
      if (normalizedType == 'document') 'file',
      if (normalizedType == 'folder') 'directory',
    }.where((t) => t.trim().isNotEmpty).map((t) => t.trim()).toList();
    final idCandidates = <String>{
      if (recordId != null && recordId.trim().isNotEmpty) recordId.trim(),
      entityId,
    }.toList();

    Map<String, dynamic>? lastFailure;

    // Official backend contract:
    // DELETE /api/recycle-bin with body { entityType: 'document'|'folder', entityId: '<uuid>' }
    for (final id in idCandidates) {
      // Prioritize official contract first (most reliable).
      final officialFirst = <Future<Map<String, dynamic>>>[
        _requestOk(
          method: 'DELETE',
          path: '/recycle-bin',
          data: {'entityType': normalizedType, 'entityId': entityId},
        ),
        _requestOk(
          method: 'DELETE',
          path: '/recycle-bin',
          data: {'entity_type': normalizedType, 'entity_id': entityId},
        ),
      ];
      for (final f in officialFirst) {
        final r = await f;
        if (r['success'] == true) {
          if (r['statusCode'] == 202) return r;
          bool stillThere = true;
          for (final delayMs in [250, 800, 1500]) {
            await Future.delayed(Duration(milliseconds: delayMs));
            final refreshed = await listRecycleBin();
            stillThere = _stillInBin(
              refreshed,
              entityId: entityId,
              recordId: recordId,
            );
            if (!stillThere) break;
          }
          if (!stillThere) return r;
        }
        lastFailure = r;
      }

      final payloads = <Map<String, dynamic>>[
        {'id': id},
        {'recordId': id},
        {'recycleBinId': id},
        {'binId': id},
        {'trashId': id},
        {
          'ids': [id],
        },
        {'entityType': normalizedType, 'entityId': entityId},
        {'entity_type': normalizedType, 'entity_id': entityId},
        if (recordId != null && recordId.trim().isNotEmpty)
          {
            'entityType': normalizedType,
            'entityId': entityId,
            'recordId': recordId.trim(),
          },
      ];
      final attempts = <Future<Map<String, dynamic>>>[
        // Some servers do not accept a body for DELETE; try query params too.
        _requestOk(
          method: 'DELETE',
          path: '/recycle-bin',
          queryParameters: {'id': id},
        ),
        _requestOk(
          method: 'DELETE',
          path: '/recycle-bin',
          queryParameters: {'recordId': id},
        ),
        _requestOk(
          method: 'DELETE',
          path: '/recycle-bin',
          queryParameters: {'recycleBinId': id},
        ),
        for (final t in typeCandidates) ...[
          _requestOk(
            method: 'DELETE',
            path: '/recycle-bin',
            queryParameters: {'entityType': t, 'entityId': entityId},
          ),
          _requestOk(
            method: 'DELETE',
            path: '/recycle-bin',
            queryParameters: {'entityType': t, 'entityId': id},
          ),
          _requestOk(
            method: 'DELETE',
            path: '/recycle-bin',
            queryParameters: {'entity_type': t, 'entity_id': entityId},
          ),
          _requestOk(
            method: 'DELETE',
            path: '/recycle-bin',
            queryParameters: {'entity_type': t, 'entity_id': id},
          ),
        ],

        // Common path-param variants.
        _requestOk(method: 'DELETE', path: '/recycle-bin/$id'),
        _requestOk(method: 'DELETE', path: '/recycle-bin/items/$id'),
        _requestOk(method: 'DELETE', path: '/recycle-bin/delete/$id'),
        _requestOk(method: 'DELETE', path: '/recyclebin/$id'),
        _requestOk(method: 'DELETE', path: '/trash/$id'),

        // Some APIs use a POST "delete" action.
        _requestOk(
          method: 'POST',
          path: '/recycle-bin/delete',
          data: {'id': id},
        ),
        _requestOk(
          method: 'POST',
          path: '/recycle-bin/delete',
          data: {'recordId': id},
        ),
        for (final p in payloads)
          _requestOk(method: 'DELETE', path: '/recycle-bin', data: p),
      ];

      for (final f in attempts) {
        final r = await f;
        if (r['success'] == true) {
          // Some servers return HTTP 202 (Accepted) for async deletes.
          // In that case the item may not disappear immediately from the list.
          if (r['statusCode'] == 202) return r;
          bool stillThere = true;
          for (final delayMs in [250, 800, 1500]) {
            await Future.delayed(Duration(milliseconds: delayMs));
            final refreshed = await listRecycleBin();
            stillThere = _stillInBin(
              refreshed,
              entityId: entityId,
              recordId: recordId,
            );
            if (!stillThere) break;
          }
          if (!stillThere) return r;
          lastFailure = {
            'success': false,
            'message': 'Delete did not persist',
            'method': r['method'],
            'path': r['path'],
            if (r['queryParameters'] != null)
              'queryParameters': r['queryParameters'],
          };
          continue;
        }
        lastFailure = r;
      }
    }

    return {
      'success': false,
      'message': lastFailure?['message']?.toString() ?? 'Delete failed',
      if (lastFailure?['method'] != null) 'method': lastFailure?['method'],
      if (lastFailure?['path'] != null) 'path': lastFailure?['path'],
      if (lastFailure?['queryParameters'] != null)
        'queryParameters': lastFailure?['queryParameters'],
      if (lastFailure?['statusCode'] != null)
        'statusCode': lastFailure?['statusCode'],
    };
  }

  /// Restore multiple items at once.
  ///
  /// Official contract: `POST /recycle-bin/restore-bulk` with `{ items: [...] }`.
  /// Returns `{ results: [{entityType, entityId, success}] }`.
  Future<Map<String, dynamic>> restoreBulk({
    required List<Map<String, String>> items,
  }) async {
    if (items.isEmpty) return {'success': true, 'results': const []};
    final payload = {'items': items};
    final r = await _requestOk(
      method: 'POST',
      path: '/recycle-bin/restore-bulk',
      data: payload,
    );
    if (r['success'] == true) return r;

    // Compatibility fallback: restore one-by-one.
    final results = <Map<String, dynamic>>[];
    for (final it in items) {
      final entityType = (it['entityType'] ?? '').toString();
      final entityId = (it['entityId'] ?? '').toString();
      if (entityType.isEmpty || entityId.isEmpty) continue;
      final one = await restoreItemFlexible(
        entityType: entityType,
        entityId: entityId,
      );
      results.add({
        'entityType': entityType,
        'entityId': entityId,
        'success': one['success'] == true,
      });
    }
    return {'success': true, 'results': results, 'fallback': true};
  }

  /// Permanently delete multiple items.
  ///
  /// Official contract: `DELETE /recycle-bin/bulk` with `{ items: [...] }`.
  Future<Map<String, dynamic>> deleteBulkPermanently({
    required List<Map<String, String>> items,
  }) async {
    if (items.isEmpty) return {'success': true, 'results': const []};
    final payload = {'items': items};
    final r = await _requestOk(
      method: 'DELETE',
      path: '/recycle-bin/bulk',
      data: payload,
    );
    if (r['success'] == true) return r;

    // Compatibility fallback: delete one-by-one.
    final results = <Map<String, dynamic>>[];
    for (final it in items) {
      final entityType = (it['entityType'] ?? '').toString();
      final entityId = (it['entityId'] ?? '').toString();
      if (entityType.isEmpty || entityId.isEmpty) continue;
      final one = await deletePermanentlyFlexible(
        entityType: entityType,
        entityId: entityId,
      );
      results.add({
        'entityType': entityType,
        'entityId': entityId,
        'success': one['success'] == true,
      });
    }
    return {'success': true, 'results': results, 'fallback': true};
  }
}
