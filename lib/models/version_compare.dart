class VersionCompare {
  final String documentId;
  final String fromVersion;
  final String toVersion;
  final String? diff;
  final String? compareUrl;

  VersionCompare({
    required this.documentId,
    required this.fromVersion,
    required this.toVersion,
    this.diff,
    this.compareUrl,
  });

  factory VersionCompare.fromJson(Map<String, dynamic> json) {
    return VersionCompare(
      documentId: json['document_id']?.toString() ?? '',
      fromVersion: json['versionFrom']?.toString() ??
          json['from']?.toString() ??
          '',
      toVersion:
          json['versionTo']?.toString() ?? json['to']?.toString() ?? '',
      diff: json['diff']?.toString(),
      compareUrl: json['compareUrl']?.toString() ?? json['url']?.toString(),
    );
  }
}
