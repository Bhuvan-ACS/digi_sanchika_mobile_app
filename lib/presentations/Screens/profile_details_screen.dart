// ignore_for_file: use_build_context_synchronously
import 'package:digi_sanchika/models/profile.dart';
import 'package:digi_sanchika/services/api_service.dart';
import 'package:digi_sanchika/services/profile_service.dart';
import 'package:digi_sanchika/utils/app_fonts.dart';
import 'package:digi_sanchika/utils/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─── Colour tokens (match the rest of the app) ────────────────────────────────
const _kPrimary  = Color(0xFF2D4EE8);
const _kGradientStart = Color(0xFF2B41BD);
const _kGradientEnd   = Color(0xFF4F63FF);
const _kBg       = Color(0xFFF6F7FB);

// ─── Screen ───────────────────────────────────────────────────────────────────
class ProfileDetailsScreen extends StatefulWidget {
  const ProfileDetailsScreen({super.key});

  @override
  State<ProfileDetailsScreen> createState() => _ProfileDetailsScreenState();
}

class _ProfileDetailsScreenState extends State<ProfileDetailsScreen> {
  UserProfile? _profile;
  bool _isLoading = true;
  bool _hasError  = false;
  String _errorMsg = '';

  // Controllers for editable fields
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl  = TextEditingController();
    _phoneCtrl = TextEditingController();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  // ── Load ──────────────────────────────────────────────────────────────────
  Future<void> _loadProfile() async {
    setState(() { _isLoading = true; _hasError = false; });
    try {
      final res = await ProfileService.getUserProfile();
      if (!mounted) return;

      if (res['success'] == true && res['data'] != null) {
        final p = UserProfile.fromJson(res['data'] as Map<String, dynamic>);
        setState(() {
          _profile  = p;
          _isLoading = false;
          // Pre-fill editable fields
          _nameCtrl.text  = p.employeeName;
          // _phoneCtrl.text = p.phone ?? '';
        });
      } else {
        if (res['statusCode'] == 401) {
          await ApiService.clearTokens();
          if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
          return;
        }
        setState(() {
          _hasError = true;
          _errorMsg = res['message'] ?? 'Failed to load profile';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _hasError = true; _errorMsg = 'Error: $e'; _isLoading = false; });
    }
  }

  // ── Save (editable fields only) ───────────────────────────────────────────
  Future<void> _saveChanges() async {
    // Wire up your update API here.
    // e.g. await ProfileService.updateProfile(name: _nameCtrl.text, phone: _phoneCtrl.text);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Profile updated successfully'),
        backgroundColor: Color(0xFF2D4EE8),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Initials ──────────────────────────────────────────────────────────────
  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  // ── Date format ───────────────────────────────────────────────────────────
  String _formatDate(String? s) {
    if (s == null) return '—';
    try {
      final d = DateTime.parse(s);
      return '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
    } catch (_) { return s; }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: _isLoading
          ? _buildLoader()
          : _hasError
              ? _buildError()
              : _buildContent(),
    );
  }

  // ── Loading ───────────────────────────────────────────────────────────────
  Widget _buildLoader() => const Scaffold(
        backgroundColor: _kBg,
        body: Center(child: CircularProgressIndicator(color: _kPrimary)),
      );

  // ── Error ─────────────────────────────────────────────────────────────────
  Widget _buildError() => Scaffold(
        backgroundColor: _kBg,
        appBar: _appBar(),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline_rounded, size: 56, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(_errorMsg, textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loadProfile,
              style: ElevatedButton.styleFrom(backgroundColor: _kPrimary),
              child: const Text('Retry', style: TextStyle(color: Colors.white)),
            ),
          ]),
        ),
      );

  // ── Main content ──────────────────────────────────────────────────────────
  Widget _buildContent() {
    final p = _profile!;
    return Scaffold(
      backgroundColor: _kBg,
      appBar: _appBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        child: Column(
          children: [
            // ── Avatar section ───────────────────────────────────────────
            _buildAvatarSection(p),

            const SizedBox(height: 28),

            // ── Fields card ──────────────────────────────────────────────
            _buildFieldsCard(p),

            const SizedBox(height: 28),

            // ── Save Changes button ──────────────────────────────────────
            // SizedBox(
            //   width: double.infinity,
            //   height: 54,
            //   child: ElevatedButton(
            //     onPressed: _saveChanges,
            //     style: ElevatedButton.styleFrom(
            //       backgroundColor: _kPrimary,
            //       foregroundColor: Colors.white,
            //       elevation: 0,
            //       shape: RoundedRectangleBorder(
            //         borderRadius: BorderRadius.circular(16),
            //       ),
            //     ),
            //     child: const Text(
            //       'Save Changes',
            //       style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            //     ),
            //   ),
            // ),
          ],
        ),
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────
  PreferredSizeWidget _appBar() => AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Color(0xFF0D0D2B)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Profile Details',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0D0D2B),
              ),
            ),
            Text(
              'Your account information',
              style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      );

  // ── Avatar section ────────────────────────────────────────────────────────
  Widget _buildAvatarSection(UserProfile p) {
    return Column(
      children: [
        // Circle avatar with gradient ring
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [_kGradientStart, _kGradientEnd],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: _kPrimary.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: Text(
              _initials(p.employeeName),
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 1,
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // // Change Photo button
        // OutlinedButton(
        //   onPressed: () {
        //     // TODO: wire up image picker
        //   },
        //   style: OutlinedButton.styleFrom(
        //     foregroundColor: _kPrimary,
        //     side: const BorderSide(color: _kPrimary, width: 1.2),
        //     padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        //     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        //     minimumSize: Size.zero,
        //     tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        //   ),
        //   child: const Text(
        //     'Change Photo',
        //     style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        //   ),
        // ),
      ],
    );
  }

  // ── Fields card ───────────────────────────────────────────────────────────
  Widget _buildFieldsCard(UserProfile p) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // Editable — Full Name
          _buildEditableField(
            label: 'Full Name',
            controller: _nameCtrl,
            icon: Icons.person_outline_rounded,
          ),
          _divider(),

          // Read-only — Email
          _buildReadOnlyField(
            label: 'Email',
            value: p.email,
            icon: Icons.email_outlined,
          ),
          _divider(),

          // Read-only — Role
          _buildReadOnlyField(
            label: 'Role',
            value: p.isAdmin ? 'Administrator' : (p.isActive ? 'Active User' : 'Inactive'),
            icon: Icons.shield_outlined,
          ),
          _divider(),

          // Read-only — Department
          _buildReadOnlyField(
            label: 'Department',
            value: p.department.isNotEmpty ? p.department : '—',
            icon: Icons.business_outlined,
          ),
          _divider(),

          // Read-only — Employee ID
          _buildReadOnlyField(
            label: 'Employee ID',
            value: p.employeeId.isNotEmpty ? p.employeeId : '—',
            icon: Icons.badge_outlined,
          ),
          _divider(),

          // Editable — Phone
          _buildEditableField(
            label: 'Phone',
            controller: _phoneCtrl,
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            hint: 'Not provided',
          ),

          // Read-only — Account Created (optional)
          if (p.createdAt != null) ...[
            _divider(),
            _buildReadOnlyField(
              label: 'Account Created',
              value: _formatDate(p.createdAt),
              icon: Icons.calendar_today_outlined,
            ),
          ],
        ],
      ),
    );
  }

  // ── Read-only field tile ──────────────────────────────────────────────────
  Widget _buildReadOnlyField({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: _kPrimary.withOpacity(0.07),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _kPrimary, size: 18),
          ),
          const SizedBox(width: 14),
          // Label + value
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade500,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value.isNotEmpty ? value : '—',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0D0D2B),
                  ),
                ),
              ],
            ),
          ),
          // Lock icon — signals non-editable
          Icon(Icons.lock_outline_rounded, size: 16, color: Colors.grey.shade300),
        ],
      ),
    );
  }

  // ── Editable field tile ───────────────────────────────────────────────────
  Widget _buildEditableField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Icon
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: _kPrimary.withOpacity(0.07),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _kPrimary, size: 18),
          ),
          const SizedBox(width: 14),
          // Label + text field
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade500,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                TextField(
                  controller: controller,
                  keyboardType: keyboardType,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0D0D2B),
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintText: hint ?? 'Enter $label',
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14, fontWeight: FontWeight.w400),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: _kPrimary.withOpacity(0.5), width: 1.5),
                    ),
                  ),
                  cursorColor: _kPrimary,
                ),
              ],
            ),
          ),
          // Edit icon
          Icon(Icons.edit_outlined, size: 16, color: Colors.grey.shade400),
        ],
      ),
    );
  }

  Widget _divider() => Divider(height: 1, color: Colors.grey.shade100, indent: 70);
}