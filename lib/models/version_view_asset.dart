class VersionViewAsset {
  final String url;
  final String? conversionStatus;
  final String? conversionError;
  final bool isPdf;
  final String? mimeType;

  VersionViewAsset({
    required this.url,
    this.conversionStatus,
    this.conversionError,
    required this.isPdf,
    this.mimeType,
  });

  factory VersionViewAsset.fromJson(Map<String, dynamic> json) {
    final url = (json['url'] ?? json['viewUrl'])?.toString() ?? '';
    return VersionViewAsset(
      url: url,
      conversionStatus: json['conversionStatus']?.toString(),
      conversionError: json['conversionError']?.toString(),
      isPdf: json['isPdf'] == true,
      mimeType: (json['mimeType'] ?? json['mime_type'])?.toString(),
    );
  }
}

