class ConversionStatus {
  final String documentId;
  final String status;
  final String? message;

  ConversionStatus({
    required this.documentId,
    required this.status,
    this.message,
  });

  factory ConversionStatus.fromJson(Map<String, dynamic> json) {
    return ConversionStatus(
      documentId: json['document_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'unknown',
      message: json['message']?.toString(),
    );
  }
}
