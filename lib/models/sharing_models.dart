import 'package:digi_sanchika/models/document.dart';
import 'package:digi_sanchika/models/shared_folder.dart';

enum ShareEntityType { document, folder }

class EffectiveAccess {
  final bool canView;
  final bool canUpload;
  final bool canDownload;
  final bool canEdit;
  final bool canComment;
  final bool canAnnotate;
  final bool canModerate;
  final bool requiresDownloadApproval;
  final bool requiresEditApproval;
  final String collaborationLevel;
  final String? expiresAt;
  final List<Map<String, dynamic>> accessSources;

  const EffectiveAccess({
    required this.canView,
    required this.canUpload,
    required this.canDownload,
    required this.canEdit,
    required this.canComment,
    required this.canAnnotate,
    required this.canModerate,
    required this.requiresDownloadApproval,
    required this.requiresEditApproval,
    required this.collaborationLevel,
    this.expiresAt,
    this.accessSources = const [],
  });

  factory EffectiveAccess.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    final level = (map['collaborationLevel'] ??
            map['collaboration_level'] ??
            'view_only')
        .toString();
    final permission = (map['permission'] ?? '').toString();
    final canDownload = _bool(map['canDownload'] ?? map['can_download']);
    final canEdit = _bool(map['canEdit'] ?? map['can_edit']);
    final canUpload = _bool(map['canUpload'] ?? map['can_upload']) ||
        permission == 'view_upload';

    return EffectiveAccess(
      canView: _bool(map['canView'] ?? map['can_view'], defaultValue: true),
      canUpload: canUpload,
      canDownload: canDownload,
      canEdit: canEdit,
      canComment: _bool(map['canComment'] ?? map['can_comment']) ||
          level == 'comment' ||
          level == 'annotate' ||
          level == 'moderate',
      canAnnotate: _bool(map['canAnnotate'] ?? map['can_annotate']) ||
          level == 'annotate' ||
          level == 'moderate',
      canModerate:
          _bool(map['canModerate'] ?? map['can_moderate']) || level == 'moderate',
      requiresDownloadApproval: _bool(
        map['requiresDownloadApproval'] ?? map['requires_download_approval'],
      ),
      requiresEditApproval:
          _bool(map['requiresEditApproval'] ?? map['requires_edit_approval']),
      collaborationLevel: level,
      expiresAt: (map['expiresAt'] ?? map['expires_at'])?.toString(),
      accessSources: _listOfMaps(map['accessSources'] ?? map['access_sources']),
    );
  }

  factory EffectiveAccess.fromShare(Map<String, dynamic>? share) {
    final map = share ?? const <String, dynamic>{};
    final allowDownload = _bool(
      map['allowDownload'] ?? map['allow_download'],
      defaultValue: false,
    );
    final allowEdit = _bool(map['allowEdit'] ?? map['allow_edit']);
    final permission = (map['permission'] ?? 'view').toString();
    return EffectiveAccess(
      canView: true,
      canUpload: permission == 'view_upload',
      canDownload: allowDownload,
      canEdit: allowEdit,
      canComment: false,
      canAnnotate: false,
      canModerate: false,
      requiresDownloadApproval: !allowDownload,
      requiresEditApproval: !allowEdit,
      collaborationLevel:
          (map['collaborationLevel'] ?? map['collaboration_level'] ?? 'view_only')
              .toString(),
      expiresAt: (map['expiresAt'] ?? map['expires_at'])?.toString(),
    );
  }

  static bool _bool(dynamic value, {bool defaultValue = false}) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    final text = value.toString().toLowerCase();
    return text == 'true' || text == '1' || text == 'yes';
  }

  static List<Map<String, dynamic>> _listOfMaps(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
}

class ShareActor {
  final String id;
  final String name;
  final String email;

  const ShareActor({this.id = '', this.name = '', this.email = ''});

  factory ShareActor.fromJson(dynamic json) {
    if (json is! Map) return const ShareActor();
    final map = Map<String, dynamic>.from(json);
    return ShareActor(
      id: (map['id'] ?? map['user_id'] ?? map['userId'] ?? '').toString(),
      name: (map['full_name'] ?? map['fullName'] ?? map['name'] ?? '')
          .toString(),
      email: (map['email'] ?? '').toString(),
    );
  }

  String get displayName => name.trim().isNotEmpty
      ? name.trim()
      : (email.trim().isNotEmpty ? email.trim() : 'Unknown User');
}

