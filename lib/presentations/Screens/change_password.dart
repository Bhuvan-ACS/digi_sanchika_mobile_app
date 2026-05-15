// ignore: file_names
import 'package:flutter/material.dart';
import 'package:digi_sanchika/utils/app_theme.dart';
import 'package:digi_sanchika/widgets/app_snackbar.dart';

class ChangePasswordDialog extends StatefulWidget {
  final String employeeId;
  final bool isFirstTime;
  final String defaultPassword;
  final Function(String, String, String) onChangePassword;

  const ChangePasswordDialog({
    super.key,
    required this.employeeId,
    this.isFirstTime = false,
    required this.defaultPassword,
    required this.onChangePassword,
  });

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _currentPwCtrl = TextEditingController();
  final _newPwCtrl = TextEditingController();
  final _confirmPwCtrl = TextEditingController();

  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;
  bool _isLoading = false;
  bool _submittedOnce = false;
  String? _apiErrorMessage;
  String? _currentPwApiError;

  // Password strength (0–4)
  int _strength = 0;

  static final RegExp _specialRe = RegExp(
    r"""[!@#\$%\^&\*\(\)_\+\-=\[\]\{\}\\|;:'",\.<>\/\?]""",
  );
  static final RegExp _repeat4Re = RegExp(r'(.)\1\1\1');
  static final RegExp _blockedPrefixRe =
      RegExp(r'^(password|123456|qwerty|admin)', caseSensitive: false);

  @override
  void initState() {
    super.initState();
    if (widget.isFirstTime) {
      _currentPwCtrl.text = widget.defaultPassword;
    }
    _newPwCtrl.addListener(_updateStrength);
  }

  @override
  void dispose() {
    _newPwCtrl.removeListener(_updateStrength);
    _currentPwCtrl.dispose();
    _newPwCtrl.dispose();
    _confirmPwCtrl.dispose();
    super.dispose();
  }

  void _updateStrength() {
    final pw = _newPwCtrl.text;
    int score = 0;
    if (pw.length >= 8) score++;
    if (pw.contains(RegExp(r'[A-Z]'))) score++;
    if (pw.contains(RegExp(r'[0-9]'))) score++;
    if (pw.contains(_specialRe)) score++;
    setState(() => _strength = score);
  }

  bool get _hasMinLength => _newPwCtrl.text.length >= 8;
  bool get _hasMaxLength => _newPwCtrl.text.length <= 72;
  bool get _hasUppercase => _newPwCtrl.text.contains(RegExp(r'[A-Z]'));
  bool get _hasLowercase => _newPwCtrl.text.contains(RegExp(r'[a-z]'));
  bool get _hasNumber => _newPwCtrl.text.contains(RegExp(r'[0-9]'));
  bool get _hasSpecial =>
      _newPwCtrl.text.contains(_specialRe);
  bool get _hasNoBlockedPrefix =>
      !_blockedPrefixRe.hasMatch(_newPwCtrl.text.trim());
  bool get _hasNoRepeats => !_repeat4Re.hasMatch(_newPwCtrl.text);

  // ── Strength metadata ───────────────────────────────────────────────────

  static const _strengthLabels = ['', 'Weak', 'Fair', 'Good', 'Strong'];
  static const _strengthColors = [
    Colors.transparent,
    AppColors.error,
    AppColors.warning,
    Color(0xFF2563EB),
    AppColors.success,
  ];

  Color get _strengthColor => _strengthColors[_strength];
  String get _strengthLabel => _strengthLabels[_strength];

