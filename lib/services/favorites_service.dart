import 'package:dio/dio.dart';
import 'package:digi_sanchika/services/api_client.dart';
import 'package:digi_sanchika/models/favorite_item.dart';

class FavoritesService {
  Dio get _dio => ApiClient.instance.dio;

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  bool _looksLikeDocument(Map<String, dynamic> map) {
    return map.containsKey('mime_type') ||
        map.containsKey('file_name') ||
        map.containsKey('fileName') ||
        map.containsKey('original_filename') ||
        map.containsKey('original_name') ||
        map.containsKey('upload_date');
  }

  Map<String, dynamic> _favoriteFromEntity({
    required Map<String, dynamic> entity,
    required String entityType,
  }) {
    final entityId =
        (entity['entity_id'] ?? entity['entityId'] ?? entity['id'] ?? '')
            .toString();
    final favId =
        (entity['favorite_id'] ??
                entity['favoriteId'] ??
                entity['fav_id'] ??
                entity['favId'] ??
                entity['id'] ??
                entityId)
            .toString();

    final name =
        (entity['name'] ??
                entity['original_filename'] ??
                entity['original_name'] ??
                entity['file_name'] ??
                entity['fileName'] ??
                entity['filename'])
            ?.toString();

    // Try to preserve "public/library" hint in the type when backend doesn't return a favorite record.
    final classification = (entity['classification'] ?? entity['doc_class'])
        ?.toString()
        .toLowerCase();
    final isPublic = entity['is_public'] == true || classification == 'public';
    final effectiveType =
        (entityType == 'document' && isPublic) ? 'library_document' : entityType;

    return {
      'id': favId,
      'entityId': entityId,
      'entity_id': entityId,
      'entityType': effectiveType,
      'entity_type': effectiveType,
      if (name != null) 'name': name,
    };
  }

  Map<String, dynamic> _normalizeRawFavorite(dynamic raw) {
    final map = _asMap(raw);
    if (map == null) return const <String, dynamic>{};

    // Case 1: already a favorite record (has entity id + entity type).
    final hasEntityId = map.containsKey('entity_id') || map.containsKey('entityId');
    final hasEntityType =
        map.containsKey('entity_type') || map.containsKey('entityType') || map.containsKey('type');
    if (hasEntityId && hasEntityType) {
      return map;
    }

    // Case 2: favorite record with nested entity (e.g. {id, entity_type, entity_id, document:{...}}).
    final nestedDoc = _asMap(map['document']);
    final nestedFolder = _asMap(map['folder']);
    final nested = nestedDoc ?? nestedFolder;
    if (nested != null) {
      final inferredType = (map['entity_type'] ?? map['entityType'] ?? map['type'])
          ?.toString()
          .toLowerCase();
      final entityType =
          (inferredType != null && inferredType.contains('folder'))
              ? 'folder'
              : 'document';
      final normalized = _favoriteFromEntity(entity: nested, entityType: entityType);
      return {
        ...normalized,
        // Prefer favorite id from outer record when present.
        if (map['id'] != null) 'id': map['id'].toString(),
        // Preserve explicit raw type hint if present.
        if (inferredType != null && inferredType.isNotEmpty)
          'entityType': inferredType,
        if (inferredType != null && inferredType.isNotEmpty)
          'entity_type': inferredType,
      };
    }

    // Case 3: backend returns the actual document/folder objects under /favorites.
    final entityType = _looksLikeDocument(map) ? 'document' : 'folder';
    return _favoriteFromEntity(entity: map, entityType: entityType);
  }

  Future<List<FavoriteItem>> listFavorites() async {
    try {
      final response = await _dio.get('/favorites');
      if (response.statusCode == 200) {
        final data = response.data;
        List<dynamic> items = [];
        if (data is List) {
          items = data;
        } else if (data is Map<String, dynamic>) {
          if (data['items'] is List) {
            items = data['items'];
          } else if (data['favorites'] is List) {
            items = data['favorites'];
          } else {
            final docs = data['documents'] is List ? data['documents'] : [];
            final folders = data['folders'] is List ? data['folders'] : [];
            items = [
              ...docs.map((d) => _favoriteFromEntity(
                    entity: Map<String, dynamic>.from(d as Map),
                    entityType: 'document',
                  )),
              ...folders.map((f) => _favoriteFromEntity(
                    entity: Map<String, dynamic>.from(f as Map),
                    entityType: 'folder',
                  )),
            ];
          }
        }
        return items
            .map((i) => _normalizeRawFavorite(i))
            .where((m) => m.isNotEmpty)
            .map<FavoriteItem>((m) => FavoriteItem.fromJson(m))
            .where((f) => f.entityId.isNotEmpty && f.entityType.isNotEmpty)
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<bool> addFavorite({
    required String entityId,
    required String entityType,
  }) async {
    final response = await _dio.post(
      '/favorites',
      data: {
        'entityType': entityType,
        'entityId': entityId,
        'entity_type': entityType,
        'entity_id': entityId,
      },
    );
    return response.statusCode == 200 || response.statusCode == 201;
  }

  Future<bool> removeFavorite({
    required String entityId,
    required String entityType,
  }) async {
    final response = await _dio.delete(
      '/favorites',
      data: {
        'entityType': entityType,
        'entityId': entityId,
        'entity_type': entityType,
        'entity_id': entityId,
      },
    );
    return response.statusCode == 200 || response.statusCode == 204;
  }
}
