class AppNotification {
  final String id;
  final String title;
  final String message;
  final String? type;
  final String? category;
  final String? url;
  final String? createdAt;
  final bool read;

  AppNotification({
    required this.id,
    required this.title,
    required this.message,
    this.type,
    this.category,
    this.url,
    this.createdAt,
    required this.read,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final metadata = json['metadata'];
    String? url;
    if (metadata is Map) {
      url = (metadata['url'] ?? metadata['path'])?.toString();
    }
    return AppNotification(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Notification',
      message: json['message']?.toString() ?? json['body']?.toString() ?? '',
      type: json['type']?.toString(),
      category: json['category']?.toString(),
      url: url ?? json['url']?.toString(),
      createdAt: json['created_at']?.toString(),
      read:
          json['read'] == true ||
          (json['read_at'] != null &&
              json['read_at'].toString().trim().isNotEmpty),
    );
  }
}
