// lib/models/profile.dart
class UserProfile {
  final String employeeName;
  final String employeeId;
  final String department;
  final String email;
  final bool isAdmin;
  final bool isActive;
  final String? createdAt;
  final String? lastLoginAt;
  final String? lastLoginIp;
  final int? failedLoginAttempts;

  UserProfile({
    required this.employeeName,
    required this.employeeId,
    required this.department,
    required this.email,
    required this.isAdmin,
    required this.isActive,
    this.createdAt,
    this.lastLoginAt,
    this.lastLoginIp,
    this.failedLoginAttempts,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final user =
        json['user'] is Map<String, dynamic>
            ? json['user'] as Map<String, dynamic>
            : json;
    final rolesRaw = json['roles'] ?? user['roles'] ?? [];
    final roles =
        rolesRaw is List ? rolesRaw.map((e) => e.toString()).toList() : <String>[];
    final isAdmin =
        roles.any((r) => r.toLowerCase().contains('admin')) ||
        user['is_admin'] == true ||
        user['isAdmin'] == true;

    return UserProfile(
      employeeName:
          user['full_name'] ??
          user['fullName'] ??
          user['employeeName'] ??
          user['name'] ??
          'Unknown',
      employeeId:
          user['employee_id']?.toString() ??
          user['employeeId']?.toString() ??
          'Unknown',
      department:
          user['department'] ??
          user['dept'] ??
          user['dept_name'] ??
          'Not Assigned',
      email: user['email'] ?? 'Not Provided',
      isAdmin: isAdmin,
      isActive:
          user['is_active'] ??
          user['isActive'] ??
          true,
      createdAt: user['created_at']?.toString() ?? user['createdAt']?.toString(),
      lastLoginAt: user['last_login_at']?.toString(),
      lastLoginIp: user['last_login_ip']?.toString(),
      failedLoginAttempts:
          int.tryParse(user['failed_login_attempts']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'employeeName': employeeName,
      'employeeId': employeeId,
      'department': department,
      'email': email,
      'isAdmin': isAdmin,
      'isActive': isActive,
      'createdAt': createdAt,
      'lastLoginAt': lastLoginAt,
      'lastLoginIp': lastLoginIp,
      'failedLoginAttempts': failedLoginAttempts,
    };
  }
}
