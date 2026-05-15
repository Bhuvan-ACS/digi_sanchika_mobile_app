import 'package:dio/dio.dart';
import 'package:digi_sanchika/models/group.dart';
import 'package:digi_sanchika/models/group_member.dart';
import 'package:digi_sanchika/services/api_client.dart';

class GroupDetails {
  final Group group;
  final List<GroupMember> members;
  final int shareCount;

  const GroupDetails({
    required this.group,
    required this.members,
    required this.shareCount,
  });
}

class GroupsService {
  Dio get _dio => ApiClient.instance.dio;

  String get _groupsBasePath {
    final base = ApiClient.instance.baseUrl;
    final uri = Uri.tryParse(base);
    final basePath = (uri?.path ?? '').trim();
    final normalized = basePath.endsWith('/')
        ? basePath.substring(0, basePath.length - 1)
        : basePath;
    return normalized.endsWith('/api') ? '/groups' : '/api/groups';
  }

  Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  List<dynamic> _asList(dynamic v) => v is List ? v : const [];

  Future<List<Group>> listGroups() async {
    final resp = await _dio.get(_groupsBasePath);
    if (resp.statusCode != 200) return const [];
    final data = resp.data;

    // Support multiple server response shapes:
    // - List<GroupJson>
    // - { groups: [...] } or { items: [...] } or { data: [...] }
    // - { data: { groups: [...] } }
    List<dynamic> items = const [];
    if (data is List) {
      items = data;
    } else {
      final map = _asMap(data);
      if (map == null) return const [];
      final nested = _asMap(map['data']);
      items = _asList(
        map['groups'] ??
            map['items'] ??
            map['data'] ??
            nested?['groups'] ??
            nested?['items'],
      );
    }

    return items
        .map((e) => _asMap(e))
        .whereType<Map<String, dynamic>>()
        .map(Group.fromJson)
        .where((g) => g.id.isNotEmpty && g.name.isNotEmpty)
        .toList();
  }

  Future<GroupDetails?> getGroupDetails(String groupId) async {
    final resp = await _dio.get('$_groupsBasePath/$groupId');
    if (resp.statusCode != 200) return null;
    final map = _asMap(resp.data);
    if (map == null) return null;

    final groupMap = _asMap(map['group']) ?? map;
    final members = _asList(map['members']).map((e) => _asMap(e)).whereType<Map<String, dynamic>>().map(GroupMember.fromJson).toList();
    final shareCountRaw = map['shareCount'] ?? map['share_count'] ?? 0;
    final shareCount = shareCountRaw is int ? shareCountRaw : int.tryParse(shareCountRaw.toString()) ?? 0;

    final group = Group.fromJson(groupMap);
    if (group.id.isEmpty) return null;
    return GroupDetails(group: group, members: members, shareCount: shareCount);
  }

  Future<List<Map<String, dynamic>>> listGroupShares(String groupId) async {
    final resp = await _dio.get('$_groupsBasePath/$groupId/shares');
    if (resp.statusCode != 200) return const [];
    final map = _asMap(resp.data);
    if (map == null) return const [];
    final docs = _asList(map['documentShares'] ?? map['document_shares']);
    final folders = _asList(map['folderShares'] ?? map['folder_shares']);
    return [
      ...docs.map((e) => _asMap(e)).whereType<Map<String, dynamic>>(),
      ...folders.map((e) => _asMap(e)).whereType<Map<String, dynamic>>(),
    ];
  }

  Future<bool> createGroup({
    required String name,
    String? description,
    String? colorHex,
    String? avatarEmoji,
  }) async {
    final payload = <String, dynamic>{
      'name': name,
      if (description != null) 'description': description,
      if (colorHex != null) 'color': colorHex,
      if (avatarEmoji != null) 'avatarEmoji': avatarEmoji,
    };
    final resp = await _dio.post(_groupsBasePath, data: payload);
    return resp.statusCode == 201 || resp.statusCode == 200;
  }

  Future<bool> updateGroup(
    String groupId, {
    String? name,
    String? description,
    String? colorHex,
    String? avatarEmoji,
    bool? isActive,
  }) async {
    final payload = <String, dynamic>{
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (colorHex != null) 'color': colorHex,
      if (avatarEmoji != null) 'avatarEmoji': avatarEmoji,
      if (isActive != null) 'isActive': isActive,
      if (isActive != null) 'is_active': isActive,
    };
    final resp = await _dio.patch('$_groupsBasePath/$groupId', data: payload);
    return resp.statusCode == 200;
  }

  Future<bool> deleteGroup(String groupId) async {
    final resp = await _dio.delete('$_groupsBasePath/$groupId');
    return resp.statusCode == 200;
  }

  Future<List<GroupMember>> listMembers(String groupId) async {
    final resp = await _dio.get('$_groupsBasePath/$groupId/members');
    if (resp.statusCode != 200) return const [];
    final map = _asMap(resp.data);
    if (map == null) return const [];
    final items = _asList(map['members'] ?? map['items'] ?? map['data']);
    return items
        .map((e) => _asMap(e))
        .whereType<Map<String, dynamic>>()
        .map(GroupMember.fromJson)
        .toList();
  }

  Future<bool> addMember(
    String groupId, {
    required String userId,
    String role = 'member',
  }) async {
    final resp = await _dio.post(
      '$_groupsBasePath/$groupId/members',
      data: {'userId': userId, 'role': role},
    );
    return resp.statusCode == 201 || resp.statusCode == 200;
  }

  Future<bool> updateMemberRole(
    String groupId, {
    required String userId,
    required String role,
  }) async {
    final resp = await _dio.patch(
      '$_groupsBasePath/$groupId/members/$userId',
      data: {'role': role},
    );
    return resp.statusCode == 200;
  }

  Future<bool> removeMember(String groupId, String userId) async {
    final resp = await _dio.delete('$_groupsBasePath/$groupId/members/$userId');
    return resp.statusCode == 200;
  }

  Future<List<Map<String, dynamic>>> getGroupActivity(String groupId, {int limit = 50}) async {
    final capped = limit < 1 ? 1 : (limit > 200 ? 200 : limit);
    final resp = await _dio.get('$_groupsBasePath/$groupId/activity', queryParameters: {'limit': capped});
    if (resp.statusCode != 200) return const [];
    final map = _asMap(resp.data);
    if (map == null) return const [];
    return _asList(map['activity'] ?? map['items'] ?? map['data'])
        .map((e) => _asMap(e))
        .whereType<Map<String, dynamic>>()
        .toList();
  }
}
