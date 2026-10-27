// ignore_for_file: use_build_context_synchronously
import 'dart:io';

import 'package:digi_sanchika/models/profile.dart';
import 'package:digi_sanchika/services/api_service.dart';
import 'package:digi_sanchika/services/profile_store.dart';
import 'package:digi_sanchika/utils/app_fonts.dart';
import 'package:digi_sanchika/widgets/app_snackbar.dart';
import 'package:digi_sanchika/widgets/profile_avatar.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// ─── Colour tokens (royal blue, matches the Profile card) ─────────────────────
const _kPrimary = Color(0xFF2563EB);
const _kGradStart = Color(0xFF1D4ED8);
const _kGradEnd = Color(0xFF1E40AF);
const _kBg = Color(0xFFF4F5F9);
const _kInk = Color(0xFF1E293B);

// ─── Screen ───────────────────────────────────────────────────────────────────
class ProfileDetailsScreen extends StatefulWidget {
  const ProfileDetailsScreen({super.key});

  @override
  State<ProfileDetailsScreen> createState() => _ProfileDetailsScreenState();
}

class _ProfileDetailsScreenState extends State<ProfileDetailsScreen> {
  final _store = ProfileStore.instance;
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = true;
  bool _hasError = false;
  String _errorMsg = '';
  bool _isSaving = false;

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _roleCtrl = TextEditingController();
  final _employeeIdCtrl = TextEditingController();
  final _departmentCtrl = TextEditingController();
  final _sinceCtrl = TextEditingController();

  /// Encoded [AvatarChoice] being edited (null = initials).
  String? _avatar;

