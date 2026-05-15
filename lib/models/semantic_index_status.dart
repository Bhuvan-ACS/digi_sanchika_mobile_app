class SemanticIndexStatus {
  final String documentId;
  final String status;
  final String? message;

  SemanticIndexStatus({
    required this.documentId,
    required this.status,
    this.message,
  });

  factory SemanticIndexStatus.fromJson(Map<String, dynamic> json) {
    return SemanticIndexStatus(
      documentId: json['document_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'unknown',
      message: json['message']?.toString(),
    );
  }
}
