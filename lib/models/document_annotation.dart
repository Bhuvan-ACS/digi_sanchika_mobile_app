class DocumentAnnotation {
  final String id;
  final String documentId;
  final int? documentVersion;
  final String type; // highlight, underline, ...
  final int? pageNumber;
  final double x;
  final double y;
  final double width;
  final double height;
  final String? content;
  final String? colorHex;
  final double? opacity;
  final double? strokeWidth;
  final String visibility; // public, team, private
  final bool isDeleted;
  final String? createdBy;
  final String? creatorName;
  final String? creatorAvatar;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const DocumentAnnotation({
    required this.id,
    required this.documentId,
    this.documentVersion,
    required this.type,
    this.pageNumber,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.content,
    this.colorHex,
    this.opacity,
    this.strokeWidth,
    required this.visibility,
    required this.isDeleted,
    this.createdBy,
    this.creatorName,
    this.creatorAvatar,
    this.createdAt,
    this.updatedAt,
  });

  static double _toDouble(dynamic v, {double fallback = 0}) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  factory DocumentAnnotation.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString());

    return DocumentAnnotation(
      id: (json['id'] ?? '').toString(),
      documentId: (json['document_id'] ?? json['documentId'] ?? '').toString(),
      documentVersion: json['document_version'] is int
          ? json['document_version'] as int
          : int.tryParse((json['document_version'] ?? json['documentVersion'] ?? '').toString()),
      type: (json['type'] ?? '').toString(),
      pageNumber: json['page_number'] is int
          ? json['page_number'] as int
          : int.tryParse((json['page_number'] ?? json['pageNumber'] ?? '').toString()),
      x: _toDouble(json['x']),
      y: _toDouble(json['y']),
      width: _toDouble(json['width']),
      height: _toDouble(json['height']),
      content: json['content']?.toString(),
      colorHex: (json['color'] ?? json['colorHex'])?.toString(),
      opacity: json['opacity'] == null ? null : _toDouble(json['opacity']),
      strokeWidth: json['stroke_width'] == null && json['strokeWidth'] == null
          ? null
          : _toDouble(json['stroke_width'] ?? json['strokeWidth']),
      visibility: (json['visibility'] ?? 'public').toString(),
      isDeleted: (json['is_deleted'] ?? json['isDeleted'] ?? false) == true,
      createdBy: (json['created_by'] ?? json['createdBy'])?.toString(),
      creatorName: (json['creator_name'] ?? json['creatorName'])?.toString(),
      creatorAvatar: (json['creator_avatar'] ?? json['creatorAvatar'])?.toString(),
      createdAt: parseDate(json['created_at'] ?? json['createdAt']),
      updatedAt: parseDate(json['updated_at'] ?? json['updatedAt']),
    );
  }
}

