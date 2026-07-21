// ignore_for_file: use_build_context_synchronously
import 'package:digi_sanchika/utils/app_fonts.dart';
import 'package:flutter/material.dart';
import 'package:digi_sanchika/services/permission_service.dart';
import 'package:digi_sanchika/services/profile_service.dart';
import 'package:digi_sanchika/models/profile.dart';
import 'package:digi_sanchika/presentations/Screens/change_password.dart';
import 'package:digi_sanchika/presentations/Screens/download_requests_screen.dart';
import 'package:digi_sanchika/presentations/Screens/edit_requests_screen.dart';
import 'package:digi_sanchika/presentations/Screens/admin_password_reset_requests_screen.dart';
import 'package:digi_sanchika/presentations/Screens/favorites_screen.dart';
import 'package:digi_sanchika/presentations/Screens/recycle_bin_screen.dart';
import 'package:digi_sanchika/presentations/Screens/profile_details_screen.dart';
import 'package:digi_sanchika/services/api_service.dart';
import 'package:digi_sanchika/utils/app_theme.dart';
import 'package:digi_sanchika/widgets/confirm_dialog.dart';
import 'package:digi_sanchika/widgets/permissions_modal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

// ─── Colour tokens ────────────────────────────────────────────────────────────
const _kPrimary       = Color(0xFF2D4EE8);
const _kGradStart     = Color(0xFF2B41BD);
const _kGradEnd       = Color(0xFF4F63FF);
const _kBg            = Color(0xFFF4F5F9);
const _kPendingOrange = Color(0xFFFF6B35);

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _userProfile;
  bool _isLoading = true;
  bool _hasError  = false;
  String _errorMessage = '';

  // Permissions
  int  _permGranted = 0;
  int  _permTotal   = 0;
  bool _permLoaded  = false;

  // Pending counts — wire these up from your real APIs
  int _downloadPending      = 0;
  int _editPending          = 0;
  int _passwordResetPending = 0;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _loadPermissionStatus();
    _loadPendingCounts();
  }

  // ── Loaders ───────────────────────────────────────────────────────────────
  Future<void> _loadUserProfile() async {
    if (!mounted) return;
    setState(() { _isLoading = true; _hasError = false; _errorMessage = ''; });
    try {
      final response = await ProfileService.getUserProfile();
      if (!mounted) return;
      if (response['success'] == true && response['data'] != null) {
        setState(() {
          _userProfile = UserProfile.fromJson(response['data'] as Map<String, dynamic>);
          _isLoading = false;
        });
      } else {
        if (response['statusCode'] == 401) {
          await ApiService.clearTokens();
          if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
          return;
        }
        setState(() { _hasError = true; _errorMessage = response['message'] ?? 'Failed to load profile'; _isLoading = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _hasError = true; _errorMessage = 'Error: $e'; _isLoading = false; });
    }
  }

  Future<void> _loadPermissionStatus() async {
    final summary = await PermissionService.permissionSummary();
    if (mounted) setState(() { _permGranted = summary.granted; _permTotal = summary.total; _permLoaded = true; });
  }

  Future<void> _loadPendingCounts() async {
    // TODO: replace with real API calls e.g. ApiService.getPendingDownloads()
    // For now uses placeholder counts
    if (mounted) setState(() { _downloadPending = 3; _editPending = 1; _passwordResetPending = 2; });
  }

  int get _totalPending => _downloadPending + _editPending + _passwordResetPending;

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  String _formatDate(String? s) {
    if (s == null) return 'Not available';
    try {
      final d = DateTime.parse(s);
      return '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
    } catch (_) { return s; }
  }

  // ── Navigation ────────────────────────────────────────────────────────────
  void _go(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  // ── Dialogs ───────────────────────────────────────────────────────────────
  void _showChangePasswordDialog() {
    showDialog(
      context: context,
      builder: (_) => ChangePasswordDialog(
        employeeId: _userProfile?.employeeId ?? '',
        isFirstTime: false,
        defaultPassword: '',
        onChangePassword: (current, newPw, confirm) async {
          try {
            final response = await ApiService.changePassword(_userProfile?.employeeId ?? '', current, newPw, confirm);
            if (!mounted) return newPw;
            if (response['success'] == true) return newPw;
            throw Exception(response['message'] ?? 'Failed to change password');
          } catch (e) {
            if (kDebugMode) print('Password change error: $e');
            rethrow;
          }
        },
      ),
    );
  }

  Future<void> _showLogoutDialog() async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Sign Out',
      message: 'Are you sure you want to sign out? You will need to log in again to access your documents.',
      confirmLabel: 'Sign Out',
      cancelLabel: 'Stay',
      variant: ConfirmVariant.danger,
      icon: Icons.logout_rounded,
    );
    if (confirmed == true && mounted) {
      try { await ApiService.clearTokens(); } catch (_) {}
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    }
  }

  Future<void> _handlePermissionsTap() async {
    final needed = await PermissionService.anyNotGranted();
    if (!mounted) return;
    if (needed) { await showPermissionsModal(context); }
    else        { await PermissionService.openSettings(); }
    if (mounted) await _loadPermissionStatus();
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: _kBg,
        body: Center(child: CircularProgressIndicator(color: _kPrimary)),
      );
    }
    if (_hasError) {
      return Scaffold(
        backgroundColor: _kBg,
        body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline_rounded, size: 56, color: Colors.red.shade300),
          const SizedBox(height: 16),
          Text(_errorMessage, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: _loadUserProfile,
            style: ElevatedButton.styleFrom(backgroundColor: _kPrimary),
            child: const Text('Retry', style: TextStyle(color: Colors.white))),
        ])),
      );
    }

    final p = _userProfile!;
    return Scaffold(
      backgroundColor: _kBg,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── 1. Profile card ─────────────────────────────────────
                _buildProfileCard(p),

                const SizedBox(height: 24),

                // ── 2. Pending Requests ─────────────────────────────────
                _sectionHeader('PENDING REQUESTS',
                  // trailing: _totalPending > 0
                  //   ? Text('$_totalPending pending',
                  //       style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _kPendingOrange))
                  //   : null,
                ),
                const SizedBox(height: 10),
                _buildCard([
                  _pendingTile(
                    icon: Icons.download_outlined,
                    iconBg: const Color(0xFFEEF0FF),
                    iconColor: _kPrimary,
                    title: 'Download Requests',
                    subtitle: 'Approve document downloads',
                    // badge: _downloadPending,
                    onTap: () => _go(const DownloadRequestsScreen()),
                  ),
                  _divider(),
                  _pendingTile(
                    icon: Icons.edit_outlined,
                    iconBg: const Color(0xFFEEF0FF),
                    iconColor: _kPrimary,
                    title: 'Edit Requests',
                    subtitle: 'Approve or reject edit access',
                    // badge: _editPending,
                    onTap: () => _go(const EditRequestsScreen()),
                  ),
                  _divider(),
                  _pendingTile(
                    icon: Icons.lock_reset_outlined,
                    iconBg: const Color(0xFFEEF0FF),
                    iconColor: _kPrimary,
                    title: 'Password Reset Requests',
                    subtitle: 'Approve or reject reset requests',
                    // badge: _passwordResetPending,
                    onTap: () => _go(const AdminPasswordResetRequestsScreen()),
                  ),
                ]),

                const SizedBox(height: 24),

                // ── 3. My Library ───────────────────────────────────────
                _sectionHeader('MY LIBRARY'),
                const SizedBox(height: 10),
                _buildCard([
                  _menuTile(
                    icon: Icons.favorite_rounded,
                    iconBg: const Color(0xFFFFEEF0),
                    iconColor: Colors.pink,
                    title: 'Favourites',
                    subtitle: 'Quick access to saved items',
                    onTap: () => _go(const FavoritesScreen()),
                  ),
                  _divider(),
                  _menuTile(
                    icon: Icons.delete_outline_rounded,
                    iconBg: const Color(0xFFFFEEEE),
                    iconColor: Colors.red,
                    title: 'Recycle Bin',
                    subtitle: 'Restore or delete items',
                    onTap: () => _go(const RecycleBinScreen()),
                  ),
                ]),

                const SizedBox(height: 24),

                // ── 4. Account & Security ───────────────────────────────
                _sectionHeader('ACCOUNT & SECURITY'),
                const SizedBox(height: 10),
                _buildCard([
                  _menuTile(
                    icon: Icons.person_outline_rounded,
                    iconBg: const Color(0xFFEEF0FF),
                    iconColor: _kPrimary,
                    title: 'Profile Details',
                    subtitle: 'Name, department, employee ID',
                    onTap: () => _go(const ProfileDetailsScreen()),
                  ),
                  _divider(),
                  _menuTile(
                    icon: Icons.lock_outline_rounded,
                    iconBg: const Color(0xFFEEF0FF),
                    iconColor: _kPrimary,
                    title: 'Change Password',
                    subtitle: 'Update your account password',
                    onTap: _showChangePasswordDialog,
                  ),
                  _divider(),
                  // App Permissions tile (dynamic subtitle)
                  _permissionsTile(),
                ]),

                const SizedBox(height: 28),

                // ── 5. Sign Out ─────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _showLogoutDialog,
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text('Sign Out', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Color(0xFFFFCDD2), width: 1.5),
                      backgroundColor: const Color(0xFFFFF5F5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Profile card ──────────────────────────────────────────────────────────
  Widget _buildProfileCard(UserProfile p) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_kGradStart, _kGradEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: _kPrimary.withOpacity(0.25), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Avatar circle
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withAlpha(35),
                  border: Border.all(color: Colors.white.withAlpha(100), width: 2.5),
                ),
                child: Center(
                  child: Text(_initials(p.employeeName),
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ),
              const SizedBox(width: 14),
              // Name + email + role badge
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.employeeName,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text(p.email,
                    style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.8)),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(35),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withAlpha(60)),
                    ),
                    child: Text(
                      p.isAdmin ? 'Administrator' : (p.isActive ? 'Active User' : 'Inactive'),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ),
                ]),
              ),
            ],
          ),

          const SizedBox(height: 16),
          Divider(color: Colors.white.withOpacity(0.25), height: 1),
          const SizedBox(height: 16),

          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statItem('Employee ID', p.employeeId.isNotEmpty ? p.employeeId : '—'),
              _verticalDivider(),
              _statItem('Department', p.department.isNotEmpty ? p.department : '—'),
              _verticalDivider(),
              _statItem('Since', _formatDate(p.createdAt).split('/').last), // show year only
            ],
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value) => Column(children: [
    Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
        maxLines: 1, overflow: TextOverflow.ellipsis),
    const SizedBox(height: 2),
    Text(label, style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.7))),
  ]);

  Widget _verticalDivider() => Container(
    height: 32, width: 1, color: Colors.white.withOpacity(0.25));

  // ── Section header ────────────────────────────────────────────────────────
  Widget _sectionHeader(String title, {Widget? trailing}) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(title, style: TextStyle(
        fontSize: 12, fontWeight: FontWeight.w700,
        color: Colors.grey.shade500, letterSpacing: 1.1)),
      if (trailing != null) trailing,
    ],
  );

  // ── White card wrapper ────────────────────────────────────────────────────
  Widget _buildCard(List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 4))],
    ),
    child: Column(children: children),
  );

  // ── Pending tile (with badge) ─────────────────────────────────────────────
  Widget _pendingTile({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    // required int badge,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0D0D2B))),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ])),
            const SizedBox(width: 8),
            // Badge
            // if (badge > 0)
            //   Container(
            //     width: 24, height: 24,
            //     decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
            //     child: Center(child: Text('$badge',
            //       style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white))),
            //   ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400, size: 20),
          ]),
        ),
      ),
    );
  }

  // ── Regular menu tile ─────────────────────────────────────────────────────
  Widget _menuTile({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? subtitleWidget,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0D0D2B))),
              const SizedBox(height: 2),
              subtitleWidget ?? Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ])),
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400, size: 20),
          ]),
        ),
      ),
    );
  }

  // ── Permissions tile ──────────────────────────────────────────────────────
  Widget _permissionsTile() {
    final allGranted = _permLoaded && _permGranted >= _permTotal;
    final permColor  = allGranted ? const Color(0xFF22C55E) : const Color(0xFFF59E0B);
    final permBg     = allGranted ? const Color(0xFFEEFDF5) : const Color(0xFFFFFBEB);

    return _menuTile(
      icon: allGranted ? Icons.verified_user_rounded : Icons.security_rounded,
      iconBg: permBg,
      iconColor: permColor,
      title: 'App Permissions',
      subtitle: '',
      subtitleWidget: _permLoaded
          ? Row(children: [
              Icon(
                allGranted ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                size: 13, color: permColor),
              const SizedBox(width: 4),
              Text(
                allGranted ? 'All permissions enabled' : '$_permGranted of $_permTotal enabled',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: permColor),
              ),
            ])
          : Text('Checking…', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
      onTap: _handlePermissionsTap,
    );
  }

  Widget _divider() => Divider(height: 1, color: Colors.grey.shade100, indent: 72);
}