class ViaGroup {
  final String id;
  final String name;
  final String? colorHex;

  const ViaGroup({required this.id, required this.name, this.colorHex});

  factory ViaGroup.fromJson(dynamic json) {
    if (json is! Map) return const ViaGroup(id: '', name: '');
    final map = Map<String, dynamic>.from(json);
    return ViaGroup(
      id: (map['id'] ?? map['group_id'] ?? map['groupId'] ?? '').toString(),
      name: (map['name'] ?? map['group_name'] ?? map['groupName'] ?? '')
          .toString(),
      colorHex: (map['color'] ?? map['colorHex'] ?? map['group_color'])
          ?.toString(),
    );
  }

  bool get isValid => id.isNotEmpty || name.isNotEmpty;
}

class SharedItem {
  final ShareEntityType type;
  final String id;
  final String name;
  final Map<String, dynamic> rawShare;
  final Map<String, dynamic> rawEntity;
  final ShareActor sharedBy;
  final ShareActor owner;
  final ViaGroup? viaGroup;
  final EffectiveAccess access;

  const SharedItem({
    required this.type,
    required this.id,
    required this.name,
    required this.rawShare,
    required this.rawEntity,
    required this.sharedBy,
    required this.owner,
    required this.viaGroup,
    required this.access,
  });

  factory SharedItem.fromJson(
    Map<String, dynamic> json, {
    required ShareEntityType type,
  }) {
    final entityKey = type == ShareEntityType.document ? 'document' : 'folder';
    final entity = _asMap(json[entityKey]) ?? json;
    final share = _asMap(json['share']) ?? const <String, dynamic>{};
    final via = ViaGroup.fromJson(
      share['viaGroup'] ?? share['via_group'] ?? json['viaGroup'] ?? json['via_group'],
    );
    final effective = _asMap(json['effectiveAccess'] ??
            json['effective_access'] ??
            share['effectiveAccess'] ??
            share['effective_access']) ??
        <String, dynamic>{};

    final id = (entity['id'] ??
            entity['document_id'] ??
            entity['folder_id'] ??
            share['document_id'] ??
            share['folder_id'] ??
            '')
        .toString();
    final name = (entity['name'] ??
            entity['original_filename'] ??
            entity['file_name'] ??
            entity['filename'] ??
            'Untitled')
        .toString();

    return SharedItem(
      type: type,
      id: id,
      name: name,
      rawShare: share,
      rawEntity: entity,
      sharedBy: ShareActor.fromJson(json['sharedBy'] ?? json['shared_by']),
      owner: ShareActor.fromJson(json['owner']),
      viaGroup: via.isValid ? via : null,
      access: effective.isNotEmpty
          ? EffectiveAccess.fromJson(effective)
          : EffectiveAccess.fromShare(share),
    );
  }

  Document toDocument() {
    final mimeType = rawEntity['mime_type']?.toString();
    final fileType = _fileTypeFrom(rawEntity, name, mimeType);
    final actor = sharedBy.displayName != 'Unknown User'
        ? sharedBy.displayName
        : owner.displayName;
    return Document(
      id: id,
      name: name,
      type: fileType,
      size: (rawEntity['file_size_bytes'] ??
              rawEntity['file_size'] ??
              rawEntity['size'] ??
              '0')
          .toString(),
      keyword: rawEntity['keywords']?.toString() ?? '',
      uploadDate:
          (rawEntity['created_at'] ?? rawEntity['updated_at'] ?? '').toString(),
      owner: actor,
      details: rawEntity['remarks']?.toString() ??
          rawEntity['description']?.toString() ??
          '',
      classification:
          (rawEntity['classification'] ?? rawEntity['doc_class'] ?? 'internal')
              .toString(),
      allowDownload: access.canDownload,
      sharingType: 'shared',
      folder: rawEntity['folder_path']?.toString() ?? 'Shared',
      folderId: rawEntity['folder_id']?.toString(),
      path: name,
      fileType: fileType,
      sharedViaGroupId: viaGroup?.id,
      sharedViaGroupName: viaGroup?.name,
      sharedViaGroupColorHex: viaGroup?.colorHex,
      sharedByName: actor,
      expiresAt: access.expiresAt ?? rawShare['expires_at']?.toString(),
    );
  }

