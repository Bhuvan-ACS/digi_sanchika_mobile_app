// ignore_for_file: use_build_context_synchronously
import 'package:digi_sanchika/utils/app_fonts.dart';
import 'package:flutter/material.dart';
import 'package:digi_sanchika/services/permission_service.dart';
import 'package:digi_sanchika/services/profile_store.dart';
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
import 'package:digi_sanchika/theme/ui_theme.dart';
import 'package:digi_sanchika/widgets/confirm_dialog.dart';
import 'package:digi_sanchika/widgets/permissions_modal.dart';
import 'package:digi_sanchika/widgets/profile_avatar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

// ─── Colour tokens ────────────────────────────────────────────────────────────
const _kPrimary = Color(0xFF3B82E8);
// Profile card fill: the same flat blue as the bottom-nav upload button.
const _kCardBlue = UiColors.primary;
const _kBg = Color(0xFFF4F5F9);
const _kPendingOrange = Color(0xFFFF6B35);

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _store = ProfileStore.instance;
  UserProfile? get _userProfile => _store.profile;
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';

  // Permissions
  int _permGranted = 0;
  int _permTotal = 0;
  bool _permLoaded = false;

  // Pending counts — wire these up from your real APIs
  int _downloadPending = 0;
  int _editPending = 0;
  int _passwordResetPending = 0;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onProfileChanged);
    _loadUserProfile();
    _loadPermissionStatus();
    _loadPendingCounts();
  }

  @override
  void dispose() {
    _store.removeListener(_onProfileChanged);
    super.dispose();
  }

  void _onProfileChanged() {
    if (mounted) setState(() {});
  }

  // ── Loaders ───────────────────────────────────────────────────────────────
  Future<void> _loadUserProfile() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = '';
    });
    try {
      final response = await _store.load();
      if (!mounted) return;
      if (response['success'] == true && _store.profile != null) {
        setState(() => _isLoading = false);
      } else {
        if (response['statusCode'] == 401) {
          await ApiService.clearTokens();
          if (mounted)
            Navigator.of(
              context,
            ).pushNamedAndRemoveUntil('/login', (_) => false);
          return;
        }
        setState(() {
          _hasError = true;
          _errorMessage = response['message'] ?? 'Failed to load profile';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _hasError = true;
          _errorMessage = 'Error: $e';
          _isLoading = false;
        });
    }
  }

  Future<void> _loadPermissionStatus() async {
    final summary = await PermissionService.permissionSummary();
    if (mounted)
      setState(() {
        _permGranted = summary.granted;
        _permTotal = summary.total;
        _permLoaded = true;
      });
  }

  Future<void> _loadPendingCounts() async {
    // TODO: replace with real API calls e.g. ApiService.getPendingDownloads()
    // For now uses placeholder counts
    if (mounted)
      setState(() {
        _downloadPending = 3;
        _editPending = 1;
        _passwordResetPending = 2;
      });
  }

  int get _totalPending =>
      _downloadPending + _editPending + _passwordResetPending;

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  // ── Navigation ────────────────────────────────────────────────────────────
  void _go(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  // Saving on the details screen updates [ProfileStore], which redraws this
  // screen through the listener — nothing to do with the result here.
  void _openEditProfile() => _go(const ProfileDetailsScreen());

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
            final response = await ApiService.changePassword(
              _userProfile?.employeeId ?? '',
              current,
              newPw,
              confirm,
            );
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
      message:
          'Are you sure you want to sign out? You will need to log in again to access your documents.',
      confirmLabel: 'Sign Out',
      cancelLabel: 'Stay',
      variant: ConfirmVariant.danger,
      icon: Icons.logout_rounded,
    );
    if (confirmed == true && mounted) {
      try {
        await ApiService.clearTokens();
      } catch (_) {}
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    }
  }

  Future<void> _handlePermissionsTap() async {
    final needed = await PermissionService.anyNotGranted();
    if (!mounted) return;
    if (needed) {
      await showPermissionsModal(context);
    } else {
      await PermissionService.openSettings();
    }
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
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 56,
                color: Colors.red.shade300,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _loadUserProfile,
                style: ElevatedButton.styleFrom(backgroundColor: _kPrimary),
                child: const Text(
                  'Retry',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final p = _userProfile!;
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: const Text(
          'Profile',
          style: TextStyle(
            fontFamily: appFontFamily,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
          ),
        ),
        leadingWidth: 54,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Center(
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E9F2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                splashRadius: 20,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(
                  Icons.arrow_back_ios_new,
                  size: 16,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
          ),
        ),
        actions: const [SizedBox(width: 54)],
      ),
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 1. Profile card ─────────────────────────────────────
                _buildProfileCard(p),

                const SizedBox(height: 24),

                // ── 2. Pending Requests ─────────────────────────────────
                _sectionHeader(
                  'PENDING REQUESTS',
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
                    label: const Text(
                      'Sign Out',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(
                        color: Color(0xFFFFCDD2),
                        width: 1.5,
                      ),
                      backgroundColor: const Color(0xFFFFF5F5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
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
  /// Compact card: avatar (with edit pencil), name and role, a chevron that
  /// opens the edit page, then employee ID and email on one line.
  Widget _buildProfileCard(UserProfile p) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _kCardBlue,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _kCardBlue.withOpacity(0.28),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Glassy circles on the right, clipped by the card's corners.
            Positioned(
              top: -70,
              right: -40,
              child: _glassCircle(190),
            ),
            Positioned(
              bottom: -110,
              right: -70,
              child: _glassCircle(250),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 14, 16),
              child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Avatar with the single edit action for the profile
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ProfileAvatar(
                    initials: _initials(p.employeeName),
                    avatar: _store.avatar,
                    size: 72,
                    border: Border.all(
                      color: Colors.white.withAlpha(110),
                      width: 2.5,
                    ),
                  ),
                  Positioned(
                    right: -6,
                    bottom: -6,
                    child: Tooltip(
                      message: 'Edit profile details',
                      child: Material(
                        color: Colors.white,
                        shape: const CircleBorder(
                          side: BorderSide(color: _kCardBlue, width: 2),
                        ),
                        elevation: 4,
                        shadowColor: Colors.black.withOpacity(0.3),
                        child: InkWell(
                          onTap: _openEditProfile,
                          customBorder: const CircleBorder(),
                          child: const Padding(
                            padding: EdgeInsets.all(7),
                            child: Icon(
                              Icons.edit_rounded,
                              size: 16,
                              color: _kCardBlue,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              // Name + role; the whole area opens the edit page.
              Expanded(
                child: InkWell(
                  onTap: _openEditProfile,
                  borderRadius: BorderRadius.circular(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.employeeName,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              p.roleLabel,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withOpacity(0.85),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white.withOpacity(0.9),
                        size: 28,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: Colors.white.withOpacity(0.25), height: 1),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Row(
              children: [
                _cardInfo(
                  Icons.badge_outlined,
                  p.employeeId.isNotEmpty ? p.employeeId : '—',
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _cardInfo(
                      Icons.mail_outline_rounded,
                      p.email.isNotEmpty ? p.email : '—',
                      shrink: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Soft translucent circle: a faint white wash fading toward its edge, with
  /// a hairline rim, so it reads as frosted glass on the blue.
  Widget _glassCircle(double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [
          Colors.white.withOpacity(0.05),
          Colors.white.withOpacity(0.14),
        ],
        stops: const [0.55, 1.0],
      ),
      border: Border.all(color: Colors.white.withOpacity(0.12)),
    ),
  );

  /// Icon + text pair for the profile card's bottom line.
  Widget _cardInfo(IconData icon, String text, {bool shrink = false}) {
    final label = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Colors.white,
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: Colors.white.withOpacity(0.9)),
        const SizedBox(width: 8),
        shrink ? Flexible(child: label) : label,
      ],
    );
  }

  // ── Section header ────────────────────────────────────────────────────────
  Widget _sectionHeader(String title, {Widget? trailing}) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade500,
          letterSpacing: 1.1,
        ),
      ),
      if (trailing != null) trailing,
    ],
  );

  // ── White card wrapper ────────────────────────────────────────────────────
  Widget _buildCard(List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
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
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0D0D2B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
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
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.grey.shade400,
                size: 20,
              ),
            ],
          ),
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
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0D0D2B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    subtitleWidget ??
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.grey.shade400,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Permissions tile ──────────────────────────────────────────────────────
  Widget _permissionsTile() {
    final allGranted = _permLoaded && _permGranted >= _permTotal;
    final permColor = allGranted
        ? const Color(0xFF22C55E)
        : const Color(0xFFF59E0B);
    final permBg = allGranted
        ? const Color(0xFFEEFDF5)
        : const Color(0xFFFFFBEB);

    return _menuTile(
      icon: allGranted ? Icons.verified_user_rounded : Icons.security_rounded,
      iconBg: permBg,
      iconColor: permColor,
      title: 'App Permissions',
      subtitle: '',
      subtitleWidget: _permLoaded
          ? Row(
              children: [
                Icon(
                  allGranted
                      ? Icons.check_circle_rounded
                      : Icons.warning_amber_rounded,
                  size: 13,
                  color: permColor,
                ),
                const SizedBox(width: 4),
                Text(
                  allGranted
                      ? 'All permissions enabled'
                      : '$_permGranted of $_permTotal enabled',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: permColor,
                  ),
                ),
              ],
            )
          : Text(
              'Checking…',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
      onTap: _handlePermissionsTap,
    );
  }

  Widget _divider() =>
      Divider(height: 1, color: Colors.grey.shade100, indent: 72);
}
