class SharedByMeModel {
  List<DocumentElement> documents;
  List<FolderElement> folders;

  SharedByMeModel({
    required this.documents,
    required this.folders,
  });

  factory SharedByMeModel.fromJson(Map<String, dynamic> json) {
    return SharedByMeModel(
      documents: (json['documents'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => DocumentElement.fromJson(_toMap(e)))
          .toList(),
      folders: (json['folders'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => FolderElement.fromJson(_toMap(e)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'documents': documents.map((e) => e.toJson()).toList(),
        'folders': folders.map((e) => e.toJson()).toList(),
      };
}

// ── DocumentElement ────────────────────────────────────────────────────────────

class DocumentElement {
  Share share;
  DocumentDocument document;
  SharedWith sharedWith;
  List<SharedWith> sharedWithAll;

  DocumentElement({
    required this.share,
    required this.document,
    required this.sharedWith,
    required this.sharedWithAll,
  });

  factory DocumentElement.fromJson(Map<String, dynamic> json) {
    return DocumentElement(
      share: Share.fromJson(_toMap(json['share'])),
      document: DocumentDocument.fromJson(_toMap(json['document'])),
      sharedWith: SharedWith.fromJson(_toMap(json['shared_with'])),
      sharedWithAll: (json['shared_with_all'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => SharedWith.fromJson(_toMap(e)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'share': share.toJson(),
        'document': document.toJson(),
        'shared_with': sharedWith.toJson(),
        'shared_with_all': sharedWithAll.map((e) => e.toJson()).toList(),
      };
}

// ── DocumentDocument ───────────────────────────────────────────────────────────

class DocumentDocument {
  String id;
  String name;
  dynamic description;
  String mimeType;
  String fileSizeBytes;
  String classification;
  String storageKey;
  int version;
  DateTime createdAt;
  DateTime updatedAt;

  DocumentDocument({
    required this.id,
    required this.name,
    required this.description,
    required this.mimeType,
    required this.fileSizeBytes,
    required this.classification,
    required this.storageKey,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DocumentDocument.fromJson(Map<String, dynamic> json) {
    return DocumentDocument(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description'],
      mimeType: json['mime_type']?.toString() ?? '',
      fileSizeBytes: json['file_size_bytes']?.toString() ?? '0',
      classification: json['classification']?.toString() ?? '',
      storageKey: json['storage_key']?.toString() ?? '',
      version: (json['version'] as num?)?.toInt() ?? 1,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'mime_type': mimeType,
        'file_size_bytes': fileSizeBytes,
        'classification': classification,
        'storage_key': storageKey,
        'version': version,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}

// ── Share ──────────────────────────────────────────────────────────────────────

class Share {
  String id;
  String? documentId;
  String permission;
  bool allowDownload;
  bool allowEdit;
  DateTime expiresAt;
  DateTime createdAt;
  bool isRevoked;
  dynamic viaGroup;
  String? folderId;

  Share({
    required this.id,
    this.documentId,
    required this.permission,
    required this.allowDownload,
    required this.allowEdit,
    required this.expiresAt,
    required this.createdAt,
    required this.isRevoked,
    required this.viaGroup,
    this.folderId,
  });

  factory Share.fromJson(Map<String, dynamic> json) {
    return Share(
      id: json['id']?.toString() ?? '',
      documentId: json['document_id']?.toString(),
      permission: json['permission']?.toString() ?? 'view',
      allowDownload: json['allow_download'] as bool? ?? false,
      allowEdit: json['allow_edit'] as bool? ?? false,
      expiresAt: _parseDate(json['expires_at'], fallback: DateTime(9999)),
      createdAt: _parseDate(json['created_at']),
      isRevoked: json['is_revoked'] as bool? ?? false,
      viaGroup: json['via_group'],
      folderId: json['folder_id']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'document_id': documentId,
        'permission': permission,
        'allow_download': allowDownload,
        'allow_edit': allowEdit,
        'expires_at': expiresAt.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'is_revoked': isRevoked,
        'via_group': viaGroup,
        'folder_id': folderId,
      };
}

// ── SharedWith ─────────────────────────────────────────────────────────────────

class SharedWith {
  String id;
  String fullName;
  String email;
  bool? isGroup;

  SharedWith({
    required this.id,
    required this.fullName,
    required this.email,
    this.isGroup,
  });

  factory SharedWith.fromJson(Map<String, dynamic> json) {
    return SharedWith(
      id: json['id']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      isGroup: json['is_group'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'full_name': fullName,
        'email': email,
        'is_group': isGroup,
      };
}

// ── FolderElement ──────────────────────────────────────────────────────────────

class FolderElement {
  Share share;
  FolderFolder folder;
  SharedWith sharedWith;
  List<SharedWith> sharedWithAll;

  FolderElement({
    required this.share,
    required this.folder,
    required this.sharedWith,
    required this.sharedWithAll,
  });

  factory FolderElement.fromJson(Map<String, dynamic> json) {
    return FolderElement(
      share: Share.fromJson(_toMap(json['share'])),
      folder: FolderFolder.fromJson(_toMap(json['folder'])),
      sharedWith: SharedWith.fromJson(_toMap(json['shared_with'])),
      sharedWithAll: (json['shared_with_all'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => SharedWith.fromJson(_toMap(e)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'share': share.toJson(),
        'folder': folder.toJson(),
        'shared_with': sharedWith.toJson(),
        'shared_with_all': sharedWithAll.map((e) => e.toJson()).toList(),
      };
}

// ── FolderFolder ───────────────────────────────────────────────────────────────

class FolderFolder {
  String id;
  String name;
  DateTime createdAt;
  DateTime updatedAt;

  FolderFolder({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FolderFolder.fromJson(Map<String, dynamic> json) {
    return FolderFolder(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}

// ── Private helpers ────────────────────────────────────────────────────────────

/// Safely coerces any [Map] (or null) to [Map<String, dynamic>].
/// Returns an empty map if the value is null or not a Map — prevents
/// "type 'Null' is not a subtype of type 'Map<String, dynamic>'" crashes.
Map<String, dynamic> _toMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}

DateTime _parseDate(dynamic value, {DateTime? fallback}) {
  if (value == null) return fallback ?? DateTime.now();
  try {
    return DateTime.parse(value.toString());
  } catch (_) {
    return fallback ?? DateTime.now();
  }
}