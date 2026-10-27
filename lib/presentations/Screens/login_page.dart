// ignore_for_file: use_build_context_synchronously, unused_element

import 'dart:async';
import 'package:digi_sanchika/presentations/Screens/change_password.dart';
import 'package:digi_sanchika/presentations/Screens/home_page.dart';
import 'package:digi_sanchika/services/api_service.dart';
import 'package:digi_sanchika/services/permission_service.dart';
import 'package:digi_sanchika/services/profile_service.dart';
import 'package:digi_sanchika/services/push_notifications_service.dart';
import 'package:digi_sanchika/widgets/permissions_modal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:digi_sanchika/utils/responsive_helper.dart';

// ─── Theme constants ──────────────────────────────────────────────────────────
const _kPrimary = Color(0xFF2D4EE8);
const _kDeepBlue = Color(0xFF2540D4);
const _kLightBlue = Color(0xFF3A5AF0);

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _employeeIdController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _employeeFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  bool _isPasswordVisible = false;
  bool _isLoading = false;
  bool _rememberMe = false;

  final String _defaultPassword = "default@123";

  static const Duration _fallbackCooldown = Duration(seconds: 30);
  static const Duration _maxCooldown = Duration(minutes: 5);

  DateTime? _loginCooldownUntil;
  Timer? _cooldownTimer;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _initializeApp();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      precacheImage(const AssetImage('assets/images/digi-sanchika-logo.png'), context);
      _maybeShowPermissionsModal();
    });
  }

  Future<void> _maybeShowPermissionsModal() async {
    if (!mounted) return;
    final needed = await PermissionService.anyNotGranted();
    if (needed && mounted) await showPermissionsModal(context);
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _employeeIdController.dispose();
    _passwordController.dispose();
    _employeeFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  // ── Cooldown helpers ───────────────────────────────────────────────────────
  bool get _isInCooldown {
    final until = _loginCooldownUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  int get _cooldownSecondsRemaining {
    final until = _loginCooldownUntil;
    if (until == null) return 0;
    final diff = until.difference(DateTime.now());
    return diff.isNegative ? 0 : diff.inSeconds;
  }

  void _startCooldown(Duration duration) {
    final clamped = _clampCooldown(duration);
    _cooldownTimer?.cancel();
    setState(() => _loginCooldownUntil = DateTime.now().add(clamped));
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (!_isInCooldown) { t.cancel(); }
      setState(() {});
    });
  }

  Duration? _cooldownFromServerResponse(Map<String, dynamic> response) {
    final s = response['retryAfterSeconds'];
    if (s is int && s > 0) return Duration(seconds: s);
    return _fallbackCooldown;
  }

  Duration _clampCooldown(Duration d) {
    if (d <= Duration.zero) return _fallbackCooldown;
    if (d > _maxCooldown) return _maxCooldown;
    return d;
  }

  // ── Init ───────────────────────────────────────────────────────────────────
  Future<void> _initializeApp() async {
    await ApiService.initialize();
    if (kDebugMode) {
      _employeeIdController.text = '';
      _passwordController.text = '';
    }
  }

  // ── Login ──────────────────────────────────────────────────────────────────
  Future<void> _attemptLogin() async {
    if (_isLoading) return;
    if (_isInCooldown) {
      final s = _cooldownSecondsRemaining;
      final m = (s ~/ 60).toString().padLeft(2, '0');
      final ss = (s % 60).toString().padLeft(2, '0');
      _showSnackBar('Too many attempts. Try again in $m:$ss.', Colors.orange, duration: 3);
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final employeeId = _employeeIdController.text.trim();
    final password = _passwordController.text.trim();

    if (password == _defaultPassword) {
      _showSnackBar('Default password detected. Please change your password.', Colors.orange);
      WidgetsBinding.instance.addPostFrameCallback((_) => _showChangePasswordDialog(isFirstTime: true));
      return;
    }

    setState(() => _isLoading = true);

    if (kDebugMode) print('Attempting login with identifier: $employeeId');
    final response = await ApiService.login(employeeId, password);
    if (kDebugMode) print('Login response: $response');

    if (response['success'] == true) {
      _showSnackBar('Login successful!', Colors.green);
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;

      final rawData = response['data'];
      Map<String, dynamic> userData = {};
      if (rawData is Map<String, dynamic>) {
        final user = rawData['user'];
        final data = rawData['data'];
        if (user is Map<String, dynamic>) userData = user;
        else if (data is Map<String, dynamic>) userData = data;
        else userData = rawData;
      }

      String _extract(List<String?> vals) => vals
          .whereType<String>().map((s) => s.trim()).firstWhere((s) => s.isNotEmpty, orElse: () => '');

      var effectiveName = _extract([
        userData['name']?.toString(), userData['full_name']?.toString(),
        userData['fullName']?.toString(), userData['username']?.toString(),
      ]);
      var effectiveEmail = _extract([
        userData['email']?.toString(), userData['user_email']?.toString(), userData['mail']?.toString(),
      ]);

      if (effectiveName.isEmpty || effectiveName.toLowerCase() == 'user') {
        try {
          final prof = await ProfileService.getUserProfile();
          if (prof['success'] == true && prof['data'] != null) {
            final data = prof['data'];
            Map<String, dynamic> u = {};
            if (data is Map<String, dynamic>) {
              final inner = data['user'];
              u = inner is Map<String, dynamic> ? inner : data;
            }
            final pn = _extract([u['name']?.toString(), u['full_name']?.toString(),
              u['fullName']?.toString(), u['username']?.toString()]);
            final pe = _extract([u['email']?.toString(), u['user_email']?.toString(), u['mail']?.toString()]);
            if (pn.isNotEmpty) effectiveName = pn;
            if (pe.isNotEmpty) effectiveEmail = pe;
          }
        } catch (_) {}
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_name', effectiveName);
      await prefs.setString('user_email', effectiveEmail.isNotEmpty ? effectiveEmail : employeeId);
      if (_rememberMe) await prefs.setBool('remember_me', true);

      try { await PushNotificationsService.instance.initAfterLogin(); } catch (_) {}

      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => HomePage(
          userName: effectiveName.isNotEmpty ? effectiveName : 'User',
          userEmail: effectiveEmail.isNotEmpty ? effectiveEmail : employeeId,
        ),
      ));
    } else {
      final message = response['message']?.toString().toLowerCase() ?? '';
      final statusCode = response['statusCode'] ?? 0;

      if (statusCode == 429) {
        _startCooldown(_cooldownFromServerResponse(response) ?? _fallbackCooldown);
        _showSnackBar(response['message'] ?? 'Too many attempts. Please wait and try again.', Colors.orange, duration: 4);
      } else if (message.contains('change password') || message.contains('password expired') ||
          message.contains('first login') || message.contains('default password') ||
          message.contains('invalid password') ||
          (statusCode == 401 && (message.contains('password') || message.contains('auth'))) ||
          (statusCode == 403 && message.contains('password'))) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showChangePasswordDialog(
            isFirstTime: message.contains('first login') || message.contains('default password'),
          );
        });
      } else {
        _showSnackBar(response['message'] ?? 'Login failed', Colors.red);
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  // ── Dialogs ────────────────────────────────────────────────────────────────
  void _showChangePasswordDialog({bool isFirstTime = false}) {
    showDialog(
      context: context,
      barrierDismissible: !isFirstTime,
      builder: (_) => ChangePasswordDialog(
        employeeId: _employeeIdController.text.trim(),
        isFirstTime: isFirstTime,
        defaultPassword: _defaultPassword,
        onChangePassword: (currentPassword, newPassword, confirmPassword) async {
          setState(() => _isLoading = true);
          await ApiService.clearTokens();
          try {
            final response = await ApiService.changePassword(
              _employeeIdController.text.trim(), currentPassword, newPassword, confirmPassword);
            if (mounted) {
              setState(() => _isLoading = false);
              if (response['success'] == true) return newPassword;
              throw Exception(response['message'] ?? 'Password change failed');
            }
          } catch (e) {
            if (mounted) setState(() => _isLoading = false);
            rethrow;
          }
          return null;
        },
      ),
    ).then((newPassword) {
      if (newPassword != null && newPassword is String) {
        _passwordController.text = newPassword;
        _showSnackBar('Password changed successfully! You can now login with your new password.', Colors.green, duration: 3);
        FocusScope.of(context).requestFocus(FocusNode());
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted && _employeeIdController.text.isNotEmpty && _passwordController.text.isNotEmpty) {
            _attemptLogin();
          }
        });
      }
    });
  }

  void _showForgotPasswordDialog() {
    final emailCtrl = TextEditingController(text: _employeeIdController.text.trim());
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.help_outline, color: _kPrimary),
          SizedBox(width: 10),
          Text('Forgot Password'),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Enter your email and tap "Notify Admin". If an account exists, administrators will be notified.'),
          const SizedBox(height: 12),
          TextField(
            controller: emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email', hintText: 'user@example.com'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final email = emailCtrl.text.trim();
              if (email.isEmpty || !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
                _showSnackBar('Please enter a valid email address', Colors.red);
                return;
              }
              final res = await ApiService.passwordResetRequest(email);
              if (!mounted) return;
              _showSnackBar((res['message'] ?? 'If an account exists, administrators have been notified.').toString(), Colors.green, duration: 3);
              Navigator.of(context).pop();
            },
            child: const Text('Notify Admin'),
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    );
  }

  void _showSnackBar(String message, Color color, {int duration = 2}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: duration),
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final r = ResponsiveHelper.of(context);

    return Scaffold(
      backgroundColor: _kDeepBlue,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Column(
          children: [
            // ── Blue hero section ──────────────────────────────────────────
            _buildHero(r),

            // ── White form card ────────────────────────────────────────────
            Expanded(
              child: Container(
                   decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
                    ),
                child: SingleChildScrollView(
                  child: _buildFormCard(r),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Blue top section ───────────────────────────────────────────────────────
  Widget _buildHero(ResponsiveHelper r) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_kPrimary, _kLightBlue, _kDeepBlue],
        ),
      ),
      child: Stack(
        children: [
          // Decorative circles
          const Positioned(top: -20, right: -50, child: _Circle(size: 200)),
          const Positioned(top: 40, right: 60, child: _Circle(size: 100)),

          // Content
          SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(r.p(28), r.p(24), r.p(28), r.p(36)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // App icon
                  GestureDetector(
                    onLongPress: () => Navigator.of(context).pushNamed('/push-debug'),
                    child: Container(
                      width: r.p(52),
                      height: r.p(52),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(r.p(14)),
                        border: Border.all(color: Colors.white.withOpacity(0.25), width: 1),
                      ),
                      child: Center(
                        child: Image.asset(
                          'assets/images/digi-sanchika-logo.png',
                          width: r.p(30),
                          height: r.p(30),
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.article_outlined,
                            color: Colors.white,
                            size: r.p(26),
                          ),
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: r.p(20)),

                  Text(
                    'Welcome back',
                    style: TextStyle(
                      fontSize: r.sp(28),
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),

                  SizedBox(height: r.p(6)),

                  Text(
                    'Sign in to access your documents,\nrequests and shared workspace.',
                    style: TextStyle(
                      fontSize: r.sp(14),
                      color: Colors.white.withOpacity(0.8),
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── White form card ────────────────────────────────────────────────────────
  Widget _buildFormCard(ResponsiveHelper r) {
    return Container(
      // width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(10), topRight: Radius.circular(10)),
      ),
      padding: EdgeInsets.fromLTRB(r.p(24), r.p(28), r.p(24), r.p(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: r.isMobile ? double.infinity : 520),
        child: AutofillGroup(
          child: Form(
            key: _formKey,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  
                  // ── Work Email field ───────────────────────────────────────
                  _fieldLabel(r, 'Work Email'),
                  SizedBox(height: r.p(6)),
                  _buildTextField(
                    r: r,
                    controller: _employeeIdController,
                    focusNode: _employeeFocus,
                    hintText: 'Enter email or employee ID',
                    prefixIcon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username, AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Please enter your identifier';
                      if (value.contains('@') && !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
                        return 'Please enter a valid email address';
                      }
                      return null;
                    },
                  ),
              
                  SizedBox(height: r.p(20)),
              
                  // ── Password field ─────────────────────────────────────────
                  _fieldLabel(r, 'Password'),
                  SizedBox(height: r.p(6)),
                  _buildTextField(
                    r: r,
                    controller: _passwordController,
                    focusNode: _passwordFocus,
                    hintText: 'Enter your password',
                    prefixIcon: Icons.lock_outline,
                    obscureText: !_isPasswordVisible,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _attemptLogin(),
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Please enter your password';
                      return null;
                    },
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isPasswordVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        color: Colors.grey.shade400,
                        size: r.sp(20),
                      ),
                      onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                    ),
                  ),
              
                  SizedBox(height: r.p(14)),
              
                  // ── Remember me + Forgot password ──────────────────────────
                  Row(
                    children: [
                      SizedBox(
                        width: r.p(20),
                        height: r.p(20),
                        child: Checkbox(
                          value: _rememberMe,
                          onChanged: (v) => setState(() => _rememberMe = v ?? false),
                          activeColor: _kPrimary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      SizedBox(width: r.p(8)),
                      Text('Remember me', style: TextStyle(fontSize: r.sp(13), color: const Color(0xFF444466))),
                      const Spacer(),
                      GestureDetector(
                        onTap: _isLoading ? null : _showForgotPasswordDialog,
                        child: Text(
                          'Forgot password?',
                          style: TextStyle(
                            fontSize: r.sp(13),
                            color: _kPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
              
                  SizedBox(height: r.p(28)),
              
                  // ── Sign In button ─────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: r.p(54),
                    child: ElevatedButton(
                      onPressed: (_isLoading || _isInCooldown) ? null : _attemptLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPrimary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _kPrimary.withOpacity(0.5),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r.p(14))),
                      ),
                      child: _isLoading
                          ? SizedBox(
                              width: r.sp(22),
                              height: r.sp(22),
                              child: const CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _isInCooldown
                                      ? () {
                                          final s = _cooldownSecondsRemaining;
                                          return 'Try again in ${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
                                        }()
                                      : 'Sign In',
                                  style: TextStyle(fontSize: r.sp(16), fontWeight: FontWeight.w700),
                                ),
                                if (!_isInCooldown) ...[
                                  SizedBox(width: r.p(8)),
                                  Icon(Icons.arrow_forward, size: r.sp(18)),
                                ],
                              ],
                            ),
                    ),
                  ),
              
                  SizedBox(height: r.p(24)),
              
                  // // ── Divider ────────────────────────────────────────────────
                  // Row(children: [
                  //   Expanded(child: Divider(color: Colors.grey.shade200, thickness: 1)),
                  //   Padding(
                  //     padding: EdgeInsets.symmetric(horizontal: r.p(12)),
                  //     child: Text('or continue with', style: TextStyle(fontSize: r.sp(12), color: Colors.grey.shade400)),
                  //   ),
                  //   Expanded(child: Divider(color: Colors.grey.shade200, thickness: 1)),
                  // ]),
              
                  // SizedBox(height: r.p(16)),
              
                  // // ── SSO button ─────────────────────────────────────────────
                  // SizedBox(
                  //   width: double.infinity,
                  //   height: r.p(52),
                  //   child: OutlinedButton(
                  //     onPressed: _isLoading ? null : () {
                  //       // SSO handler — wire up your SSO logic here
                  //     },
                  //     style: OutlinedButton.styleFrom(
                  //       foregroundColor: const Color(0xFF222244),
                  //       side: BorderSide(color: Colors.grey.shade200, width: 1.5),
                  //       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r.p(14))),
                  //     ),
                  //     child: Row(
                  //       mainAxisAlignment: MainAxisAlignment.center,
                  //       children: [
                  //         Icon(Icons.shield_outlined, size: r.sp(18), color: _kPrimary),
                  //         SizedBox(width: r.p(8)),
                  //         Text(
                  //           'Single Sign-On (SSO)',
                  //           style: TextStyle(fontSize: r.sp(15), fontWeight: FontWeight.w600),
                  //         ),
                  //       ],
                  //     ),
                  //   ),
                  // ),
              
                  // SizedBox(height: r.p(10)),
              
                  // ── Security footer ────────────────────────────────────────
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline, size: r.sp(12), color: Colors.grey.shade400),
                        SizedBox(width: r.p(4)),
                        Text(
                          'Secured with enterprise-grade encryption',
                          style: TextStyle(fontSize: r.sp(11), color: Colors.grey.shade400),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 166.h),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  Widget _fieldLabel(ResponsiveHelper r, String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: r.sp(13),
        fontWeight: FontWeight.w600,
        color: const Color(0xFF333355),
      ),
    );
  }

  Widget _buildTextField({
    required ResponsiveHelper r,
    required TextEditingController controller,
    FocusNode? focusNode,
    required String hintText,
    required IconData prefixIcon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    Iterable<String>? autofillHints,
    TextInputAction? textInputAction,
    void Function(String)? onFieldSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      autofillHints: autofillHints,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      style: TextStyle(fontSize: r.sp(15), color: const Color(0xFF111133)),
      cursorColor: _kPrimary,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: r.sp(14)),
        prefixIcon: Icon(prefixIcon, color: Colors.grey.shade400, size: r.sp(20)),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFFF8F9FD),
        contentPadding: EdgeInsets.symmetric(vertical: r.p(16), horizontal: r.p(16)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(r.p(12)),
          borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(r.p(12)),
          borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(r.p(12)),
          borderSide: const BorderSide(color: _kPrimary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(r.p(12)),
          borderSide: const BorderSide(color: Colors.red, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(r.p(12)),
          borderSide: const BorderSide(color: Colors.red, width: 1.5),
        ),
      ),
    );
  }
}

// ─── Decorative circle ────────────────────────────────────────────────────────
class _Circle extends StatelessWidget {
  final double size;
  const _Circle({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.07),
      ),
    );
  }
}