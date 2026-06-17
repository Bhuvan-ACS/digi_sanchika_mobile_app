/// Models for GET /api/shares/folders/:folderId/members
library;

enum FolderAccessType {
  direct,
  group;

  static FolderAccessType fromString(String? value) =>
      value?.toLowerCase() == 'group' ? group : direct;
}

/// A group that grants a member access to a folder.
class FolderMemberGroup {
  final String groupId;
  final String groupName;
  final String groupColor;

  const FolderMemberGroup({
    required this.groupId,
    required this.groupName,
    required this.groupColor,
  });

  factory FolderMemberGroup.fromJson(Map<String, dynamic> json) {
    return FolderMemberGroup(
      groupId: (json['groupId'] ?? json['group_id'] ?? '').toString(),
      groupName: (json['groupName'] ?? json['group_name'] ?? '').toString(),
      groupColor:
          (json['groupColor'] ?? json['group_color'] ?? '#2B41BD').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'groupId': groupId,
    'groupName': groupName,
    'groupColor': groupColor,
  };
}

/// A user who has access to a folder.
class FolderMember {
  final String userId;
  final String fullName;
  final String email;

  /// "view" | "view_upload"
  final String permission;

  final bool allowDownload;
  final bool allowEdit;
  final DateTime? expiresAt;
  final DateTime? sharedAt;
  final String shareId;
  final FolderAccessType accessType;

  /// Non-empty only when [accessType] is [FolderAccessType.group].
  final List<FolderMemberGroup> viaGroups;

  const FolderMember({
    required this.userId,
    required this.fullName,
    required this.email,
    required this.permission,
    required this.allowDownload,
    required this.allowEdit,
    this.expiresAt,
    this.sharedAt,
    required this.shareId,
    required this.accessType,
    this.viaGroups = const [],
  });

  factory FolderMember.fromJson(Map<String, dynamic> json) {
    final rawGroups = json['viaGroups'] ?? json['via_groups'] ?? const [];
    return FolderMember(
      userId: (json['userId'] ?? json['user_id'] ?? '').toString(),
      fullName: (json['fullName'] ?? json['full_name'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      permission: (json['permission'] ?? 'view').toString(),
      allowDownload: _parseBool(json['allowDownload'] ?? json['allow_download']),
      allowEdit: _parseBool(json['allowEdit'] ?? json['allow_edit']),
      expiresAt: _parseDate(json['expiresAt'] ?? json['expires_at']),
      sharedAt: _parseDate(json['sharedAt'] ?? json['shared_at']),
      shareId: (json['shareId'] ?? json['share_id'] ?? '').toString(),
      accessType: FolderAccessType.fromString(
        (json['accessType'] ?? json['access_type'])?.toString(),
      ),
      viaGroups: rawGroups is List
          ? rawGroups
                .whereType<Map>()
                .map(
                  (g) => FolderMemberGroup.fromJson(
                    Map<String, dynamic>.from(g),
                  ),
                )
                .toList()
          : const [],
    );
  }

  /// True when [permission] is "view_upload".
  bool get canUpload => permission == 'view_upload';

  /// True when the share has not yet expired (or has no expiry).
  bool get isActive {
    final exp = expiresAt;
    return exp == null || exp.isAfter(DateTime.now());
  }

  static bool _parseBool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v != 0;
    if (v is String) return v == 'true' || v == '1' || v == 'yes';
    return false;
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString());
    } catch (_) {
      return null;
    }
  }
}

/// Top-level response for GET /api/shares/folders/:folderId/members
class FolderMembersResponse {
  final String folderId;
  final String folderName;
  final int totalMembers;

  /// Sorted alphabetically by [FolderMember.fullName] (server-side).
  final List<FolderMember> members;

  const FolderMembersResponse({
    required this.folderId,
    required this.folderName,
    required this.totalMembers,
    required this.members,
  });

  factory FolderMembersResponse.fromJson(Map<String, dynamic> json) {
    final rawMembers = json['members'];
    final memberList = rawMembers is List ? rawMembers : const [];
    return FolderMembersResponse(
      folderId: (json['folderId'] ?? json['folder_id'] ?? '').toString(),
      folderName: (json['folderName'] ?? json['folder_name'] ?? '').toString(),
      totalMembers:
          (json['totalMembers'] ?? json['total_members'] ?? memberList.length)
              is int
          ? (json['totalMembers'] ?? json['total_members'] ?? memberList.length)
                as int
          : int.tryParse(
                  (json['totalMembers'] ?? json['total_members'] ?? '')
                      .toString(),
                ) ??
                memberList.length,
      members: memberList
          .whereType<Map>()
          .map((m) => FolderMember.fromJson(Map<String, dynamic>.from(m)))
          .toList(),
    );
  }

  /// Convenience: members who have a direct share (not only via groups).
  List<FolderMember> get directMembers =>
      members.where((m) => m.accessType == FolderAccessType.direct).toList();

  /// Convenience: members who only have access through a group.
  List<FolderMember> get groupOnlyMembers =>
      members.where((m) => m.accessType == FolderAccessType.group).toList();
}
