// lib/models/recent_activity.dart

/// One audit-log entry returned by `GET /api/user/recent-activity`.
class RecentActivity {
  final String id;
  final String action;
  final String? resourceType;
  final String? resourceId;
  final Map<String, dynamic> metadata;
  final DateTime? createdAt;

  RecentActivity({
    required this.id,
    required this.action,
    this.resourceType,
    this.resourceId,
    this.metadata = const {},
    this.createdAt,
  });

  factory RecentActivity.fromJson(Map<String, dynamic> json) {
    final meta = json['metadata'];
    return RecentActivity(
      id: json['id']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      resourceType: json['resource_type']?.toString(),
      resourceId: json['resource_id']?.toString(),
      metadata: meta is Map ? Map<String, dynamic>.from(meta) : const {},
      createdAt: DateTime.tryParse(
        json['created_at']?.toString() ?? '',
      )?.toLocal(),
    );
  }
}
