import 'package:digi_sanchika/models/password_reset_request.dart';
import 'package:digi_sanchika/services/admin_password_reset_service.dart';
import 'package:digi_sanchika/utils/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:digi_sanchika/widgets/responsive_page.dart';

class AdminPasswordResetRequestsScreen extends StatefulWidget {
  const AdminPasswordResetRequestsScreen({super.key});

  @override
  State<AdminPasswordResetRequestsScreen> createState() =>
      _AdminPasswordResetRequestsScreenState();
}

class _AdminPasswordResetRequestsScreenState
    extends State<AdminPasswordResetRequestsScreen>
    with SingleTickerProviderStateMixin {
  final AdminPasswordResetService _service = AdminPasswordResetService();
  late final TabController _tabs;

  bool _loading = true;
  List<PasswordResetRequest> _pending = const [];
  List<PasswordResetRequest> _resolved = const [];
  List<PasswordResetRequest> _rejected = const [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final p = await _service.listRequests(status: 'pending');
    final r = await _service.listRequests(status: 'resolved');
    final j = await _service.listRequests(status: 'rejected');
    if (!mounted) return;
    setState(() {
      _pending = p.requests;
      _resolved = r.requests;
      _rejected = j.requests;
      _loading = false;
    });
  }

  Future<void> _reject(PasswordResetRequest req) async {
    final note = await _promptText(
      title: 'Reject request?',
      hint: 'Optional note',
    );
    if (note == null) return;

    final confirmed = await _confirm(
      title: 'Reject password reset request',
      message: 'Reject reset request for ${req.email}?',
      confirmText: 'Reject',
      danger: true,
    );
    if (confirmed != true) return;

    final result = await _service.rejectRequest(req.id, note: note);
    if (!mounted) return;
    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request rejected')),
      );
      await _load();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result['message']?.toString() ?? 'Reject failed'),
        backgroundColor: AppColors.error,
      ),
    );
  }

  Future<void> _reset(PasswordResetRequest req) async {
    final password = await _promptText(
      title: 'Set temporary password',
      hint: 'TempPass@2026',
      isPassword: true,
    );
    if (password == null || password.trim().isEmpty) return;

    final forceChange = await _confirm(
      title: 'Force change on next login?',
      message:
          'Require ${req.email} to change password immediately after login?',
      confirmText: 'Yes',
      cancelText: 'No',
    );

    final confirmed = await _confirm(
      title: 'Reset password',
      message: 'Reset password for ${req.email}?',
      confirmText: 'Reset',
      danger: true,
    );
    if (confirmed != true) return;

    final result = await _service.resetFromRequest(
      req.id,
      newPassword: password.trim(),
      forceChangeOnLogin: forceChange == true,
    );
    if (!mounted) return;
    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset successfully')),
      );
      await _load();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result['message']?.toString() ?? 'Reset failed'),
        backgroundColor: AppColors.error,
      ),
    );
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmText,
    String cancelText = 'Cancel',
    bool danger = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancelText),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: danger ? AppColors.error : AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  Future<String?> _promptText({
    required String title,
    required String hint,
    bool isPassword = false,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          obscureText: isPassword,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Widget _buildList(List<PasswordResetRequest> items,
      {required bool actions}) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) {
      return const Center(child: Text('No requests'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          final req = items[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withAlpha(18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.lock_reset_rounded,
                            color: AppColors.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              req.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              req.createdAt ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _statusColor(req.status).withAlpha(18),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: _statusColor(req.status).withAlpha(60)),
                        ),
                        child: Text(
                          req.status,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _statusColor(req.status),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if ((req.ip ?? '').trim().isNotEmpty ||
                      (req.userAgent ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      [
                        if ((req.ip ?? '').trim().isNotEmpty) 'IP: ${req.ip}',
                        if ((req.userAgent ?? '').trim().isNotEmpty)
                          'UA: ${req.userAgent}',
                      ].join(' • '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ],
                  if (actions) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _reject(req),
                            icon: const Icon(Icons.close_rounded, size: 18),
                            label: const Text('Reject'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.error,
                              side: const BorderSide(color: AppColors.errorBorder),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _reset(req),
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: const Text('Reset'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Color _statusColor(String status) {
    final s = status.toLowerCase().trim();
    if (s.contains('pending')) return AppColors.warning;
    if (s.contains('resolved')) return AppColors.success;
    if (s.contains('reject')) return AppColors.error;
    return Colors.grey.shade700;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Password Reset Requests'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Resolved'),
            Tab(text: 'Rejected'),
          ],
        ),
      ),
      body: ResponsivePage(
        padding: EdgeInsets.zero,
        child: TabBarView(
          controller: _tabs,
          children: [
            _buildList(_pending, actions: true),
            _buildList(_resolved, actions: false),
            _buildList(_rejected, actions: false),
          ],
        ),
      ),
    );
  }
}
