import 'package:digi_sanchika/models/folder_members.dart';
import 'package:digi_sanchika/services/sharing_service.dart';
import 'package:digi_sanchika/utils/app_theme.dart';
import 'package:digi_sanchika/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// Stacked avatar circles showing the members who have access to a folder.
///
/// Fetches [FolderMembersResponse] once on mount using [SharingService].
/// Shows up to [maxVisible] initials; any remainder is shown as "+N".
/// Gracefully degrades to a single grey placeholder on load or error.
class FolderMemberAvatarStack extends StatefulWidget {
  const FolderMemberAvatarStack({
    super.key,
    required this.folderId,
    this.size = 26.0,
    this.overlap = 18.0,
    this.maxVisible = 3,
    this.fallbackInitial,
  });

  final String folderId;

  /// Diameter of each avatar circle in logical pixels.
  final double size;

  /// How many pixels each subsequent avatar is shifted right (creates the
  /// overlapping effect). Should be < [size].
  final double overlap;

  /// Maximum number of initials circles to render before showing "+N".
  final int maxVisible;

  /// Single initial to display while loading or when no members exist yet.
  /// Typically the current user's first letter.
  final String? fallbackInitial;

  @override
  State<FolderMemberAvatarStack> createState() =>
      _FolderMemberAvatarStackState();
}

class _FolderMemberAvatarStackState extends State<FolderMemberAvatarStack> {
  static final _service = SharingService();

  // Small in-process cache so rebuilds of the same folderId skip the network.
  static final _cache = <String, FolderMembersResponse>{};

  FolderMembersResponse? _data;
  bool _loading = true;

  static const _palette = <Color>[
    Color(0xFF1E88E5), // blue
    Color(0xFF43A047), // green
    Color(0xFFE53935), // red
    Color(0xFF8E24AA), // purple
    Color(0xFFFB8C00), // orange
    Color(0xFF00ACC1), // cyan
    Color(0xFF6D4C41), // brown
  ];

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  @override
  void didUpdateWidget(FolderMemberAvatarStack old) {
    super.didUpdateWidget(old);
    if (old.folderId != widget.folderId) _loadMembers();
  }

  Future<void> _loadMembers() async {
    if (_cache.containsKey(widget.folderId)) {
      if (mounted) setState(() { _data = _cache[widget.folderId]; _loading = false; });
      return;
    }
    try {
      final result = await _service.getFolderMembers(widget.folderId);
      _cache[widget.folderId] = result;
      if (mounted) setState(() { _data = result; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Deterministic color so the same person always gets the same hue.
  Color _colorFor(FolderMember m) {
    final hash = m.userId.isNotEmpty ? m.userId.hashCode : m.fullName.hashCode;
    return _palette[hash.abs() % _palette.length];
  }

  String _initials(FolderMember m) {
    final parts = m.fullName.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return m.fullName.isNotEmpty ? m.fullName[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;

    // ── Loading: one grey ghost circle ────────────────────────────────────
    if (_loading) {
      return _circle(
        size: widget.size,
        color: AppColors.border,
        child: const SizedBox.shrink(),
      );
    }

    final members = _data?.members ?? const [];
    final total = _data?.totalMembers ?? 0;

    // ── No members yet: fallback initial (e.g. current user) ─────────────
    if (members.isEmpty) {
      final initial = widget.fallbackInitial ?? '?';
      return _circle(
        size: widget.size,
        color: _palette[initial.codeUnitAt(0) % _palette.length],
        child: Text(
          initial,
          style: TextStyle(
            color: Colors.white,
            fontSize: r.sp(9),
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    // ── Render up to [maxVisible] avatars + optional overflow badge ───────
    final visible = members.take(widget.maxVisible).toList();
    final overflow = total - visible.length; // may be 0
    final extraSlots = overflow > 0 ? 1 : 0;
    final stackWidth =
        widget.size + (visible.length - 1 + extraSlots) * widget.overlap;

    return SizedBox(
      height: widget.size,
      width: stackWidth,
      child: Stack(
        children: [
          // Member initials
          for (int i = 0; i < visible.length; i++)
            Positioned(
              left: i * widget.overlap,
              child: _circle(
                size: widget.size,
                color: _colorFor(visible[i]),
                child: Text(
                  _initials(visible[i]),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: r.sp(8),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

          // "+N" overflow badge
          if (overflow > 0)
            Positioned(
              left: visible.length * widget.overlap,
              child: _circle(
                size: widget.size,
                color: AppColors.textTertiary,
                child: Text(
                  '+$overflow',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: r.sp(7),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _circle({
    required double size,
    required Color color,
    required Widget child,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}
