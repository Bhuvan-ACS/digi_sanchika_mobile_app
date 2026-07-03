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
import 'package:digi_sanchika/services/api_service.dart';
import 'package:digi_sanchika/utils/app_theme.dart';
import 'package:digi_sanchika/utils/responsive_helper.dart';
import 'package:digi_sanchika/widgets/confirm_dialog.dart';
import 'package:digi_sanchika/widgets/empty_state_widget.dart';
import 'package:digi_sanchika/widgets/permissions_modal.dart';
import 'package:digi_sanchika/widgets/responsive_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _userProfile;
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';

  // Permissions state — loaded once, refreshed after modal closes
  int _permGranted = 0;
  int _permTotal = 0;
  bool _permLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _loadPermissionStatus();
  }

  // ── Data loaders ─────────────────────────────────────────────────────────────

  Future<void> _loadUserProfile() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = '';
    });

    try {
      final response = await ProfileService.getUserProfile();
      if (!mounted) return;

      if (response['success'] == true && response['data'] != null) {
        final profileData = response['data'] as Map<String, dynamic>;
        setState(() {
          _userProfile = UserProfile.fromJson(profileData);
          _isLoading = false;
        });
      } else {
        final statusCode = response['statusCode'];
        if (statusCode == 401) {
          try {
            await ApiService.clearTokens();
          } catch (_) {}
          if (!mounted) return;
          Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
          return;
        }
        setState(() {
          _hasError = true;
          _errorMessage = response['message'] ?? 'Failed to load profile';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadPermissionStatus() async {
    final summary = await PermissionService.permissionSummary();
    if (mounted) {
      setState(() {
        _permGranted = summary.granted;
        _permTotal = summary.total;
        _permLoaded = true;
      });
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  String _formatDate(String? dateString) {
    if (dateString == null) return 'Not available';
    try {
      final d = DateTime.parse(dateString);
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {
      return dateString;
    }
  }

  /// Returns user initials (up to 2 chars) for the avatar.
  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  // ── Navigation ────────────────────────────────────────────────────────────────

  void _navigateToDownloadRequests() => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => const DownloadRequestsScreen()),
      );

  void _navigateToEditRequests() => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const EditRequestsScreen()),
      );

  void _navigateToPasswordResetRequests() => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const AdminPasswordResetRequestsScreen(),
        ),
      );

  void _navigateToFavorites() => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const FavoritesScreen()),
      );

  void _navigateToRecycleBin() => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RecycleBinScreen()),
      );

  // ── Dialogs ───────────────────────────────────────────────────────────────────

  void _showChangePasswordDialog() {
    showDialog(
      context: context,
      builder: (_) => ChangePasswordDialog(
        employeeId: _userProfile?.employeeId ?? '',
        isFirstTime: false,
        defaultPassword: '',
        onChangePassword: (current, newPw, confirm) async {
          try {
            if (kDebugMode) print('Calling change password API...');
            final response = await ApiService.changePassword(
              _userProfile?.employeeId ?? '',
              current,
              newPw,
              confirm,
            );
            if (!mounted) return newPw;
            if (response['success'] == true) {
              return newPw;
            } else {
              throw Exception(
                  response['message'] ?? 'Failed to change password');
            }
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
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  Future<void> _handlePermissionsTap() async {
    final ctx = context;
    final needed = await PermissionService.anyNotGranted();
    if (!mounted) return;
    if (needed) {
      await showPermissionsModal(ctx);
    } else {
      await PermissionService.openSettings();
    }
    if (mounted) await _loadPermissionStatus();
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = _userProfile!;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Profile Header
              _buildAvatarCard(p),
          
              const SizedBox(height: 32),

              Text(
                'ACCOUNT ACTIONS',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade500,
                  letterSpacing: 1.2,
                ),
              ),

              const SizedBox(height: 14),

              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildActionTile(
                      icon: Icons.lock_outline,
                      iconColor: Colors.indigo,
                      title: 'Change Password',
                      subtitle: 'Update your account password',
                      onTap: _showChangePasswordDialog,
                    ),
                    Divider(height: 1, color: Colors.grey.shade200),
                    _buildActionTile(
                      icon: Icons.download_outlined,
                      iconColor: Colors.orange,
                      title: 'Download Requests',
                      subtitle: 'Manage document download requests',
                      onTap:_navigateToDownloadRequests,
                    ),
                    Divider(height: 1, color: Colors.grey.shade200),
                    _buildActionTile(
                      icon: Icons.edit_outlined,
                      iconColor: Colors.indigo,
                      title: 'Edit Requests',
                      subtitle: 'Approve or reject edit access',
                      onTap: _navigateToEditRequests,
                    ),
                    Divider(height: 1, color: Colors.grey.shade200),
                    _buildActionTile(
                      icon: Icons.favorite,
                      iconColor: Colors.pink,
                      title: 'Favourites',
                      subtitle: 'Quick access to saved items',
                      onTap: _navigateToFavorites,
                    ),
                    Divider(height: 1, color: Colors.grey.shade200),
                    _buildActionTile(
                      icon: Icons.delete_outline,
                      iconColor: Colors.red,
                      title: 'Recycle Bin',
                      subtitle: 'Restore or permanently delete items',
                      onTap: _navigateToRecycleBin,
                    ),
                    Divider(height: 1, color: Colors.grey.shade200),
                    _buildActionTile(
                      icon: Icons.lock_reset,
                      iconColor: Colors.orange,
                      title: 'Password Reset Requests',
                      subtitle: 'Approve or reject reset requests',
                      onTap: _navigateToPasswordResetRequests,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              Text(
                'APP PERMISSIONS',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade500,
                  letterSpacing: 1.2,
                ),
              ),

              const SizedBox(height: 14),

            _buildPermissionsTile(),
              const SizedBox(height: 28),
               _sectionLabel('Profile Details'),
                  const SizedBox(height: 12),
                  Container(
                      decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        children: [
                          _buildInfoTile(
                            Icons.badge_rounded,
                            AppColors.primary,
                            'Employee ID',
                            p.employeeId,
                          ),
                    Divider(height: 1, color: Colors.grey.shade200),

                             _buildInfoTile(
                    Icons.business_rounded,
                    AppColors.success,
                    'Department',
                    p.department,
                  ),
                    Divider(height: 1, color: Colors.grey.shade200),

                  _buildInfoTile(
                    Icons.email_rounded,
                    AppColors.warning,
                    'Email Address',
                    p.email,
                  ),
                    Divider(height: 1, color: Colors.grey.shade200),

                  if (p.createdAt != null)
                    _buildInfoTile(
                      Icons.calendar_today_rounded,
                      AppColors.primaryLight,
                      'Account Created',
                      _formatDate(p.createdAt),
                    ),
                        ],
                      ),
                    ),
                  ),
               height10,
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _showLogoutDialog,
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Sign Out'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(
                      color: AppColors.errorBorder,
                      width: 1.5,
                    ),
                    backgroundColor: AppColors.errorLight,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  

 


  

  // ── Sub-widgets ────────────────────────────────────────────────────────────

 

  Widget _sectionLabel(String label) => Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.textTertiary,
          letterSpacing: 0.8,
        ),
      );

  Widget _buildActionTile(
      {required IconData icon,
      required Color iconColor,
      required String title,
      required String subtitle,
      required VoidCallback onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
   
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconColor.withAlpha(18),
                    borderRadius:
                        BorderRadius.circular(AppRadius.sm),
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
                        
                        style: w700_15Poppins()
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: w400_13Poppins(color: Colors.grey.shade600)
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textTertiary, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionsTile() {
    final allGranted = _permLoaded && _permGranted >= _permTotal;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: _permLoaded
              ? (allGranted ? AppColors.successBorder : AppColors.warningBorder)
              : AppColors.border,
        ),
        boxShadow: AppShadows.xs,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: _handlePermissionsTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: (allGranted ? AppColors.success : AppColors.warning)
                        .withAlpha(18),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(
                    allGranted
                        ? Icons.verified_user_rounded
                        : Icons.security_rounded,
                    color: allGranted ? AppColors.success : AppColors.warning,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Manage Permissions',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      _permLoaded
                          ? Row(
                              children: [
                                Icon(
                                  allGranted
                                      ? Icons.check_circle_rounded
                                      : Icons.warning_amber_rounded,
                                  size: 12,
                                  color: allGranted
                                      ? AppColors.success
                                      : AppColors.warning,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  allGranted
                                      ? 'All permissions granted'
                                      : '$_permGranted of $_permTotal granted — tap to fix',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: allGranted
                                        ? AppColors.success
                                        : AppColors.warning,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            )
                          : const Text(
                              'Checking permissions…',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textTertiary),
                            ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textTertiary, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

Widget _buildAvatarCard(UserProfile p) {
  return Container(
    width: double.infinity,padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
    decoration:  BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2B41BD), Color(0xFF4F63FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.20),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [// Initials 
                      Container(width: 82,height: 82,decoration: BoxDecoration(color: Colors.white.withAlpha(35),shape: BoxShape.circle,border: Border.all(color: Colors.white.withAlpha(100), width: 2.5),),child: Center(child: Text(_initials(p.employeeName),style: const TextStyle(fontSize: 28,fontWeight: FontWeight.w800,color: Colors.white,letterSpacing: 1,),),),),const SizedBox(height: 14),
                      width10,
                            // Name
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.employeeName,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: 2.h,),
                                 SizedBox(
                                  width: 190.w,
                                  child: Text(p.email,style: w400_14Poppins(color: Colors.white),overflow: TextOverflow.ellipsis,maxLines: 1,)),
                                height5,
                      
                            // Role / status badge
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(30),
                                borderRadius: BorderRadius.circular(AppRadius.pill),
                                border:
                                    Border.all(color: Colors.white.withAlpha(60)),
                              ),
                              child: Text(
                                p.isAdmin ? 'Administrator' : (p.isActive ? 'Active User' : 'Inactive'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                              ],
                            ),
                         
                          ],
                        ),
                        height10,
                        Divider(color: Colors.white54,),
                        height10,
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                             Column(
                               children: [
                                 Text("222",style: w700_22Poppins(color: Colors.white),),
                                 Text("Documents",style: w400_14Poppins(color: Colors.white),),
                               ],
                             ),
    width10,

    SizedBox(
      height: 40, // Height of the divider
      child: VerticalDivider(
        color: Colors.white54,
        thickness: 1,
        width: 20, // Total space occupied
      ),
    ),

    width10,
    Column(
                               children: [
                                 Text("12",style: w700_22Poppins(color: Colors.white),),
                                 Text("Shared",style: w400_14Poppins(color: Colors.white),),
                               ],
                             ),
   width10,

    SizedBox(
      height: 40, // Height of the divider
      child: VerticalDivider(
        color: Colors.white54,
        thickness: 1,
        width: 20, // Total space occupied
      ),
    ),
    width10,
      Column(
                               children: [
                                 Text("222",style: w700_22Poppins(color: Colors.white),),
                                 Text("Storage",style: w400_14Poppins(color: Colors.white),),
                               ],
                             ),


                          ],
                        )
                    ],
                  ),
                ),
);

}

  Widget _buildInfoTile(
      IconData icon, Color color, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
     
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withAlpha(18),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value.isNotEmpty ? value : '—',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
