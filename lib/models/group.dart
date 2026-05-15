class Group {
  final String id;
  final String name;
  final String? description;
  final String? colorHex;
  final String? avatarEmoji;
  final bool isActive;
  final int? memberCount;
  final DateTime? createdAt;

  const Group({
    required this.id,
    required this.name,
    this.description,
    this.colorHex,
    this.avatarEmoji,
    required this.isActive,
    this.memberCount,
    this.createdAt,
  });

  factory Group.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['created_at'] ?? json['createdAt'];
    DateTime? createdAt;
    if (createdAtRaw != null) {
      createdAt = DateTime.tryParse(createdAtRaw.toString());
    }

    return Group(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      description: json['description']?.toString(),
      colorHex: (json['color'] ?? json['colorHex'] ?? json['color_hex'])?.toString(),
      avatarEmoji: (json['avatarEmoji'] ?? json['avatar_emoji'])?.toString(),
      isActive: (json['is_active'] ?? json['isActive'] ?? true) == true,
      memberCount: (json['member_count'] is int)
          ? (json['member_count'] as int)
          : int.tryParse((json['member_count'] ?? json['memberCount'] ?? '').toString()),
      createdAt: createdAt,
    );
  }
}

