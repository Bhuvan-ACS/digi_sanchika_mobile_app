class DownloadRequest {
  final String id;
  final String documentId;
  final String? folderId;
  final String? targetType;
  final String status;
  final String? reason;
  final String? createdAt;
  final String? approvedAt;
  final String? token;
  final String? documentName;
  final String? folderName;
  final String? requesterName;
  final String? requesterEmail;

  DownloadRequest({
    required this.id,
    required this.documentId,
    this.folderId,
    this.targetType,
    required this.status,
    this.reason,
    this.createdAt,
    this.approvedAt,
    this.token,
    this.documentName,
    this.folderName,
    this.requesterName,
    this.requesterEmail,
  });

  factory DownloadRequest.fromJson(Map<String, dynamic> json) {
    final document = json['document'] is Map<String, dynamic>
        ? json['document'] as Map<String, dynamic>
        : null;
    final requester = json['requester'] is Map<String, dynamic>
        ? json['requester'] as Map<String, dynamic>
        : null;

    final folder = json['folder'] is Map<String, dynamic>
        ? json['folder'] as Map<String, dynamic>
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

    final targetType =
        json['target_type']?.toString() ?? json['targetType']?.toString();
    final folderId =
        json['folder_id']?.toString() ?? json['folderId']?.toString();

    String? folderName =
        json['folder_name']?.toString() ?? json['folderName']?.toString();
    folderName ??= folder?['name']?.toString();

    return DownloadRequest(
      id: json['id']?.toString() ?? '',
      documentId:
          json['document_id']?.toString() ??
          json['documentId']?.toString() ??
          document?['id']?.toString() ??
          '',
      folderId: folderId?.trim().isEmpty == true ? null : folderId?.trim(),
      targetType: targetType?.trim().isEmpty == true ? null : targetType?.trim(),
      status: json['status']?.toString() ?? 'unknown',
      reason: json['reason']?.toString(),
      createdAt: json['created_at']?.toString(),
      approvedAt: json['approved_at']?.toString(),
      token: json['token']?.toString(),
      documentName: docName?.trim().isEmpty == true ? null : docName?.trim(),
      folderName: folderName?.trim().isEmpty == true ? null : folderName?.trim(),
      requesterName: reqName?.trim().isEmpty == true ? null : reqName?.trim(),
      requesterEmail:
          reqEmail?.trim().isEmpty == true ? null : reqEmail?.trim(),
    );
  }
}
