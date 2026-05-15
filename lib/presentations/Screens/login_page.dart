// ignore_for_file: use_build_context_synchronously, unused_element

import 'dart:ui';
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
import 'package:digi_sanchika/utils/responsive_helper.dart';
import 'package:digi_sanchika/utils/design_tokens.dart';
import 'package:digi_sanchika/utils/app_theme.dart';

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
  final String _defaultPassword = "default@123";

  static const Duration _fallbackCooldown = Duration(seconds: 30);
  static const Duration _maxCooldown = Duration(minutes: 5);

  DateTime? _loginCooldownUntil;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _initializeApp();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      precacheImage(const AssetImage('assets/images/app-logo.png'), context);
      _maybeShowPermissionsModal();
    });
  }

  /// Shows the permissions modal whenever any required permission is not granted.
  Future<void> _maybeShowPermissionsModal() async {
    if (!mounted) return;
    final needed = await PermissionService.anyNotGranted();
    if (needed && mounted) {
      await showPermissionsModal(context);
    }
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

  bool get _isInCooldown {
    final until = _loginCooldownUntil;
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  int get _cooldownSecondsRemaining {
    final until = _loginCooldownUntil;
    if (until == null) return 0;
    final diff = until.difference(DateTime.now());
    return diff.isNegative ? 0 : diff.inSeconds;
  }

  void _startCooldown(Duration duration) {
    final clamped = _clampCooldown(duration);
    final until = DateTime.now().add(clamped);
    _cooldownTimer?.cancel();
    setState(() {
      _loginCooldownUntil = until;
    });
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (!_isInCooldown) {
        t.cancel();
        setState(() {});
      } else {
        // Tick UI.
        setState(() {});
      }
    });
  }

  Duration? _cooldownFromServerResponse(Map<String, dynamic> response) {
    final retryAfterSeconds = response['retryAfterSeconds'];
    if (retryAfterSeconds is int && retryAfterSeconds > 0) {
      return Duration(seconds: retryAfterSeconds);
    }

    // Fallback: short cooldown to prevent hammering if server didn't send hints.
    return _fallbackCooldown;
  }

  Duration _clampCooldown(Duration duration) {
    if (duration <= Duration.zero) return _fallbackCooldown;
    if (duration > _maxCooldown) return _maxCooldown;
    return duration;
  }

  Future<void> _initializeApp() async {
    await ApiService.initialize();

    if (kDebugMode) {
      _employeeIdController.text = '';
      _passwordController.text = '';
    }
  }

  Future<void> _attemptLogin() async {
    if (_isLoading) return;
    if (_isInCooldown) {
      final s = _cooldownSecondsRemaining;
      final m = (s ~/ 60).toString().padLeft(2, '0');
      final ss = (s % 60).toString().padLeft(2, '0');
      _showSnackBar(
        'Too many attempts. Try again in $m:$ss.',
        Colors.orange,
        duration: 3,
      );
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final employeeId = _employeeIdController.text.trim();
    final password = _passwordController.text.trim();

    // Check if password is default password
    if (password == _defaultPassword) {
      _showSnackBar(
        'Default password detected. Please change your password.',
        Colors.orange,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showChangePasswordDialog(isFirstTime: true);
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    if (kDebugMode) {
      print('Attempting login with identifier: $employeeId');
    }

    final response = await ApiService.login(employeeId, password);

    if (kDebugMode) {
      print('Login response: $response');
    }

    if (response['success'] == true) {
      _showSnackBar('Login successful!', Colors.green);

      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      final rawData = response['data'];
      Map<String, dynamic> userData = {};

      if (rawData is Map<String, dynamic>) {
        final user = rawData['user'];
        final data = rawData['data'];
        if (user is Map<String, dynamic>) {
          userData = user;
        } else if (data is Map<String, dynamic>) {
          userData = data;
        } else {
          userData = rawData;
        }
      }

      final name =
          <String?>[
                userData['name']?.toString(),
                userData['full_name']?.toString(),
                userData['fullName']?.toString(),
                userData['username']?.toString(),
              ]
              .whereType<String>()
              .map((s) => s.trim())
              .firstWhere((s) => s.isNotEmpty, orElse: () => '');

      final email =
          <String?>[
                userData['email']?.toString(),
                userData['user_email']?.toString(),
                userData['mail']?.toString(),
              ]
              .whereType<String>()
              .map((s) => s.trim())
              .firstWhere((s) => s.isNotEmpty, orElse: () => '');

      var effectiveName = name;
      var effectiveEmail = email;

      // Many backends return only tokens on login; fetch /auth/me for real profile.
      if (effectiveName.isEmpty || effectiveName.toLowerCase() == 'user') {
        try {
          final prof = await ProfileService.getUserProfile();
          if (prof['success'] == true && prof['data'] != null) {
            final data = prof['data'];
            Map<String, dynamic> u = {};
            if (data is Map<String, dynamic>) {
              final inner = data['user'];
              if (inner is Map<String, dynamic>) {
                u = inner;
              } else {
                u = data;
              }
            }
            final pn =
                <String?>[
                      u['name']?.toString(),
                      u['full_name']?.toString(),
                      u['fullName']?.toString(),
                      u['username']?.toString(),
                    ]
                    .whereType<String>()
                    .map((s) => s.trim())
                    .firstWhere((s) => s.isNotEmpty, orElse: () => '');

            final pe =
                <String?>[
                      u['email']?.toString(),
                      u['user_email']?.toString(),
                      u['mail']?.toString(),
                    ]
                    .whereType<String>()
                    .map((s) => s.trim())
                    .firstWhere((s) => s.isNotEmpty, orElse: () => '');

            if (pn.isNotEmpty) effectiveName = pn;
            if (pe.isNotEmpty) effectiveEmail = pe;
          }
        } catch (_) {}
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_name', effectiveName);
      await prefs.setString(
        'user_email',
        effectiveEmail.isNotEmpty ? effectiveEmail : employeeId,
      );

      // Initialize FCM + local notifications only after we know the user is authenticated.
      try {
        await PushNotificationsService.instance.initAfterLogin();
      } catch (_) {}

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => HomePage(
            userName: effectiveName.isNotEmpty ? effectiveName : 'User',
            userEmail: effectiveEmail.isNotEmpty ? effectiveEmail : employeeId,
          ),
        ),
      );
    } else {
      // ENHANCED ERROR DETECTION FOR PASSWORD CHANGE
      final message = response['message']?.toString().toLowerCase() ?? '';
      final statusCode = response['statusCode'] ?? 0;

      // Only enforce client-side cooldown when backend explicitly rate-limits (429).
      // Avoid parsing long waits (e.g., "45 mins") from arbitrary error messages.
      if (statusCode == 429) {
        final cd = _cooldownFromServerResponse(response);
        _startCooldown(cd ?? _fallbackCooldown);
        _showSnackBar(
          response['message'] ??
              'Too many attempts. Please wait and try again.',
          Colors.orange,
          duration: 4,
        );
      } else
      // Check if server is asking for password change
      if (message.contains('change password') ||
          message.contains('password expired') ||
          message.contains('first login') ||
          message.contains('default password') ||
          message.contains('invalid password') ||
          (statusCode == 401 &&
              (message.contains('password') || message.contains('auth'))) ||
          (statusCode == 403 && message.contains('password'))) {
        // Check if we should show password change dialog
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // If it mentions first login or default password, show as first time
          bool isFirstTime =
              message.contains('first login') ||
              message.contains('default password');

          _showChangePasswordDialog(isFirstTime: isFirstTime);
        });
      } else {
        // Regular login failure
        _showSnackBar(response['message'] ?? 'Login failed', Colors.red);
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _showChangePasswordDialog({bool isFirstTime = false}) {
    showDialog(
      context: context,
      barrierDismissible: !isFirstTime,
      builder: (context) => ChangePasswordDialog(
        employeeId: _employeeIdController.text.trim(),
        isFirstTime: isFirstTime,
        defaultPassword: _defaultPassword,
        onChangePassword:
            (currentPassword, newPassword, confirmPassword) async {
              if (kDebugMode) {
                print('=== PASSWORD CHANGE STARTED ===');
                print('Identifier: ${_employeeIdController.text.trim()}');
                print('Current Password: $currentPassword');
                print('New Password: $newPassword');
                print('Confirm Password: $confirmPassword');
              }

              setState(() {
                _isLoading = true;
              });

              // Clear any existing tokens before password change
              await ApiService.clearTokens();

              try {
                final response = await ApiService.changePassword(
                  _employeeIdController.text.trim(),
                  currentPassword,
                  newPassword,
                  confirmPassword,
                );

                if (kDebugMode) {
                  print('=== PASSWORD CHANGE RESPONSE ===');
                  print('Success: ${response['success']}');
                  print('Message: ${response['message']}');
                  print('Status Code: ${response['statusCode']}');
                }

                if (mounted) {
                  setState(() {
                    _isLoading = false;
                  });

                  if (response['success'] == true) {
                    // Return the new password to be used in login
                    return newPassword;
                  } else {
                    throw Exception(
                      response['message'] ?? 'Password change failed',
                    );
                  }
                }
              } catch (e) {
                if (kDebugMode) {
                  print('=== PASSWORD CHANGE ERROR ===');
                  print('Error: $e');
                }
                if (mounted) {
                  setState(() {
                    _isLoading = false;
                  });
                  rethrow;
                }
              }
              return null;
            },
      ),
    ).then((newPassword) {
      // This callback runs after the dialog closes
      if (kDebugMode) {
        print('=== DIALOG CLOSED ===');
        print('Returned value: $newPassword');
      }

      if (newPassword != null && newPassword is String) {
        // Update the password field with the new password
        _passwordController.text = newPassword;

        // Show success message
        _showSnackBar(
          'Password changed successfully! You can now login with your new password.',
          Colors.green,
          duration: 3,
        );

        // Set focus to password field for easy login
        FocusScope.of(context).requestFocus(FocusNode());

        // Auto-attempt login after 1 second
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted &&
              _employeeIdController.text.isNotEmpty &&
              _passwordController.text.isNotEmpty) {
            _attemptLogin();
          }
        });
      }
    });
  }

  void _showForgotPasswordDialog() {
    final emailController = TextEditingController(
      text: _employeeIdController.text.trim(),
    );
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.help_outline, color: Colors.indigo),
            SizedBox(width: 10),
            Text('Forgot Password'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your email and tap “Notify Admin”. If an account exists, administrators will be notified.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [
                AutofillHints.email,
                AutofillHints.username,
              ],
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'user@example.com',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final email = emailController.text.trim();
              if (email.isEmpty ||
                  !RegExp(r'^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$').hasMatch(email)) {
                _showSnackBar('Please enter a valid email address', Colors.red);
                return;
              }

              final res = await ApiService.passwordResetRequest(email);
              if (!mounted) return;

              _showSnackBar(
                (res['message'] ??
                        'If an account exists, administrators have been notified.')
                    .toString(),
                Colors.green,
                duration: 3,
              );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: duration),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = ResponsiveHelper.of(context);
    final layout = AppLayout.of(context);
    final logoSize = r.isMobile ? 88.0 : (r.isTablet ? 110.0 : 128.0);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.brandGradient),
        child: SafeArea(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: layout.gutter,
                  vertical: r.p(24),
                ),
                child: ConstrainedBox(
                  // Cap form width on tablets/desktops so it doesn't stretch
                  constraints: BoxConstraints(
                    maxWidth: r.isMobile ? double.infinity : 520,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // ── Logo ──────────────────────────────────────────────
                      GestureDetector(
                        onLongPress: () {
                          Navigator.of(context).pushNamed('/push-debug');
                        },
                        child: Container(
                          height: logoSize,
                          width: logoSize,
                          padding: EdgeInsets.all(r.p(12)),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(r.p(20)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(20),
                                blurRadius: 15,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/images/app-logo.png',
                            fit: BoxFit.contain,
                            cacheHeight: 200,
                            cacheWidth: 200,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                Icons.library_books_rounded,
                                color: Colors.indigo,
                                size: logoSize * 0.5,
                              );
                            },
                          ),
                        ),
                      ),

                      SizedBox(height: r.p(20)),

                      // ── App title ─────────────────────────────────────────
                      Text(
                        'Digi-Sanchika',
                        style: TextStyle(
                          fontSize: r.sp(30),
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),

                      SizedBox(height: r.p(6)),

                      Text(
                        'Document Management System',
                        style: TextStyle(
                          fontSize: r.sp(14),
                          color: Colors.white70,
                        ),
                      ),

                      SizedBox(height: r.p(40)),

                      // ── Form ──────────────────────────────────────────────
                      AutofillGroup(
                        child: Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              _buildGlassTextField(
                                r: r,
                                controller: _employeeIdController,
                                focusNode: _employeeFocus,
                                label: 'Email or Employee ID',
                                hintText: 'Enter email or employee ID',
                                helperText: null,
                                icon: Icons.badge,
                                keyboardType: TextInputType.text,
                                autofillHints: const [
                                  AutofillHints.username,
                                  AutofillHints.email,
                                ],
                                textInputAction: TextInputAction.next,
                                onFieldSubmitted: (_) =>
                                    _passwordFocus.requestFocus(),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter your identifier';
                                  }
                                  if (value.contains('@')) {
                                    final emailRegex = RegExp(
                                      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                    );
                                    if (!emailRegex.hasMatch(value)) {
                                      return 'Please enter a valid email address';
                                    }
                                  }
                                  return null;
                                },
                              ),

                              SizedBox(height: r.p(20)),

                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  _buildGlassTextField(
                                    r: r,
                                    controller: _passwordController,
                                    focusNode: _passwordFocus,
                                    label: 'Password',
                                    icon: Icons.lock,
                                    obscureText: !_isPasswordVisible,
                                    autofillHints: const [
                                      AutofillHints.password,
                                    ],
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) => _attemptLogin(),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Please enter your password';
                                      }
                                      return null;
                                    },
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _isPasswordVisible
                                            ? Icons.visibility
                                            : Icons.visibility_off,
                                        color: Colors.white70,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _isPasswordVisible =
                                              !_isPasswordVisible;
                                        });
                                      },
                                    ),
                                  ),

                                  TextButton(
                                    onPressed: _isLoading
                                        ? null
                                        : _showForgotPasswordDialog,
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: r.p(8),
                                        vertical: r.p(4),
                                      ),
                                      minimumSize: const Size(0, 0),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.help_outline,
                                          color: Colors.white70,
                                          size: r.sp(14),
                                        ),
                                        SizedBox(width: r.p(4)),
                                        Text(
                                          'Forgot Password?',
                                          style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: r.sp(12),
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      SizedBox(height: r.p(28)),

                      // ── Login button ──────────────────────────────────────
                      SizedBox(
                        width: double.infinity,
                        height: r.p(52),
                        child: ElevatedButton(
                          onPressed: (_isLoading || _isInCooldown)
                              ? null
                              : _attemptLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.indigo,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(r.p(14)),
                            ),
                            elevation: 5,
                          ),
                          child: _isLoading
                              ? SizedBox(
                                  height: r.sp(20),
                                  width: r.sp(20),
                                  child: const CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.indigo,
                                    ),
                                  ),
                                )
                              : Text(
                                  _isInCooldown
                                      ? () {
                                          final s = _cooldownSecondsRemaining;
                                          final m = (s ~/ 60)
                                              .toString()
                                              .padLeft(2, '0');
                                          final ss = (s % 60)
                                              .toString()
                                              .padLeft(2, '0');
                                          return 'Try again in $m:$ss';
                                        }()
                                      : 'Login',
                                  style: TextStyle(
                                    fontSize: r.sp(17),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),

                      SizedBox(height: r.p(24)),

                      // ── Footer ────────────────────────────────────────────
                      Row(
                        children: [
                          Expanded(
                            child: Divider(
                              color: Colors.white.withAlpha(45),
                              thickness: 1,
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: r.p(12)),
                            child: Text(
                              'Powered by ACS Technologies LTD',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: r.sp(11),
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Divider(
                              color: Colors.white.withAlpha(45),
                              thickness: 1,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassTextField({
    required ResponsiveHelper r,
    required TextEditingController controller,
    FocusNode? focusNode,
    required String label,
    String? hintText,
    String? helperText,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    Iterable<String>? autofillHints,
    TextInputAction? textInputAction,
    void Function(String)? onFieldSubmitted,
  }) {
    final radius = BorderRadius.circular(r.p(15));

    // Border is kept outside the BackdropFilter to avoid "broken" seams at the
    // rounded edges due to blur + anti-aliasing compositing.
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: Colors.white.withAlpha(30), width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: radius,
        clipBehavior: Clip.antiAliasWithSaveLayer,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(20),
              borderRadius: radius,
            ),
            child: TextFormField(
              controller: controller,
              focusNode: focusNode,
              keyboardType: keyboardType,
              obscureText: obscureText,
              validator: validator,
              autofillHints: autofillHints,
              textInputAction: textInputAction,
              onFieldSubmitted: onFieldSubmitted,
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              style: TextStyle(color: Colors.white, fontSize: r.sp(15)),
              cursorColor: Colors.white,
              cursorWidth: 2.0,
              decoration: InputDecoration(
                // Avoid the global InputDecorationTheme fill (white) for this
                // "glass" field, otherwise the hint/text becomes unreadable.
                filled: false,
                fillColor: Colors.transparent,
                floatingLabelBehavior: FloatingLabelBehavior.never,
                hintText: hintText ?? label,
                hintStyle: TextStyle(color: Colors.white70, fontSize: r.sp(14)),
                helperText: helperText,
                helperStyle: TextStyle(
                  color: Colors.white70,
                  fontSize: r.sp(12),
                ),
                prefixIcon: Icon(icon, color: Colors.white70, size: r.sp(22)),
                suffixIcon: suffixIcon,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  vertical: r.p(16),
                  horizontal: r.p(16),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
