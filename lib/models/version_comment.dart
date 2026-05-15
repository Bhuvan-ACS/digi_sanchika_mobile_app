class VersionComment {
  final String id;
  final String documentId;
  final String version;
  final String comment;
  final bool resolved;
  final String? createdAt;

  VersionComment({
    required this.id,
    required this.documentId,
    required this.version,
    required this.comment,
    required this.resolved,
    this.createdAt,
  });

  factory VersionComment.fromJson(Map<String, dynamic> json) {
    return VersionComment(
      id: json['id']?.toString() ?? '',
      documentId: json['document_id']?.toString() ?? '',
      version: json['version']?.toString() ?? '',
      comment: json['comment']?.toString() ?? '',
      resolved: json['resolved'] == true,
      createdAt: json['created_at']?.toString(),
    );
  }
}