  // ── Submit ──────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _submittedOnce = true;
      _apiErrorMessage = null;
      _currentPwApiError = null;
    });
    if (!_formKey.currentState!.validate()) return;

    if (_newPwCtrl.text != _confirmPwCtrl.text) {
      AppSnackbar.error(context, 'New password and confirm password do not match');
      return;
    }
    if (_newPwCtrl.text == _currentPwCtrl.text) {
      AppSnackbar.warning(context, 'New password cannot be same as current password');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await Future.delayed(const Duration(milliseconds: 50));
      await widget.onChangePassword(
        _currentPwCtrl.text.trim(),
        _newPwCtrl.text.trim(),
        _confirmPwCtrl.text.trim(),
      );
      if (mounted) {
        AppSnackbar.success(
          context,
          widget.isFirstTime
              ? 'Password set successfully!'
              : 'Password changed successfully!',
        );
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) Navigator.pop(context, _newPwCtrl.text.trim());
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '').trim();
        final lower = msg.toLowerCase();
        setState(() {
          _apiErrorMessage = msg.isEmpty
              ? 'Failed to ${widget.isFirstTime ? 'set' : 'change'} password'
              : msg;
          if (lower.contains('current password') ||
              lower.contains('old password') ||
              lower.contains('incorrect') ||
              lower.contains('invalid')) {
            _currentPwApiError = _apiErrorMessage;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      backgroundColor: AppColors.surface,
      elevation: 12,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: const Icon(
                      Icons.lock_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.isFirstTime
                              ? 'Set Your New Password'
                              : 'Change Password',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'ID: ${widget.employeeId}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!widget.isFirstTime)
                    GestureDetector(
                      onTap: () => Navigator.pop(context, null),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),

              // First-time notice
              if (widget.isFirstTime) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: const Color(0xFFFCD34D)),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: AppColors.warning,
                        size: 18,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'First login detected. Please set a secure password.',
                          style: TextStyle(
                            color: Color(0xFF92400E),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (_apiErrorMessage != null && _apiErrorMessage!.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.errorLight,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: AppColors.errorBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: AppColors.error,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _apiErrorMessage!.trim(),
                          style: const TextStyle(
                            color: AppColors.error,
                            fontSize: 13,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              Form(
                key: _formKey,
                autovalidateMode: _submittedOnce
                    ? AutovalidateMode.onUserInteraction
                    : AutovalidateMode.disabled,
                child: Column(
                  children: [
                    _PasswordField(
                      controller: _currentPwCtrl,
                      label: widget.isFirstTime
                          ? 'Default Password'
                          : 'Current Password',
                      hint: widget.isFirstTime
                          ? 'System default password'
                          : 'Enter your current password',
                      isVisible: _showCurrent,
                      readOnly: widget.isFirstTime,
                      onToggle: () =>
                          setState(() => _showCurrent = !_showCurrent),
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Please enter ${widget.isFirstTime ? 'default' : 'current'} password';
                        }
                        if (_currentPwApiError != null &&
                            _currentPwApiError!.trim().isNotEmpty) {
                          return _currentPwApiError!.trim();
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    _PasswordField(
                      controller: _newPwCtrl,
                      label: 'New Password',
                      hint: 'Enter your new password',
                      isVisible: _showNew,
                      onToggle: () => setState(() => _showNew = !_showNew),
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Please enter new password';
                        }
                        if (v.length < 8) {
                          return 'Password must be at least 8 characters';
                        }
                        if (v.length > 72) {
                          return 'Password must be at most 72 characters';
                        }
                        if (!v.contains(RegExp(r'[A-Z]'))) {
                          return 'Password must contain at least one uppercase letter';
                        }
                        if (!v.contains(RegExp(r'[a-z]'))) {
                          return 'Password must contain at least one lowercase letter';
                        }
                        if (!v.contains(RegExp(r'[0-9]'))) {
                          return 'Password must contain at least one digit';
                        }
                        if (!v.contains(_specialRe)) {
                          return 'Password must contain at least one special character';
                        }
                        if (_blockedPrefixRe.hasMatch(v.trim())) {
                          return 'Password is too common. Please choose another.';
                        }
                        if (_repeat4Re.hasMatch(v)) {
                          return 'Password cannot contain 4+ repeated characters';
                        }
                        return null;
                      },
                    ),

                    // Strength bar (shown once user starts typing)
                    if (_newPwCtrl.text.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _StrengthBar(
                        strength: _strength,
                        color: _strengthColor,
                        label: _strengthLabel,
                      ),
                      const SizedBox(height: 10),
                      _RequirementChecklist(
                        hasMinLength: _hasMinLength,
                        hasUppercase: _hasUppercase,
                        hasNumber: _hasNumber,
                        hasSpecial: _hasSpecial,
                      ),
                    ],

                    const SizedBox(height: 16),

                    _PasswordField(
                      controller: _confirmPwCtrl,
                      label: 'Confirm Password',
                      hint: 'Re-enter your new password',
                      isVisible: _showConfirm,
                      onToggle: () =>
                          setState(() => _showConfirm = !_showConfirm),
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Please confirm your password';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Action buttons
              Row(
                children: [
                  if (!widget.isFirstTime) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isLoading
                            ? null
                            : () => Navigator.pop(context, null),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.sm),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              widget.isFirstTime
                                  ? 'Set Password'
                                  : 'Save Password',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

// ── Password field ──────────────────────────────────────────────────────────

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool isVisible;
  final bool readOnly;
  final VoidCallback onToggle;
  final String? Function(String?)? validator;

  const _PasswordField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.isVisible,
    required this.onToggle,
    this.readOnly = false,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 7),
        TextFormField(
          controller: controller,
          obscureText: !isVisible,
          readOnly: readOnly,
          validator: validator,
          style: TextStyle(
            color: readOnly ? AppColors.textSecondary : AppColors.textPrimary,
            fontStyle:
                readOnly ? FontStyle.italic : FontStyle.normal,
            fontSize: 14,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 13,
            ),
            filled: true,
            fillColor: readOnly
                ? AppColors.surfaceVariant
                : AppColors.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 13,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              borderSide: const BorderSide(color: AppColors.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              borderSide:
                  const BorderSide(color: AppColors.error, width: 1.5),
            ),
            suffixIcon: readOnly
                ? null
                : IconButton(
                    icon: Icon(
                      isVisible
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: onToggle,
                  ),
          ),
        ),
      ],
    );
  }
}

// ── Strength bar ────────────────────────────────────────────────────────────

class _StrengthBar extends StatelessWidget {
  final int strength;
  final Color color;
  final String label;

  const _StrengthBar({
    required this.strength,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(4, (i) {
            final filled = i < strength;
            return Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: 5,
                margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                decoration: BoxDecoration(
                  color: filled ? color : AppColors.border,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            );
          }),
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(height: 5),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Requirement checklist ───────────────────────────────────────────────────

class _RequirementChecklist extends StatelessWidget {
  final bool hasMinLength;
  final bool hasUppercase;
  final bool hasNumber;
  final bool hasSpecial;

  const _RequirementChecklist({
    required this.hasMinLength,
    required this.hasUppercase,
    required this.hasNumber,
    required this.hasSpecial,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                  child: _Req(label: 'At least 8 characters', met: hasMinLength)),
              const SizedBox(width: 8),
              Expanded(
                  child: _Req(label: 'One uppercase letter', met: hasUppercase)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _Req(label: 'One number', met: hasNumber)),
              const SizedBox(width: 8),
              Expanded(
                  child: _Req(label: 'One special character', met: hasSpecial)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Req extends StatelessWidget {
  final String label;
  final bool met;

  const _Req({required this.label, required this.met});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Icon(
            met ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            key: ValueKey(met),
            size: 13,
            color: met ? AppColors.success : AppColors.textTertiary,
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: met ? AppColors.success : AppColors.textSecondary,
              fontWeight: met ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}
