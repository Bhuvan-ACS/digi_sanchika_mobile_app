class CollaborationStatus {
  final String level; // view_only, comment, annotate, moderate
  final bool isLocked;

  const CollaborationStatus({required this.level, required this.isLocked});

  factory CollaborationStatus.fromJson(Map<String, dynamic> json) {
    return CollaborationStatus(
      level: (json['level'] ?? json['collaborationLevel'] ?? 'view_only').toString(),
      isLocked: (json['isLocked'] ?? json['is_locked'] ?? false) == true,
    );
  }
}

class DocumentComment {
  final String id;
  final String documentId;
  final String? parentId;
  final String content;
  final int? pageNumber;
  final double? x;
  final double? y;
  final String visibility; // public, team, private
  final bool isResolved;
  final DateTime? resolvedAt;
  final String? resolvedBy;
  final String? createdBy;
  final String? creatorName;
  final String? creatorAvatar;
  final int replyCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const DocumentComment({
    required this.id,
    required this.documentId,
    required this.parentId,
    required this.content,
    this.pageNumber,
    this.x,
    this.y,
    required this.visibility,
    required this.isResolved,
    this.resolvedAt,
    this.resolvedBy,
    this.createdBy,
    this.creatorName,
    this.creatorAvatar,
    required this.replyCount,
    this.createdAt,
    this.updatedAt,
  });

  static double? _toNullableDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static DateTime? _parseDate(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString());

  factory DocumentComment.fromJson(Map<String, dynamic> json) {
    return DocumentComment(
      id: (json['id'] ?? '').toString(),
      documentId: (json['document_id'] ?? json['documentId'] ?? '').toString(),
      parentId: (json['parent_id'] ?? json['parentId'])?.toString(),
      content: (json['content'] ?? '').toString(),
      pageNumber: json['page_number'] is int
          ? json['page_number'] as int
          : int.tryParse((json['page_number'] ?? json['pageNumber'] ?? '').toString()),
      x: _toNullableDouble(json['x']),
      y: _toNullableDouble(json['y']),
      visibility: (json['visibility'] ?? 'public').toString(),
      isResolved: (json['is_resolved'] ?? json['isResolved'] ?? false) == true,
      resolvedAt: _parseDate(json['resolved_at'] ?? json['resolvedAt']),
      resolvedBy: (json['resolved_by'] ?? json['resolvedBy'])?.toString(),
      createdBy: (json['created_by'] ?? json['createdBy'])?.toString(),
      creatorName: (json['creator_name'] ?? json['creatorName'])?.toString(),
      creatorAvatar: (json['creator_avatar'] ?? json['creatorAvatar'])?.toString(),
      replyCount: (json['reply_count'] is int)
          ? json['reply_count'] as int
          : int.tryParse((json['reply_count'] ?? json['replyCount'] ?? '0').toString()) ?? 0,
      createdAt: _parseDate(json['created_at'] ?? json['createdAt']),
      updatedAt: _parseDate(json['updated_at'] ?? json['updatedAt']),
    );
  }
}