  @override
  void initState() {
    super.initState();
    final cached = _store.profile;
    if (cached != null) {
      _fill(cached);
      _isLoading = false;
    } else {
      _loadProfile();
    }
    _nameCtrl.addListener(_refreshInitials);
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_refreshInitials);
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _roleCtrl.dispose();
    _employeeIdCtrl.dispose();
    _departmentCtrl.dispose();
    _sinceCtrl.dispose();
    super.dispose();
  }

  void _refreshInitials() {
    if (_avatar == null && mounted) setState(() {});
  }

  void _fill(UserProfile p) {
    _nameCtrl.text = p.employeeName;
    _emailCtrl.text = p.email == 'Not Provided' ? '' : p.email;
    _roleCtrl.text = p.roleLabel;
    _employeeIdCtrl.text = p.employeeId == 'Unknown' ? '' : p.employeeId;
    _departmentCtrl.text = p.department;
    _sinceCtrl.text = p.sinceLabel == '—' ? '' : p.sinceLabel;
    _avatar = _store.avatar;
  }

  // ── Load ──────────────────────────────────────────────────────────────────
  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final res = await _store.load();
      if (!mounted) return;
      final profile = _store.profile;
      if (res['success'] == true && profile != null) {
        setState(() {
          _fill(profile);
          _isLoading = false;
        });
      } else {
        if (res['statusCode'] == 401) {
          await ApiService.clearTokens();
          if (mounted) {
            Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
          }
          return;
        }
        setState(() {
          _hasError = true;
          _errorMsg = res['message'] ?? 'Failed to load profile';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMsg = 'Error: $e';
          _isLoading = false;
        });
      }
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────
  Future<void> _saveChanges() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      AppSnackbar.error(context, 'Please fix the highlighted fields');
      return;
    }
    setState(() => _isSaving = true);
    try {
      await _store.save(
        employeeName: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        designation: _roleCtrl.text.trim(),
        employeeId: _employeeIdCtrl.text.trim(),
        department: _departmentCtrl.text.trim(),
        sinceYear: _sinceCtrl.text.trim(),
        avatar: _avatar,
      );
      if (!mounted) return;
      AppSnackbar.success(context, 'Profile updated successfully');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      AppSnackbar.error(context, 'Could not save profile: $e');
    }
  }

  // ── Avatar actions ────────────────────────────────────────────────────────
  Future<void> _pickPhoto() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      final path = result?.files.single.path;
      if (path == null) return;
      // Copy out of the picker's cache, which the OS may clear.
      final dir = await getApplicationDocumentsDirectory();
      final target = p.join(
        dir.path,
        'profile_avatar_${DateTime.now().millisecondsSinceEpoch}${p.extension(path)}',
      );
      await File(path).copy(target);
      if (mounted) setState(() => _avatar = AvatarChoice.photo(target).encode());
    } catch (e) {
      if (mounted) AppSnackbar.error(context, 'Could not load photo: $e');
    }
  }

  Future<void> _openGenerator() async {
    final existing = AvatarChoice.decode(_avatar);
    final encoded = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AvatarGeneratorSheet(
        initialPrompt: existing?.kind == 'gen' ? existing!.value : '',
      ),
    );
    if (encoded != null && mounted) setState(() => _avatar = encoded);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  // ── Validators ────────────────────────────────────────────────────────────
  String? _required(String? v, String label) =>
      (v == null || v.trim().isEmpty) ? '$label is required' : null;

  String? _validateName(String? v) {
    final err = _required(v, 'Full name');
    if (err != null) return err;
    return v!.trim().length < 2 ? 'Name must be at least 2 characters' : null;
  }

  String? _validateEmail(String? v) {
    final err = _required(v, 'Email');
    if (err != null) return err;
    final ok = RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$').hasMatch(v!.trim());
    return ok ? null : 'Enter a valid email address';
  }

  String? _validateEmployeeId(String? v) {
    final err = _required(v, 'Employee ID');
    if (err != null) return err;
    return RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(v!.trim())
        ? null
        : 'Use letters, numbers, - or _ only';
  }

  String? _validateYear(String? v) {
    final err = _required(v, 'Year');
    if (err != null) return err;
    final year = int.tryParse(v!.trim());
    final now = DateTime.now().year;
    if (year == null || v.trim().length != 4) return 'Enter a 4-digit year';
    if (year < 1950 || year > now) return 'Year must be 1950–$now';
    return null;
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: _appBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : _hasError
          ? _buildError()
          : _buildContent(),
    );
  }

  Widget _buildError() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline_rounded, size: 56, color: Colors.red.shade300),
        const SizedBox(height: 16),
        Text(
          _errorMsg,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _loadProfile,
          style: ElevatedButton.styleFrom(backgroundColor: _kPrimary),
          child: const Text('Retry', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );

  Widget _buildContent() {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAvatarSection(),
              const SizedBox(height: 24),
              _sectionHeader('PERSONAL INFORMATION'),
              const SizedBox(height: 10),
              _buildCard([
                _field(
                  label: 'Full Name',
                  controller: _nameCtrl,
                  icon: Icons.person_outline_rounded,
                  validator: _validateName,
                  textCapitalization: TextCapitalization.words,
                ),
                _field(
                  label: 'Email Address',
                  controller: _emailCtrl,
                  icon: Icons.email_outlined,
                  validator: _validateEmail,
                  keyboardType: TextInputType.emailAddress,
                ),
              ]),
              const SizedBox(height: 24),
              _sectionHeader('WORK INFORMATION'),
              const SizedBox(height: 10),
              _buildCard([
                _field(
                  label: 'Role / Designation',
                  controller: _roleCtrl,
                  icon: Icons.shield_outlined,
                  validator: (v) => _required(v, 'Role'),
                  textCapitalization: TextCapitalization.words,
                ),
                _field(
                  label: 'Employee ID',
                  controller: _employeeIdCtrl,
                  icon: Icons.badge_outlined,
                  validator: _validateEmployeeId,
                ),
                _field(
                  label: 'Department',
                  controller: _departmentCtrl,
                  icon: Icons.business_outlined,
                  validator: (v) => _required(v, 'Department'),
                  textCapitalization: TextCapitalization.words,
                ),
                _field(
                  label: 'Since (Year)',
                  controller: _sinceCtrl,
                  icon: Icons.calendar_today_outlined,
                  validator: _validateYear,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  isLast: true,
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────
  PreferredSizeWidget _appBar() => AppBar(
    backgroundColor: _kBg,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: true,
    systemOverlayStyle: SystemUiOverlayStyle.dark,
    title: const Text(
      'Edit Profile Details',
      style: TextStyle(
        fontFamily: appFontFamily,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: _kInk,
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
            icon: const Icon(Icons.arrow_back_ios_new, size: 16, color: _kInk),
          ),
        ),
      ),
    ),
    actions: [
      if (!_isLoading && !_hasError)
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: FilledButton(
            onPressed: _isSaving ? null : _saveChanges,
            style: FilledButton.styleFrom(
              backgroundColor: _kPrimary,
              disabledBackgroundColor: _kPrimary.withOpacity(0.6),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(0, 36),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Save Changes',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
    ],
  );

  // ── Avatar section ────────────────────────────────────────────────────────
  Widget _buildAvatarSection() {
    final choice = AvatarChoice.decode(_avatar);
    final selectedPreset = choice?.kind == 'preset'
        ? int.tryParse(choice!.value)
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 18),
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
      child: Column(
        children: [
          // Gradient ring around the avatar
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [_kGradStart, _kPrimary, _kGradEnd],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: _kPrimary.withOpacity(0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: ProfileAvatar(
                initials: _initials(_nameCtrl.text),
                avatar: _avatar,
                size: 96,
                background: _kPrimary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _avatarAction(
                icon: Icons.file_upload_outlined,
                label: 'Upload Photo',
                onTap: _pickPhoto,
              ),
              _avatarAction(
                icon: Icons.auto_awesome_rounded,
                label: 'Generate',
                onTap: _openGenerator,
              ),
              if (_avatar != null)
                _avatarAction(
                  icon: Icons.restart_alt_rounded,
                  label: 'Use Initials',
                  onTap: () => setState(() => _avatar = null),
                  muted: true,
                ),
            ],
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Quick presets',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade500,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: AvatarChoice.presets.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final selected = selectedPreset == i;
                return GestureDetector(
                  onTap: () => setState(
                    () => _avatar = AvatarChoice.preset(i).encode(),
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? _kPrimary : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    child: ProfileAvatar(
                      initials: '',
                      avatar: AvatarChoice.preset(i).encode(),
                      size: 54,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool muted = false,
  }) {
    final color = muted ? Colors.grey.shade600 : _kPrimary;
    return Material(
      color: muted ? const Color(0xFFF1F3F7) : const Color(0xFFEEF3FF),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Section header ────────────────────────────────────────────────────────
  Widget _sectionHeader(String title) => Text(
    title,
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: Colors.grey.shade500,
      letterSpacing: 1.1,
    ),
  );

  // ── White card wrapper ────────────────────────────────────────────────────
  Widget _buildCard(List<Widget> children) => Container(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
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

  // ── Editable field ────────────────────────────────────────────────────────
  Widget _field({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required FormFieldValidator<String> validator,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
    bool isLast = false,
  }) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: c, width: w),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        validator: validator,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        inputFormatters: inputFormatters,
        textInputAction: isLast ? TextInputAction.done : TextInputAction.next,
        onFieldSubmitted: isLast ? (_) => _saveChanges() : null,
        cursorColor: _kPrimary,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: _kInk,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade500,
            fontWeight: FontWeight.w500,
          ),
          floatingLabelStyle: const TextStyle(
            color: _kPrimary,
            fontWeight: FontWeight.w600,
          ),
          prefixIcon: Icon(icon, size: 20, color: _kPrimary),
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: border(const Color(0xFFE5E9F2)),
          enabledBorder: border(const Color(0xFFE5E9F2)),
          focusedBorder: border(_kPrimary, 1.5),
          errorBorder: border(Colors.red.shade300),
          focusedErrorBorder: border(Colors.red.shade400, 1.5),
        ),
      ),
    );
  }
}

// ─── Prompt-based avatar generator ────────────────────────────────────────────
class _AvatarGeneratorSheet extends StatefulWidget {
  const _AvatarGeneratorSheet({required this.initialPrompt});

  final String initialPrompt;

  @override
  State<_AvatarGeneratorSheet> createState() => _AvatarGeneratorSheetState();
}

class _AvatarGeneratorSheetState extends State<_AvatarGeneratorSheet> {
  late final TextEditingController _promptCtrl;

  static const _suggestions = [
    'Calm ocean at sunset',
    'Rocket in deep space',
    'Coffee and code',
    'Mountain adventure',
    'Playful cat',
    'Music lover',
  ];

  @override
  void initState() {
    super.initState();
    _promptCtrl = TextEditingController(text: widget.initialPrompt)
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _promptCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prompt = _promptCtrl.text.trim();
    final hasPrompt = prompt.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Generate an Avatar',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _kInk,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Describe a vibe — the same prompt always gives the same avatar.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 18),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: hasPrompt
                    ? ProfileAvatar(
                        key: ValueKey(prompt.toLowerCase()),
                        initials: '',
                        avatar: AvatarChoice.generated(prompt).encode(),
                        size: 88,
                      )
                    : Container(
                        key: const ValueKey('empty'),
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFEEF3FF),
                          border: Border.all(color: const Color(0xFFDBE4FF)),
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          color: _kPrimary,
                          size: 34,
                        ),
                      ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _promptCtrl,
                autofocus: widget.initialPrompt.isEmpty,
                maxLength: 60,
                textCapitalization: TextCapitalization.sentences,
                cursorColor: _kPrimary,
                decoration: InputDecoration(
                  hintText: 'e.g. Rocket in deep space',
                  counterText: '',
                  prefixIcon: const Icon(
                    Icons.edit_note_rounded,
                    color: _kPrimary,
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE5E9F2)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE5E9F2)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _kPrimary, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in _suggestions)
                    ActionChip(
                      label: Text(s, style: const TextStyle(fontSize: 12)),
                      backgroundColor: const Color(0xFFF1F5FF),
                      side: BorderSide.none,
                      onPressed: () {
                        _promptCtrl.text = s;
                        _promptCtrl.selection = TextSelection.collapsed(
                          offset: s.length,
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: hasPrompt
                      ? () => Navigator.of(
                          context,
                        ).pop(AvatarChoice.generated(prompt).encode())
                      : null,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text(
                    'Use This Avatar',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: _kPrimary,
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
    );
  }
}
