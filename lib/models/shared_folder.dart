class SharedFolder {
  final String id;
  final String name;
  final String owner;
  final String createdAt;
  final String expiresAt;
  final int itemCount;
  final bool canUpload;
  final bool canDownload;
  final bool canEdit;
  final String? viaGroupName;
  final String? viaGroupColorHex;

  SharedFolder({
    required this.id,
    required this.name,
    required this.owner,
    required this.createdAt,
    required this.expiresAt,
    this.itemCount = -1,
    this.canUpload = false,
    this.canDownload = false,
    this.canEdit = false,
    this.viaGroupName,
    this.viaGroupColorHex,
  });

  factory SharedFolder.fromJson(Map<String, dynamic> json) {
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
    final effective =
        json['effectiveAccess'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(json['effectiveAccess'])
            : (json['effective_access'] is Map<String, dynamic>
                ? Map<String, dynamic>.from(json['effective_access'])
                : <String, dynamic>{});
    final viaGroup =
        share['viaGroup'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(share['viaGroup'])
            : (share['via_group'] is Map<String, dynamic>
                ? Map<String, dynamic>.from(share['via_group'])
                : <String, dynamic>{});

    final count =
        json['item_count'] ??
        json['items_count'] ??
        json['document_count'] ??
        json['total_files'] ??
        folder['item_count'] ??
        folder['items_count'] ??
        folder['document_count'];

    return SharedFolder(
      id: (folder['id'] ?? '').toString(),
      name: folder['name']?.toString() ?? 'Unknown Folder',
      owner:
          sharedBy['full_name']?.toString() ??
          sharedBy['name']?.toString() ??
          folder['owner']?.toString() ??
          'Unknown User',
      createdAt: _formatDate(
        folder['created_at'] ?? share['created_at'],
      ),
      expiresAt:
    (share['expires_at'] ?? folder['expires_at'])!.toString(),
      itemCount: count is int
          ? count
          : int.tryParse(count?.toString() ?? '') ?? -1,
      canUpload:
          effective['canUpload'] == true ||
          effective['can_upload'] == true ||
          (share['permission']?.toString() == 'view_upload'),
      canDownload:
          effective['canDownload'] == true ||
          effective['can_download'] == true ||
          share['allow_download'] == true ||
          share['allowDownload'] == true,
      canEdit:
          effective['canEdit'] == true ||
          effective['can_edit'] == true ||
          share['allow_edit'] == true ||
          share['allowEdit'] == true,
      viaGroupName: viaGroup['name']?.toString(),
      viaGroupColorHex:
          (viaGroup['color'] ?? viaGroup['colorHex'])?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'owner': owner,
      'createdAt': createdAt,
      'expiresAt': expiresAt,
      'itemCount': itemCount,
      'canUpload': canUpload,
      'canDownload': canDownload,
      'canEdit': canEdit,
      'viaGroupName': viaGroupName,
      'viaGroupColorHex': viaGroupColorHex,
    };
  }

  static String _formatDate(dynamic value) {
  if (value == null) return 'No Expiry';

  try {
    final date = DateTime.parse(value.toString());

    // Handle backend's "no expiry" value
    if (date.year >= 9999) {
      return 'No Expiry';
    }

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  } catch (_) {
    return value.toString();
  }
}

  @override
  String toString() {
    return 'SharedFolder('
        'id: $id, '
        'name: $name, '
        'owner: $owner, '
        'createdAt: $createdAt, '
        'expiresAt: $expiresAt, '
        'itemCount: $itemCount'
        ')';
  }
}
