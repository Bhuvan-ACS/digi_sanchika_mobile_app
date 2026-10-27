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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:digi_sanchika/theme/ui_theme.dart';
import 'package:digi_sanchika/widgets/auth_widgets.dart';

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
    return AuthPage(
      showBack: false,
      maxSheetFraction: 0.66,
      children: [
        // Long-press the title for the push-notification debug screen.
        GestureDetector(
          onLongPress: () => Navigator.of(context).pushNamed('/push-debug'),
          child: const AuthTitle(
            title: 'Welcome back',
            subtitle:
                'Sign in to access your documents, requests and shared workspace.',
          ),
        ),
        const SizedBox(height: 28),
        AutofillGroup(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Work Email field ─────────────────────────────────────
                TextFormField(
                  controller: _employeeIdController,
                  focusNode: _employeeFocus,
                  enabled: !_isLoading,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const [
                    AutofillHints.username,
                    AutofillHints.email,
                  ],
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your identifier';
                    }
                    if (value.contains('@') &&
                        !RegExp(
                          r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                        ).hasMatch(value)) {
                      return 'Please enter a valid email address';
                    }
                    return null;
                  },
                  decoration: authInputDecoration(
                    label: 'Work Email',
                    hint: 'Enter email or employee ID',
                    icon: Icons.mail_outline_rounded,
                  ),
                ),
                const SizedBox(height: 16),

                // ── Password field ───────────────────────────────────────
                TextFormField(
                  controller: _passwordController,
                  focusNode: _passwordFocus,
                  enabled: !_isLoading,
                  obscureText: !_isPasswordVisible,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _attemptLogin(),
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    return null;
                  },
                  decoration: authInputDecoration(
                    label: 'Password',
                    hint: 'Enter your password',
                    icon: Icons.lock_outline_rounded,
                    suffix: IconButton(
                      onPressed: () => setState(
                        () => _isPasswordVisible = !_isPasswordVisible,
                      ),
                      icon: Icon(
                        _isPasswordVisible
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: UiColors.muted,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // ── Remember me + Forgot password ────────────────────────
                Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: Checkbox(
                        value: _rememberMe,
                        onChanged: (v) =>
                            setState(() => _rememberMe = v ?? false),
                        activeColor: UiColors.royalBlue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Remember me',
                      style: TextStyle(fontSize: 13, color: UiColors.muted),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _isLoading ? null : _showForgotPasswordDialog,
                      style: TextButton.styleFrom(
                        foregroundColor: UiColors.royalBlue,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Forgot password?',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Sign In button ───────────────────────────────────────
                AuthPrimaryButton(
                  label: _isInCooldown
                      ? () {
                          final s = _cooldownSecondsRemaining;
                          return 'Try again in ${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
                        }()
                      : 'Sign In',
                  loading: _isLoading,
                  onPressed: (_isLoading || _isInCooldown)
                      ? null
                      : _attemptLogin,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