  SharedFolder toSharedFolder() {
    return SharedFolder(
      id: id,
      name: name,
      owner: sharedBy.displayName != 'Unknown User'
          ? sharedBy.displayName
          : owner.displayName,
      createdAt: _displayDate(rawEntity['created_at'] ?? rawShare['created_at']),
      expiresAt: access.expiresAt ?? rawShare['expires_at']?.toString() ?? '',
      itemCount: int.tryParse(
            (rawEntity['item_count'] ??
                    rawEntity['items_count'] ??
                    rawEntity['document_count'] ??
                    '')
                .toString(),
          ) ??
          -1,
      canUpload: access.canUpload,
      canDownload: access.canDownload,
      canEdit: access.canEdit,
      viaGroupName: viaGroup?.name,
      viaGroupColorHex: viaGroup?.colorHex,
    );
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static String _fileTypeFrom(
    Map<String, dynamic> map,
    String filename,
    String? mimeType,
  ) {
    final mime = mimeType?.toLowerCase() ?? '';
    if (mime.contains('pdf')) return 'pdf';
    if (mime.contains('word')) return 'docx';
    if (mime.contains('sheet') || mime.contains('excel')) return 'xlsx';
    if (mime.contains('presentation') || mime.contains('powerpoint')) {
      return 'pptx';
    }
    if (mime.startsWith('image/')) return 'image';
    final raw = (map['file_type'] ?? map['type'])?.toString();
    if (raw != null && raw.isNotEmpty) return raw;
    final parts = filename.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : 'unknown';
  }

  static String _displayDate(dynamic value) {
    if (value == null) return '';
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

class SharedWithMeResult {
  final List<SharedItem> documents;
  final List<SharedItem> folders;

  const SharedWithMeResult({required this.documents, required this.folders});

  factory SharedWithMeResult.fromJson(Map<String, dynamic> json) {
    final documents = _items(json['documents'], ShareEntityType.document);
    final folders = _items(json['folders'], ShareEntityType.folder);
    return SharedWithMeResult(documents: documents, folders: folders);
  }

  static List<SharedItem> _items(dynamic value, ShareEntityType type) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((e) => SharedItem.fromJson(Map<String, dynamic>.from(e), type: type))
        .where((e) => e.id.isNotEmpty)
        .toList();
  }
}

class ShareGrant {
  final String id;
  final ShareEntityType entityType;
  final bool isGroup;
  final String targetId;
  final String targetName;
  final String targetSubtitle;
  final String? groupColorHex;
  final String permission;
  final bool allowDownload;
  final bool allowEdit;
  final String collaborationLevel;
  final String? expiresAt;
  final bool isRevoked;
  final bool isExpired;
  final List<GroupMemberOverride> overrides;

  const ShareGrant({
    required this.id,
    required this.entityType,
    required this.isGroup,
    required this.targetId,
    required this.targetName,
    required this.targetSubtitle,
    this.groupColorHex,
    required this.permission,
    required this.allowDownload,
    required this.allowEdit,
    required this.collaborationLevel,
    this.expiresAt,
    required this.isRevoked,
    required this.isExpired,
    this.overrides = const [],
  });

  factory ShareGrant.direct(
    Map<String, dynamic> json, {
    required ShareEntityType entityType,
  }) {
    final user = ShareActor.fromJson(
      json['sharedWith'] ??
          json['shared_with'] ??
          json['recipient'] ??
          json['user'],
    );
    final email = (json['email'] ?? json['shared_with_email'] ?? user.email)
        .toString();
    final name = (json['full_name'] ??
            json['name'] ??
            user.name ??
            (email.isNotEmpty ? email : 'User'))
        .toString();
    return ShareGrant(
      id: (json['id'] ?? json['share_id'] ?? '').toString(),
      entityType: entityType,
      isGroup: false,
      targetId:
          (json['shared_with_id'] ?? json['sharedWithId'] ?? user.id).toString(),
      targetName: name,
      targetSubtitle: email,
      permission: (json['permission'] ?? 'view').toString(),
      allowDownload: EffectiveAccess._bool(json['allow_download'] ?? json['allowDownload']),
      allowEdit: EffectiveAccess._bool(json['allow_edit'] ?? json['allowEdit']),
      collaborationLevel:
          (json['collaboration_level'] ?? json['collaborationLevel'] ?? 'view_only')
              .toString(),
      expiresAt: (json['expires_at'] ?? json['expiresAt'])?.toString(),
      isRevoked: EffectiveAccess._bool(json['is_revoked'] ?? json['isRevoked']),
      isExpired: _isExpired(json['expires_at'] ?? json['expiresAt']),
    );
  }

  factory ShareGrant.group(
    Map<String, dynamic> json, {
    required ShareEntityType entityType,
  }) {
    return ShareGrant(
      id: (json['id'] ?? json['group_share_id'] ?? '').toString(),
      entityType: entityType,
      isGroup: true,
      targetId: (json['group_id'] ?? json['groupId'] ?? '').toString(),
      targetName:
          (json['group_name'] ?? json['groupName'] ?? json['name'] ?? 'Group')
              .toString(),
      targetSubtitle:
          '${json['member_count'] ?? json['memberCount'] ?? 0} members',
      groupColorHex: (json['group_color'] ?? json['color'])?.toString(),
      permission: (json['permission'] ?? 'view').toString(),
      allowDownload: EffectiveAccess._bool(json['allow_download'] ?? json['allowDownload']),
      allowEdit: EffectiveAccess._bool(json['allow_edit'] ?? json['allowEdit']),
      collaborationLevel:
          (json['collaboration_level'] ?? json['collaborationLevel'] ?? 'view_only')
              .toString(),
      expiresAt: (json['expires_at'] ?? json['expiresAt'])?.toString(),
      isRevoked: EffectiveAccess._bool(json['is_revoked'] ?? json['isRevoked']),
      isExpired: _isExpired(json['expires_at'] ?? json['expiresAt']),
      overrides: _overrideList(json['overrides']),
    );
  }

  static bool _isExpired(dynamic value) {
    if (value == null) return false;
    try {
      final date = DateTime.parse(value.toString());
      if (date.year >= 9999) return false;
      return date.isBefore(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  static List<GroupMemberOverride> _overrideList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((e) => GroupMemberOverride.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}

class ShareGrantResult {
  final List<ShareGrant> directShares;
  final List<ShareGrant> groupShares;

  const ShareGrantResult({
    required this.directShares,
    required this.groupShares,
  });
}

class PublicLinkGrant {
  final String id;
  final String token;
  final String? url;
  final bool allowView;
  final bool allowDownload;
  final String? expiresAt;

  const PublicLinkGrant({
    required this.id,
    required this.token,
    this.url,
    required this.allowView,
    required this.allowDownload,
    this.expiresAt,
  });

  factory PublicLinkGrant.fromJson(Map<String, dynamic> json) {
    final link = json['link'] is Map
        ? Map<String, dynamic>.from(json['link'] as Map)
        : json;
    return PublicLinkGrant(
      id: (link['id'] ?? '').toString(),
      token: (link['token'] ?? json['token'] ?? '').toString(),
      url: (json['url'] ?? link['url'])?.toString(),
      allowView: EffectiveAccess._bool(
        link['allow_view'] ?? link['allowView'],
        defaultValue: true,
      ),
      allowDownload:
          EffectiveAccess._bool(link['allow_download'] ?? link['allowDownload']),
      expiresAt: (link['expires_at'] ?? link['expiresAt'])?.toString(),
    );
  }
}

class GroupMemberOverride {
  final String id;
  final String userId;
  final bool accessEnabled;
  final String? permission;
  final bool? allowDownload;
  final bool? allowEdit;
  final String? collaborationLevel;
  final String? expiresAt;

  const GroupMemberOverride({
    required this.id,
    required this.userId,
    required this.accessEnabled,
    this.permission,
    this.allowDownload,
    this.allowEdit,
    this.collaborationLevel,
    this.expiresAt,
  });

  factory GroupMemberOverride.fromJson(Map<String, dynamic> json) {
    return GroupMemberOverride(
      id: (json['id'] ?? '').toString(),
      userId: (json['user_id'] ?? json['userId'] ?? '').toString(),
      accessEnabled: EffectiveAccess._bool(
        json['access_enabled'] ?? json['accessEnabled'],
        defaultValue: true,
      ),
      permission: json.containsKey('permission')
          ? json['permission']?.toString()
          : null,
      allowDownload: json.containsKey('allow_download') ||
              json.containsKey('allowDownload')
          ? EffectiveAccess._bool(json['allow_download'] ?? json['allowDownload'])
          : null,
      allowEdit: json.containsKey('allow_edit') || json.containsKey('allowEdit')
          ? EffectiveAccess._bool(json['allow_edit'] ?? json['allowEdit'])
          : null,
      collaborationLevel:
          (json['collaboration_level'] ?? json['collaborationLevel'])?.toString(),
      expiresAt: (json['expires_at'] ?? json['expiresAt'])?.toString(),
    );
  }
}
