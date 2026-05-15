class GroupMember {
  final String id; // membership id (if provided)
  final String userId;
  final String groupId;
  final String role; // owner | admin | member
  final String? fullName;
  final String? email;
  final String? employeeId;
  final DateTime? joinedAt;

  const GroupMember({
    required this.id,
    required this.userId,
    required this.groupId,
    required this.role,
    this.fullName,
    this.email,
    this.employeeId,
    this.joinedAt,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    final joinedAtRaw = json['joined_at'] ?? json['joinedAt'];
    return GroupMember(
      id: (json['id'] ?? '').toString(),
      userId: (json['user_id'] ?? json['userId'] ?? '').toString(),
      groupId: (json['group_id'] ?? json['groupId'] ?? '').toString(),
      role: (json['role'] ?? 'member').toString(),
      fullName: (json['full_name'] ?? json['fullName'] ?? json['name'])?.toString(),
      email: json['email']?.toString(),
      employeeId: (json['employee_id'] ?? json['employeeId'])?.toString(),
      joinedAt: joinedAtRaw == null ? null : DateTime.tryParse(joinedAtRaw.toString()),
    );
  }
}

