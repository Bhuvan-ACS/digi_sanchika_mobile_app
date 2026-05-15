// ignore_for_file: use_build_context_synchronously
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:digi_sanchika/services/permission_service.dart';

// ─── Public entry-point ───────────────────────────────────────────────────────

/// Shows the branded permissions modal. Resolves when the user dismisses it.
Future<void> showPermissionsModal(BuildContext context) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withAlpha(160),
    builder: (_) => const _PermissionsModal(),
  );
}

// ─── Modal widget ─────────────────────────────────────────────────────────────

class _PermissionsModal extends StatefulWidget {
  const _PermissionsModal();

  @override
  State<_PermissionsModal> createState() => _PermissionsModalState();
}

class _PermissionsModalState extends State<_PermissionsModal>
    with SingleTickerProviderStateMixin {
  bool _isRequesting = false;
  late final AnimationController _animController;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _scaleAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutBack,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // ── Permission items ────────────────────────────────────────────────────────

  List<_PermItem> get _items {
    if (Platform.isIOS) {
      return const [
        _PermItem(
          icon: Icons.photo_library_outlined,
          color: Color(0xFF9C27B0),
          title: 'Photos & Media',
          description:
              'Access your photo library to upload images and videos to your workspace.',
        ),
      ];
    }
    return const [
      _PermItem(
        icon: Icons.folder_open_outlined,
        color: Color(0xFF1976D2),
        title: 'Files & Storage',
        description:
            'Access device files to upload documents, spreadsheets, and other files.',
      ),
      _PermItem(
        icon: Icons.photo_library_outlined,
        color: Color(0xFF9C27B0),
        title: 'Photos & Images',
        description:
            'Access your photos to upload images and visual content to your workspace.',
      ),
      _PermItem(
        icon: Icons.video_library_outlined,
        color: Color(0xFFE53935),
        title: 'Videos',
        description:
            'Access video files to upload recordings and media content.',
      ),
      _PermItem(
        icon: Icons.audio_file_outlined,
        color: Color(0xFFE65100),
        title: 'Audio Files',
        description:
            'Access audio recordings to upload voice and media content.',
      ),
    ];
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  Future<void> _allowAll() async {
    setState(() => _isRequesting = true);

    final statuses = await PermissionService.requestAll();

    setState(() => _isRequesting = false);

    final permanentlyDenied = statuses.entries
        .where((e) => e.value.isPermanentlyDenied)
        .toList();

    if (permanentlyDenied.isNotEmpty && mounted) {
      await _showSettingsDialog();
      return;
    }

    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _showSettingsDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.settings_outlined, color: Color(0xFF3949AB)),
            SizedBox(width: 10),
            Text(
              'Open Settings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const Text(
          'Some permissions were permanently denied.\n\n'
          'Please open Settings → Digi Sanchika → Permissions and allow them manually to use all features.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Later',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              PermissionService.openSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3949AB),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Open Settings',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnim,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 22, vertical: 48),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.fromARGB(245, 26, 71, 200),
                    Color(0xFF3949AB),
                    Color(0xFF5C6BC0),
                    Color(0xFF42A5F5),
                  ],
                  stops: [0.0, 0.35, 0.7, 1.0],
                ),
                borderRadius: BorderRadius.all(Radius.circular(28)),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Shield icon ──────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(35),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withAlpha(60),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.security_outlined,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),

                    const SizedBox(height: 18),

                    // ── Title ────────────────────────────────────────────
                    const Text(
                      'App Permissions',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      'Digi Sanchika needs the following permissions to let you upload and manage your documents.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withAlpha(210),
                        fontSize: 13.5,
                        height: 1.45,
                      ),
                    ),

                    const SizedBox(height: 26),

                    // ── Permission rows ──────────────────────────────────
                    ..._items.map(_buildRow),

                    const SizedBox(height: 30),

                    // ── Allow All button ─────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isRequesting ? null : _allowAll,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF3949AB),
                          disabledBackgroundColor:
                              Colors.white.withAlpha(140),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _isRequesting
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Color(0xFF3949AB),
                                  ),
                                ),
                              )
                            : const Text(
                                'Allow All Permissions',
                                style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // ── Not Now ──────────────────────────────────────────
                    TextButton(
                      onPressed: _isRequesting
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text(
                        'Not Now',
                        style: TextStyle(
                          color: Colors.white.withAlpha(179),
                          fontSize: 14,
                        ),
                      ),
                    ),

                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(_PermItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(45), width: 1),
      ),
      child: Row(
        children: [
          // colour-coded icon bubble
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: item.color.withAlpha(55),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(item.icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.description,
                  style: TextStyle(
                    color: Colors.white.withAlpha(191),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.check_circle_outline_rounded,
            color: Colors.white.withAlpha(120),
            size: 20,
          ),
        ],
      ),
    );
  }
}

// ─── Data class ───────────────────────────────────────────────────────────────

class _PermItem {
  const _PermItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String description;
}
