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
    _newPwCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _currentPwCtrl.dispose();
    _newPwCtrl.dispose();
    _confirmPwCtrl.dispose();
    super.dispose();
  }

  bool get _hasMinLength => _newPwCtrl.text.length >= 8;
  bool get _hasUppercase => _newPwCtrl.text.contains(RegExp(r'[A-Z]'));
  bool get _hasNumber => _newPwCtrl.text.contains(RegExp(r'[0-9]'));
  bool get _hasSpecial => _newPwCtrl.text.contains(_specialRe);

  bool get _hasUppercaseAndNumber => _hasUppercase && _hasNumber;

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

  String? _newPasswordValidator(String? v) {
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
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      backgroundColor: const Color(0xFFF3F4F8),
      elevation: 12,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: back/close pill + title + subtitle
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: widget.isFirstTime
                          ? null
                          : () => Navigator.pop(context, null),
                      child: Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4F63FF).withAlpha(20),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          widget.isFirstTime
                              ? Icons.lock_rounded
                              : Icons.arrow_back_rounded,
                          color: const Color(0xFF4F63FF),
                          size: 20,
                        ),
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
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.isFirstTime
                                ? 'ID: ${widget.employeeId}'
                                : 'Keep your account secure',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
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
                      borderRadius: BorderRadius.circular(14),
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

                if (_apiErrorMessage != null &&
                    _apiErrorMessage!.trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.errorLight,
                      borderRadius: BorderRadius.circular(14),
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

                // Fields card
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(8),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    autovalidateMode: _submittedOnce
                        ? AutovalidateMode.onUserInteraction
                        : AutovalidateMode.disabled,
                    child: Column(
                      children: [
                        _PillPasswordField(
                          controller: _currentPwCtrl,
                          label: widget.isFirstTime
                              ? 'Default Password'
                              : 'Current Password',
                          hint: widget.isFirstTime
                              ? 'System default password'
                              : 'Enter current password',
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
                        _PillPasswordField(
                          controller: _newPwCtrl,
                          label: 'New Password',
                          hint: 'Enter new password',
                          isVisible: _showNew,
                          onToggle: () => setState(() => _showNew = !_showNew),
                          validator: _newPasswordValidator,
                        ),
                        const SizedBox(height: 16),
                        _PillPasswordField(
                          controller: _confirmPwCtrl,
                          label: 'Confirm New Password',
                          hint: 'Re-enter new password',
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
                ),

                const SizedBox(height: 16),

                // Requirements — always visible, matching target design
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF1FE),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Password must contain',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF4F63FF),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _Req(
                        label: 'At least 8 characters',
                        met: _hasMinLength,
                      ),
                      const SizedBox(height: 4),
                      _Req(
                        label: 'One uppercase & one number',
                        met: _hasUppercaseAndNumber,
                      ),
                      const SizedBox(height: 4),
                      _Req(
                        label: 'One special character',
                        met: _hasSpecial,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

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
                              borderRadius: BorderRadius.circular(28),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      flex: widget.isFirstTime ? 1 : 2,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4F63FF),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
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
                                    : 'Update Password',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
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

// ── Password field (pill style) ─────────────────────────────────────────────

class _PillPasswordField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool isVisible;
  final bool readOnly;
  final VoidCallback onToggle;
  final String? Function(String?)? validator;

  const _PillPasswordField({
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
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 7),
        TextFormField(
          controller: controller,
          obscureText: !isVisible,
          readOnly: readOnly,
          validator: validator,
          style: TextStyle(
            color: readOnly ? AppColors.textSecondary : Colors.black87,
            fontStyle: readOnly ? FontStyle.italic : FontStyle.normal,
            fontSize: 14,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 13.5,
            ),
            filled: true,
            fillColor:
                readOnly ? AppColors.surfaceVariant : const Color(0xFFF3F4F8),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(26),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(26),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(26),
              borderSide:
                  const BorderSide(color: Color(0xFF4F63FF), width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(26),
              borderSide: const BorderSide(color: AppColors.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(26),
              borderSide: const BorderSide(color: AppColors.error, width: 1.5),
            ),
            suffixIcon: readOnly
                ? null
                : IconButton(
                    icon: Icon(
                      isVisible
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                      size: 18,
                      color: Colors.grey.shade500,
                    ),
                    onPressed: onToggle,
                  ),
          ),
        ),
      ],
    );
  }
}

// ── Requirement row ─────────────────────────────────────────────────────────

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
            met
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            key: ValueKey(met),
            size: 15,
            color: met ? AppColors.success : Colors.grey.shade400,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: met ? Colors.black87 : Colors.grey.shade600,
              fontWeight: met ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}