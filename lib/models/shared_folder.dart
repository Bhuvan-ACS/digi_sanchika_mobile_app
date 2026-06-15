class SharedFolder {
  final String id;
  final String name;
  final String owner;
  final String createdAt;
  final String expiresAt;
  final int itemCount;

  SharedFolder({
    required this.id,
    required this.name,
    required this.owner,
    required this.createdAt,
    required this.expiresAt,
    this.itemCount = -1,
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