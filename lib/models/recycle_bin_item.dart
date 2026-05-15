class RecycleBinItem {
  /// Id of the recycle-bin entry itself (if the backend uses a separate record).
  final String? recordId;
  final String entityId;
  final String entityType;
  final String name;
  final String? deletedAt;

  RecycleBinItem({
    this.recordId,
    required this.entityId,
    required this.entityType,
    required this.name,
    this.deletedAt,
  });

  factory RecycleBinItem.fromJson(Map<String, dynamic> json) {
    String pickString(List<String> keys) {
      for (final k in keys) {
        final v = json[k];
        if (v == null) continue;
        final s = v.toString().trim();
        if (s.isNotEmpty) return s;
      }
      return '';
    }

    // Many backends return both:
    // - a recycle-bin entry id (often `id`)
    // - the actual entity id (`entity_id` / `document_id` / `folder_id` ...)
    //
    // Prefer using the entity id as `entityId`, and keep the bin entry id in
    // `recordId` when both are available.
    var recordId = pickString([
      'recycle_bin_id',
      'recycleBinId',
      'record_id',
      'recordId',
    ]);

    final explicitEntityId = pickString([
      'entity_id',
      'entityId',
      'entityID',
      'document_id',
      'doc_id',
      'file_id',
      'folder_id',
    ]);
    final idField = pickString(['id']);

    final entityId = explicitEntityId.isNotEmpty ? explicitEntityId : idField;

    // If the backend provides a separate `id` and we already have an entity id,
    // treat `id` as the recycle-bin record id for delete/restore operations.
    if (recordId.isEmpty &&
        idField.isNotEmpty &&
        explicitEntityId.isNotEmpty &&
        idField != explicitEntityId) {
      recordId = idField;
    }

    String normalizeEntityType(String raw) {
      final t = raw.trim().toLowerCase();
      if (t.isEmpty) return '';
      if (t.contains('folder')) return 'folder';
      if (t.contains('document')) return 'document';
      // Some payloads may carry mime types or extensions in `type`.
      if (t.contains('/') || t.contains('pdf') || t.contains('doc')) {
        return 'document';
      }
      return t;
    }

    var entityTypeRaw = pickString([
      'entity_type',
      'entityType',
      'item_type',
      'type',
      'kind',
    ]);

    // Heuristics for APIs that return separate `documents` / `folders` arrays without an explicit type field.
    if (entityTypeRaw.trim().isEmpty) {
      if (json.containsKey('mime_type') ||
          json.containsKey('file_size_bytes') ||
          json.containsKey('classification')) {
        entityTypeRaw = 'document';
      } else if (json.containsKey('parent_id')) {
        entityTypeRaw = 'folder';
      }
    }

    return RecycleBinItem(
      recordId: recordId.isEmpty ? null : recordId,
      entityId: entityId,
      entityType: normalizeEntityType(entityTypeRaw),
      name: pickString([
        'name',
        'original_name',
        'original_filename',
        'filename',
        'file_name',
        'title',
      ]),
      deletedAt:
          pickString([
            'deleted_at',
            'deletedAt',
            'trashed_at',
            'moved_to_bin_at',
            'created_at',
          ]).isEmpty
          ? null
          : pickString([
              'deleted_at',
              'deletedAt',
              'trashed_at',
              'moved_to_bin_at',
              'created_at',
            ]),
    );
  }
}
