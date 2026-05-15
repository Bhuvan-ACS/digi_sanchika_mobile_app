import 'package:flutter/material.dart';
import 'package:digi_sanchika/services/notifications_service.dart';
import 'package:digi_sanchika/models/app_notification.dart';
import 'package:digi_sanchika/utils/app_theme.dart';
import 'package:digi_sanchika/utils/responsive_helper.dart';
import 'package:digi_sanchika/widgets/shimmer_loader.dart';
import 'package:digi_sanchika/widgets/empty_state_widget.dart';
import 'package:digi_sanchika/widgets/app_snackbar.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final NotificationsService _service = NotificationsService();

  bool _isLoading = true;
  String? _error;
  List<AppNotification> _notifications = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadNotifications();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final items = await _service.fetchNotifications(limit: 50, offset: 0);
      if (mounted) setState(() => _notifications = items);
    } catch (_) {
      if (mounted) setState(() => _error = 'Failed to load notifications');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<AppNotification> get _allNotifications => _notifications;
  List<AppNotification> get _unreadNotifications =>
      _notifications.where((n) => !n.read).toList();

  // ── Type-based icon + color ──────────────────────────────────────────────

  static ({IconData icon, Color color, Color bg}) _typeStyle(String? type) {
    switch ((type ?? '').toLowerCase()) {
      case 'success':
        return (
          icon: Icons.check_circle_rounded,
          color: AppColors.success,
          bg: AppColors.successLight,
        );
      case 'warning':
        return (
          icon: Icons.warning_amber_rounded,
          color: AppColors.warning,
          bg: const Color(0xFFFEF3C7),
        );
      case 'error':
      case 'alert':
        return (
          icon: Icons.error_rounded,
          color: AppColors.error,
          bg: AppColors.errorLight,
        );
      case 'document':
      case 'file':
        return (
          icon: Icons.insert_drive_file_rounded,
          color: AppColors.primary,
          bg: AppColors.primaryContainer,
        );
      case 'folder':
        return (
          icon: Icons.folder_rounded,
          color: AppColors.warning,
          bg: const Color(0xFFFEF3C7),
        );
      case 'system':
        return (
          icon: Icons.settings_rounded,
          color: AppColors.textSecondary,
          bg: AppColors.surfaceVariant,
        );
      default:
        return (
          icon: Icons.notifications_rounded,
          color: AppColors.primary,
          bg: AppColors.primaryContainer,
        );
    }
  }

  // ── Notification item card ───────────────────────────────────────────────

  Widget _buildNotificationItem(AppNotification n) {
    final style = _typeStyle(n.type);
    final isUnread = !n.read;

    return GestureDetector(
      onTap: () async {
        if (!isUnread) return;
        await _service.markRead(n.id);
        if (mounted) {
          setState(() {
            _notifications = _notifications
                .map((x) => x.id == n.id
                    ? AppNotification(
                        id: x.id,
                        title: x.title,
                        message: x.message,
                        type: x.type,
                        createdAt: x.createdAt,
                        read: true,
                      )
                    : x)
                .toList();
          });
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: isUnread
              ? AppColors.primaryContainer.withAlpha(80)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: AppShadows.xs,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Stack(
            children: [
              // Uniform border (required when using borderRadius)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
              ),
              // Left accent stripe for unread
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: isUnread ? AppColors.primary : Colors.transparent,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Type icon bubble
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: style.bg,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Icon(style.icon, size: 20, color: style.color),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  n.title,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isUnread
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                    color: AppColors.textPrimary,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                              if (isUnread) ...[
                                const SizedBox(width: 8),
                                Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.only(top: 4),
                                  decoration: const BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            n.message,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              height: 1.4,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if ((n.createdAt ?? '').isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(
                                  Icons.access_time_rounded,
                                  size: 11,
                                  color: AppColors.textTertiary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  n.createdAt!,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Bulk actions ─────────────────────────────────────────────────────────

  Future<void> _markAllAsRead() async {
    await _service.markAllRead();
    if (!mounted) return;
    setState(() {
      _notifications = _notifications
          .map((n) => AppNotification(
                id: n.id,
                title: n.title,
                message: n.message,
                type: n.type,
                createdAt: n.createdAt,
                read: true,
              ))
          .toList();
    });
    AppSnackbar.success(context, 'All notifications marked as read');
  }

  Future<void> _clearAll() async {
    await _service.clearAll();
    if (!mounted) return;
    setState(() => _notifications = []);
    AppSnackbar.info(context, 'All notifications cleared');
  }

  // ── List pane ────────────────────────────────────────────────────────────

  Widget _buildNotificationsList(List<AppNotification> notifications) {
    if (_isLoading) {
      return const ShimmerNotificationLoader();
    }

    if (_error != null) {
      return EmptyStateWidget(
        icon: Icons.wifi_off_rounded,
        title: 'Could not load notifications',
        subtitle: _error,
        action: TextButton.icon(
          onPressed: _loadNotifications,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Retry'),
        ),
      );
    }

    if (notifications.isEmpty) {
      return EmptyStateWidget(
        icon: Icons.notifications_none_rounded,
        title: 'No notifications',
        subtitle: 'You\'re all caught up — check back later.',
      );
    }

    return Column(
      children: [
        // Action bar
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          child: Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.mark_email_read_rounded,
                  label: 'Mark All Read',
                  color: AppColors.primary,
                  onTap: _markAllAsRead,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
                  icon: Icons.delete_sweep_rounded,
                  label: 'Clear All',
                  color: AppColors.error,
                  onTap: _clearAll,
                ),
              ),
            ],
          ),
        ),

        // List
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            final r = ResponsiveHelper.of(context);
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: r.isDesktop ? 720 : double.infinity,
                ),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                  itemCount: notifications.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) =>
                      _buildNotificationItem(notifications[i]),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  // ── Scaffold ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final totalUnread = _unreadNotifications.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Notifications',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 19,
            color: Colors.white,
          ),
        ),
        backgroundColor: AppColors.primary,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withAlpha(178),
          labelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          tabs: [
            const Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_rounded, size: 17),
                  SizedBox(width: 6),
                  Text('All'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.mark_email_unread_rounded, size: 17),
                  const SizedBox(width: 6),
                  const Text('Unread'),
                  if (totalUnread > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius:
                            BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        totalUnread > 99 ? '99+' : '$totalUnread',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildNotificationsList(_allNotifications),
          _buildNotificationsList(_unreadNotifications),
        ],
      ),
    );
  }
}

// ── Action button ──────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withAlpha(120)),
        backgroundColor: color.withAlpha(12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        padding: const EdgeInsets.symmetric(vertical: 10),
      ),
    );
  }
}
