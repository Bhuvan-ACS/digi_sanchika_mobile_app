import 'package:flutter/material.dart';
import 'package:digi_sanchika/theme/ui_theme.dart';
import 'package:digi_sanchika/models/document.dart';

class FileTypeOption {
  const FileTypeOption(this.key, this.label, this.icon, this.count);

  final String key;
  final String label;
  final IconData icon;
  final int count;
}

/// "File Type" filter button with an animated, elevated dropdown panel.
///
/// The panel is shown in an [Overlay] so it floats above the cards instead of
/// pushing or blending into them; a soft scrim and a strong shadow keep it
/// visually distinct. It scales/fades in from the button and its rows
/// cascade in.
class FileTypeDropdown extends StatefulWidget {
  const FileTypeDropdown({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.defaultKey = 'All',
    this.idleLabel = 'File Type',
  });

  final String value;
  final List<FileTypeOption> options;
  final ValueChanged<String> onChanged;
  final String defaultKey;
  final String idleLabel;

  @override
  State<FileTypeDropdown> createState() => _FileTypeDropdownState();
}

class _FileTypeDropdownState extends State<FileTypeDropdown>
    with SingleTickerProviderStateMixin {
  final LayerLink _link = LayerLink();
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 180),
  );
  OverlayEntry? _entry;

  bool get _open => _entry != null;
  bool get _filtered => widget.value != widget.defaultKey;

  String get _label {
    if (!_filtered) return widget.idleLabel;
    return widget.options
        .firstWhere(
          (o) => o.key == widget.value,
          orElse: () => widget.options.first,
        )
        .label;
  }

  void _toggle() => _open ? _close() : _show();

  void _show() {
    _entry = OverlayEntry(builder: _buildOverlay);
    Overlay.of(context).insert(_entry!);
    setState(() {});
    _ctrl.forward();
  }

  Future<void> _close() async {
    if (!_open) return;
    await _ctrl.reverse();
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _entry?.remove();
    _entry = null;
    _ctrl.dispose();
    super.dispose();
  }

  Widget _buildOverlay(BuildContext context) {
    final curved = CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return Stack(
      children: [
        // Scrim: dismisses on tap and dims what is behind the panel.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
            child: FadeTransition(
              opacity: curved,
              child: Container(color: Colors.black.withAlpha(36)),
            ),
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(0, 8),
          child: FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              alignment: Alignment.topRight,
              scale: Tween<double>(begin: 0.85, end: 1).animate(curved),
              child: _panel(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _panel() {
    return Material(
      color: Colors.white,
      elevation: 14,
      shadowColor: Colors.black.withAlpha(90),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 210, maxWidth: 240),
        child: IntrinsicWidth(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < widget.options.length; i++)
                  _row(widget.options[i], i),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(FileTypeOption o, int i) {
    final selected = o.key == widget.value;
    final start = (i * 0.07).clamp(0.0, 0.6);
    final anim = CurvedAnimation(
      parent: _ctrl,
      curve: Interval(start, (start + 0.4).clamp(0.0, 1.0),
          curve: Curves.easeOut),
    );
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.15),
          end: Offset.zero,
        ).animate(anim),
        child: InkWell(
          onTap: () {
            widget.onChanged(o.key);
            _close();
          },
          child: Container(
            color: selected ? UiColors.primaryTint : null,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(
              children: [
                Icon(
                  o.icon,
                  size: 20,
                  color: selected ? UiColors.primary : UiColors.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    o.label,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? UiColors.primary : UiColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${o.count}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: UiColors.textSecondary,
                  ),
                ),
                SizedBox(
                  width: 22,
                  child: selected
                      ? const Icon(Icons.check_rounded,
                          size: 18, color: UiColors.primary)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _filtered || _open;
    return CompositedTransformTarget(
      link: _link,
      child: GestureDetector(
        onTap: _toggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 44,
          padding: const EdgeInsets.only(left: 14, right: 8),
          decoration: BoxDecoration(
            color: _filtered ? UiColors.primary : UiColors.surface,
            borderRadius: BorderRadius.circular(9999),
            border: Border.all(
              color: active ? UiColors.primary : UiColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _filtered ? Colors.white : UiColors.textPrimary,
                ),
              ),
              const SizedBox(width: 2),
              AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: const Duration(milliseconds: 220),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 22,
                  color: _filtered ? Colors.white : UiColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Category of [d] for the File Type dropdown: PDF, Docs, Sheets, PPT,
/// Images, Videos, Audio or Other. Shared so every screen counts and filters
/// documents the same way.
String fileTypeCategory(Document d) {
  String clean(String v) {
    var e = v.toLowerCase().trim();
    if (e.contains('/')) e = e.split('/').last;
    if (e.contains('.')) e = e.split('.').last;
    return e;
  }

  final byType = clean(d.type);
  final ext = byType.isNotEmpty ? byType : clean(d.name);
  final nameExt = d.name.contains('.')
      ? d.name.toLowerCase().split('.').last
      : '';
  bool inSet(Set<String> set) => set.contains(ext) || set.contains(nameExt);

  if (inSet({'pdf'})) return 'PDF';
  if (inSet({'doc', 'docx', 'txt', 'odt'})) return 'Docs';
  if (inSet({'xls', 'xlsx', 'csv', 'ods'})) return 'Sheets';
  if (inSet({'ppt', 'pptx', 'odp'})) return 'PPT';
  if (inSet({
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'svg', 'image',
  })) {
    return 'Images';
  }
  if (inSet({'mp4', 'm4v', 'mov', 'webm', 'mkv', '3gp', 'avi', 'video'})) {
    return 'Videos';
  }
  if (inSet({'mp3', 'wav', 'aac', 'm4a', 'ogg', 'flac', 'wma', 'audio'})) {
    return 'Audio';
  }
  return 'Other';
}

/// Dropdown options (with counts) for [docs], in the order shown on every
/// screen. "Docs" includes spreadsheets, as in Workspace.
List<FileTypeOption> fileTypeOptionsFor(List<Document> docs) {
  int count(bool Function(String category) test) =>
      docs.where((d) => test(fileTypeCategory(d))).length;
  return [
    FileTypeOption('All', 'ALL', Icons.apps_rounded, docs.length),
    FileTypeOption('PDF', 'PDF', Icons.picture_as_pdf_outlined,
        count((c) => c == 'PDF')),
    FileTypeOption('PPT', 'PPTX', Icons.slideshow_outlined,
        count((c) => c == 'PPT')),
    FileTypeOption('Docs', 'Docs', Icons.description_outlined,
        count((c) => c == 'Docs' || c == 'Sheets')),
    FileTypeOption('Images', 'Images', Icons.image_outlined,
        count((c) => c == 'Images')),
    FileTypeOption('Videos', 'Video', Icons.videocam_outlined,
        count((c) => c == 'Videos')),
    FileTypeOption('Audio', 'Audio', Icons.audiotrack_outlined,
        count((c) => c == 'Audio')),
    FileTypeOption('Other', 'Other', Icons.folder_zip_outlined,
        count((c) => c == 'Other')),
  ];
}

/// True when [d] belongs to the dropdown choice [key] (same rules as
/// Workspace: "Docs" also covers spreadsheets).
bool matchesFileTypeKey(Document d, String key) {
  if (key == 'All') return true;
  final c = fileTypeCategory(d);
  if (key == 'Docs') return c == 'Docs' || c == 'Sheets';
  return c == key;
}
