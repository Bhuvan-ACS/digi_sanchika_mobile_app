class VersionInfo {
  final String version;
  final String name;
  final String? mimeType;
  final int? fileSizeBytes;
  final String? contentHash;
  final String? classification;
  final String? keywords;
  final String? remarks;
  final String? changeNote;
  final String? createdBy;
  final String? authorName;
  final String? createdAt;

  VersionInfo({
    required this.version,
    required this.name,
    this.mimeType,
    this.fileSizeBytes,
    this.contentHash,
    this.classification,
    this.keywords,
    this.remarks,
    this.changeNote,
    this.createdBy,
    this.authorName,
    this.createdAt,
  });

  factory VersionInfo.fromJson(Map<String, dynamic> json) {
    String safeString(dynamic v) => v == null ? '' : v.toString();

    int? safeInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      return int.tryParse(v.toString());
    }

    return VersionInfo(
      version:
          safeString(json['version_number'] ?? json['version']).trim().isEmpty
              ? safeString(json['version']).trim()
              : safeString(json['version_number'] ?? json['version']).trim(),
      name: safeString(json['name'] ?? json['file_name'] ?? json['filename']),
      mimeType: (json['mime_type'] ?? json['mimeType'])?.toString(),
      fileSizeBytes: safeInt(json['file_size_bytes'] ?? json['fileSizeBytes']),
      contentHash: (json['content_hash'] ?? json['contentHash'])?.toString(),
      classification: json['classification']?.toString(),
      keywords: json['keywords']?.toString(),
      remarks: (json['remarks'] ?? json['remark'])?.toString(),
      changeNote: (json['change_note'] ?? json['changeNote'])?.toString(),
      createdBy: (json['created_by'] ?? json['createdBy'])?.toString(),
      authorName: (json['author_name'] ?? json['authorName'])?.toString(),
      createdAt: (json['created_at'] ?? json['createdAt'])?.toString(),
    );
  }
}

