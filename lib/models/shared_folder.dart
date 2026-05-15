// models/shared_folder.dart
class SharedFolder {
  final String id;
  final String name;
  final String owner;
  final String createdAt;
  final int itemCount; // -1 = unknown

  SharedFolder({
    required this.id,
    required this.name,
    required this.owner,
    required this.createdAt,
    this.itemCount = -1,
  });

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'owner': owner, 'createdAt': createdAt, 'itemCount': itemCount};
  }

  factory SharedFolder.fromJson(Map<String, dynamic> json) {
    final count = json['item_count'] ??
        json['items_count'] ??
        json['document_count'] ??
        json['total_files'] ??
        json['files_count'];

    String? from(dynamic v) {
      if (v == null) return null;
      if (v is String) {
        final s = v.trim();
        return s.isEmpty ? null : s;
      }
      if (v is Map) {
        final name = v['name'] ?? v['full_name'] ?? v['username'];
        if (name is String && name.trim().isNotEmpty) return name.trim();
      }
      return null;
    }

    final ownerName =
        from(json['shared_by']) ??
        from(json['sharedBy']) ??
        from(json['owner']) ??
        from(json['owner_name']) ??
        from(json['shared_by_name']) ??
        from(json['created_by']) ??
        from(json['uploader']) ??
        'Unknown User';
    return SharedFolder(
      id: (json['id'] ?? 0).toString(),
      name: json['name']?.toString() ?? 'Unknown Folder',
      owner: ownerName,
      createdAt: _formatDate(json['created_at']),
      itemCount: count is int
          ? count
          : (count != null ? int.tryParse(count.toString()) ?? -1 : -1),
    );
  }

  static String _formatDate(dynamic date) {
    if (date == null) return 'Unknown';
    try {
      final dateTime = DateTime.parse(date.toString());
      return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year}';
    } catch (e) {
      final dateStr = date.toString();
      if (dateStr.contains('/')) return dateStr;
      return dateStr;
    }
  }
}
