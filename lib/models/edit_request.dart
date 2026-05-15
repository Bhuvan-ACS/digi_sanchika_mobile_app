class EditRequest {
  final String id;
  final String documentId;
  final String status;
  final String? reason;
  final String? createdAt;
  final String? approvedAt;
  final String? documentName;
  final String? requesterName;
  final String? requesterEmail;

  EditRequest({
    required this.id,
    required this.documentId,
    required this.status,
    this.reason,
    this.createdAt,
    this.approvedAt,
    this.documentName,
    this.requesterName,
    this.requesterEmail,
  });

  factory EditRequest.fromJson(Map<String, dynamic> json) {
    final document = json['document'] is Map<String, dynamic>
        ? json['document'] as Map<String, dynamic>
        : null;
    final requester = json['requester'] is Map<String, dynamic>
        ? json['requester'] as Map<String, dynamic>
        : null;

    String? docName = json['document_name']?.toString();
    docName ??= json['documentName']?.toString();
    docName ??= document?['name']?.toString();
    docName ??= document?['original_name']?.toString();
    docName ??= document?['original_filename']?.toString();
    docName ??= document?['file_name']?.toString();
    docName ??= document?['filename']?.toString();

    String? reqName = json['requester_name']?.toString();
    reqName ??= json['requesterName']?.toString();
    reqName ??= requester?['name']?.toString();
    reqName ??= requester?['full_name']?.toString();

    String? reqEmail = json['requester_email']?.toString();
    reqEmail ??= json['requesterEmail']?.toString();
    reqEmail ??= requester?['email']?.toString();
    reqEmail ??= requester?['user_email']?.toString();

    return EditRequest(
      id: json['id']?.toString() ?? '',
      documentId:
          json['document_id']?.toString() ??
          json['documentId']?.toString() ??
          document?['id']?.toString() ??
          '',
      status: json['status']?.toString() ?? 'unknown',
      reason: json['reason']?.toString(),
      createdAt: json['created_at']?.toString(),
      approvedAt: json['approved_at']?.toString(),
      documentName: docName?.trim().isEmpty == true ? null : docName?.trim(),
      requesterName: reqName?.trim().isEmpty == true ? null : reqName?.trim(),
      requesterEmail:
          reqEmail?.trim().isEmpty == true ? null : reqEmail?.trim(),
    );
  }
}
