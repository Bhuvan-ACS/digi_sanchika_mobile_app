// models/document.dart - FIXED VERSION
class Document {
  String id;
  String name;
  String type;
  String size;
  String keyword;
  String uploadDate;
  String owner;
  String details;
  String classification;
  bool allowDownload;
  bool isPublishedToLibrary;
  String sharingType;
  String folder; // This is folder name
  String? folderId; // CHANGE: Make nullable String?
  String path;
  String fileType;
  String? expiresAt;

  // Shared-with-me enhancements (optional; only set for shared items).
  String? sharedViaGroupId;
  String? sharedViaGroupName;
  String? sharedViaGroupColorHex;
  String? sharedByName;

  Document({
    required this.id,
    required this.name,
    required this.type,
    required this.size,
    required this.keyword,
    required this.uploadDate,
    required this.owner,
    required this.details,
    required this.classification,
    required this.allowDownload,
    this.isPublishedToLibrary = false,
    required this.sharingType,
    required this.folder,
    required this.path,
    required this.fileType,
    this.folderId, // CHANGE: Make optional and nullable
    this.sharedViaGroupId,
    this.sharedViaGroupName,
    this.sharedViaGroupColorHex,
    this.sharedByName,
    this.expiresAt,
  });

  Map<String, dynamic> toApiJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'size': size,
      'keyword': keyword,
      'upload_date': uploadDate,
      'owner': owner,
      'details': details,
      'classification': classification,
      'allowDownload': allowDownload,
      'isPublishedToLibrary': isPublishedToLibrary,
      'sharingType': sharingType,
      'folder': folder,
      'folder_id': folderId, // Can be null
      'path': path,
      'fileType': fileType,
      'sharedViaGroupId': sharedViaGroupId,
      'sharedViaGroupName': sharedViaGroupName,
      'sharedViaGroupColorHex': sharedViaGroupColorHex,
      'sharedByName': sharedByName,
      'expiresAt': expiresAt,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'size': size,
      'keyword': keyword,
      'uploadDate': uploadDate,
      'owner': owner,
      'details': details,
      'classification': classification,
      'allowDownload': allowDownload,
      'isPublishedToLibrary': isPublishedToLibrary,
      'sharingType': sharingType,
      'folder': folder,
      'folderId': folderId, // Can be null
      'path': path,
      'fileType': fileType,
      'sharedViaGroupId': sharedViaGroupId,
      'sharedViaGroupName': sharedViaGroupName,
      'sharedViaGroupColorHex': sharedViaGroupColorHex,
      'sharedByName': sharedByName,
      'expiresAt': expiresAt,
    };
  }

 factory Document.fromJson(Map<String, dynamic> json) {
   final folder =
        json['folder'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(json['folder'])
            : json;

    final share =
        json['share'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(json['share'])
            : <String, dynamic>{};

    final sharedBy =
        json['sharedBy'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(json['sharedBy'])
            : <String, dynamic>{};
  return Document(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    type: json['type']?.toString() ?? '',
    size: json['size']?.toString() ?? '',
    keyword: json['keyword']?.toString() ?? '',
    uploadDate:
        json['uploadDate']?.toString() ??
        json['upload_date']?.toString() ??
        DateTime.now().toString(),
    owner: json['owner']?.toString() ?? '',
    details: json['details']?.toString() ?? '',
    classification:
        json['classification']?.toString() ?? 'General',
    allowDownload: json['allowDownload'] ?? true,
    isPublishedToLibrary:
        json['isPublishedToLibrary'] == true ||
        json['is_published_to_library'] == true,
    sharingType:
        json['sharingType']?.toString() ?? 'private',
    folder: json['folder']?.toString() ?? 'General',
    folderId:
        json['folderId']?.toString() ??
        json['folder_id']?.toString(),
    path:
        json['path']?.toString() ??
        json['filename']?.toString() ??
        '',
    fileType:
        json['fileType']?.toString() ??
        json['file_type']?.toString() ??
        'unknown',
    sharedViaGroupId:
        json['sharedViaGroupId']?.toString(),
    sharedViaGroupName:
        json['sharedViaGroupName']?.toString(),
    sharedViaGroupColorHex:
        json['sharedViaGroupColorHex']?.toString(),
    sharedByName:
        json['sharedByName']?.toString(),
    expiresAt: _formatExpiry(
        share['expires_at'] ?? folder['expires_at'],
      ),
  );
}

 static Document fromApiJson(
  Map<String, dynamic> docJson,
) {
  final share =
      docJson['share'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(docJson['share'])
          : <String, dynamic>{};

  return Document(
    id: (docJson['id'] ?? '').toString(),
    name:
        (docJson['original_name'] ??
                docJson['filename'] ??
                '')
            .toString(),
    type:
        (docJson['file_type'] ?? 'unknown')
            .toString(),
    size: (docJson['size'] ?? 0).toString(),
    keyword: '',
    uploadDate:
        docJson['upload_date']?.toString() ??
        DateTime.now().toString(),
    owner: '',
    details: '',
    classification:
        (docJson['category'] ?? 'General')
            .toString(),
    allowDownload: true,
    isPublishedToLibrary:
        docJson['isPublishedToLibrary'] ==
            true ||
        docJson['is_published_to_library'] ==
            true,
    sharingType: 'private',
    folder: 'General',
    folderId:
        docJson['folder_id']?.toString(),
    path:
        (docJson['filename'] ?? '')
            .toString(),
    fileType:
        (docJson['file_type'] ?? 'unknown')
            .toString(),
    expiresAt: _formatExpiry(
      share['expires_at'] ??
          docJson['expiresAt'] ??
          docJson['expires_at'],
    ),
  );
}
  Document copyWith({
    String? id,
    String? name,
    String? type,
    String? size,
    String? keyword,
    String? uploadDate,
    String? owner,
    String? details,
    String? classification,
    bool? allowDownload,
    bool? isPublishedToLibrary,
    String? sharingType,
    String? folder,
    String? folderId,
    String? path,
    String? fileType,
    String? sharedViaGroupId,
    String? sharedViaGroupName,
    String? sharedViaGroupColorHex,
    String? sharedByName,
    String? expiresAt,
  }) {
    return Document(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      size: size ?? this.size,
      keyword: keyword ?? this.keyword,
      uploadDate: uploadDate ?? this.uploadDate,
      owner: owner ?? this.owner,
      details: details ?? this.details,
      classification: classification ?? this.classification,
      allowDownload: allowDownload ?? this.allowDownload,
      isPublishedToLibrary: isPublishedToLibrary ?? this.isPublishedToLibrary,
      sharingType: sharingType ?? this.sharingType,
      folder: folder ?? this.folder,
      folderId: folderId ?? this.folderId,
      path: path ?? this.path,
      fileType: fileType ?? this.fileType,
      sharedViaGroupId: sharedViaGroupId ?? this.sharedViaGroupId,
      sharedViaGroupName: sharedViaGroupName ?? this.sharedViaGroupName,
      sharedViaGroupColorHex: sharedViaGroupColorHex ?? this.sharedViaGroupColorHex,
      sharedByName: sharedByName ?? this.sharedByName,
      expiresAt: _formatExpiry(expiresAt),
    );
  }

  static String _formatExpiry(dynamic value) {
  if (value == null) return 'No Expiry';
  try {
    final date = DateTime.parse(value.toString());
    if (date.year >= 9999) return 'No Expiry';
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  } catch (_) {
    return value.toString();
  }
}
}



