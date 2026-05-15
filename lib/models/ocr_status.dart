class OcrStatus {
  final String documentId;
  final String status;
  final String? message;

  OcrStatus({
    required this.documentId,
    required this.status,
    this.message,
  });

  factory OcrStatus.fromJson(Map<String, dynamic> json) {
    return OcrStatus(
      documentId: json['document_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'unknown',
      message: json['message']?.toString(),
    );
  }
}
