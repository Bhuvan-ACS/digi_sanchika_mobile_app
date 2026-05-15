class FavoriteItem {
  final String id;
  final String entityId;
  final String entityType;
  final String? name;

  FavoriteItem({
    required this.id,
    required this.entityId,
    required this.entityType,
    this.name,
  });

  factory FavoriteItem.fromJson(Map<String, dynamic> json) {
    return FavoriteItem(
      id: json['id']?.toString() ?? '',
      entityId:
          json['entity_id']?.toString() ??
          json['entityId']?.toString() ??
          json['target_id']?.toString() ??
          json['targetId']?.toString() ??
          '',
      entityType:
          json['entity_type']?.toString() ??
          json['entityType']?.toString() ??
          json['target_type']?.toString() ??
          json['type']?.toString() ??
          '',
      name: json['name']?.toString(),
    );
  }
}
