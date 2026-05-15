class PasswordResetRequest {
  final String id;
  final String email;
  final String? ip;
  final String? userAgent;
  final String status; // pending | resolved | rejected
  final String? createdAt;

  const PasswordResetRequest({
    required this.id,
    required this.email,
    this.ip,
    this.userAgent,
    required this.status,
    this.createdAt,
  });

  factory PasswordResetRequest.fromJson(Map<String, dynamic> json) {
    return PasswordResetRequest(
      id: (json['id'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      ip: json['ip']?.toString(),
      userAgent: (json['userAgent'] ?? json['user_agent'])?.toString(),
      status: (json['status'] ?? 'pending').toString(),
      createdAt: (json['createdAt'] ?? json['created_at'])?.toString(),
    );
  }
}

