class FolderAlert {
  final String id;
  final String userId;
  final String folderId;
  final String? folderName;
  final bool onAdd;
  final bool onDelete;
  final bool onShare;
  final bool onEdit;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const FolderAlert({
    required this.id,
    required this.userId,
    required this.folderId,
    this.folderName,
    required this.onAdd,
    required this.onDelete,
    required this.onShare,
    required this.onEdit,
    this.createdAt,
    this.updatedAt,
  });

  factory FolderAlert.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString());

    return FolderAlert(
      id: (json['id'] ?? '').toString(),
      userId: (json['user_id'] ?? json['userId'] ?? '').toString(),
      folderId: (json['folder_id'] ?? json['folderId'] ?? '').toString(),
      folderName: (json['folder_name'] ?? json['folderName'])?.toString(),
      onAdd: (json['on_add'] ?? json['onAdd'] ?? true) == true,
      onDelete: (json['on_delete'] ?? json['onDelete'] ?? true) == true,
      onShare: (json['on_share'] ?? json['onShare'] ?? false) == true,
      onEdit: (json['on_edit'] ?? json['onEdit'] ?? false) == true,
      createdAt: parseDate(json['created_at'] ?? json['createdAt']),
      updatedAt: parseDate(json['updated_at'] ?? json['updatedAt']),
    );
  }
}

