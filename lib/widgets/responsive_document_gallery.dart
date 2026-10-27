import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:digi_sanchika/models/document.dart';
import 'package:digi_sanchika/services/favorites_store.dart';
import 'package:digi_sanchika/utils/app_theme.dart';
import 'package:digi_sanchika/widgets/file_type_icon.dart';

/// Single accent used by every badge and action in the expanded details.
const _kAccent = Color(0xFF2563EB);

/// The three supported document layouts.  Hosts can map their existing view
/// enums to this type without changing their data or action handling.
enum ResponsiveDocumentViewMode { list, grid2, grid3 }

class ResponsiveDocumentGallery extends StatefulWidget {
  final List<Document> documents;
  final ResponsiveDocumentViewMode mode;
  final ValueChanged<Document> onView;
  final void Function(
    Document document,
    BuildContext anchorContext,
    bool isGrid,
  )
  onOverflow;
  final ValueChanged<Document> onVersions;
  final ValueChanged<Document> onDownload;
  final ValueChanged<Document>? onShare;
  final ValueChanged<Document>? onDelete;
  final bool Function(Document)? canDownload;
  final bool shrinkWrap;

  const ResponsiveDocumentGallery({
    super.key,
    required this.documents,
    required this.mode,
    required this.onView,
    required this.onOverflow,
    required this.onVersions,
    required this.onDownload,
    this.onShare,
    this.onDelete,
    this.canDownload,
    this.shrinkWrap = false,
  });

  @override
  State<ResponsiveDocumentGallery> createState() =>
      _ResponsiveDocumentGalleryState();
}

class _ResponsiveDocumentGalleryState extends State<ResponsiveDocumentGallery> {
  final Set<String> _expanded = <String>{};

  bool get _isGrid => widget.mode != ResponsiveDocumentViewMode.list;

  void _toggle(Document document) {
    setState(() {
      if (_expanded.contains(document.id)) {
        _expanded.clear();
      } else {
        _expanded
          ..clear()
          ..add(document.id);
      }
    });
  }

  Future<void> _showExpandedDialog(Document document) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withAlpha(105),
      builder: (dialogContext) {
        final media = MediaQuery.of(dialogContext).size;
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: media.width * .9,
              maxHeight: media.height * .86,
            ),
            child: SingleChildScrollView(
              child: _ExpandedDocumentCard(
                document: document,
                onClose: () => Navigator.of(dialogContext).pop(),
                onView: () {
                  Navigator.of(dialogContext).pop();
                  widget.onView(document);
                },
                onVersions: () {
                  Navigator.of(dialogContext).pop();
                  widget.onVersions(document);
                },
                onDownload: () {
                  Navigator.of(dialogContext).pop();
                  widget.onDownload(document);
                },
                canDownload: widget.canDownload?.call(document) ?? true,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.documents.isEmpty) return const SizedBox.shrink();
    if (!_isGrid) {
      return ListView.separated(
        shrinkWrap: widget.shrinkWrap,
        physics: widget.shrinkWrap
            ? const NeverScrollableScrollPhysics()
            : const AlwaysScrollableScrollPhysics(),
        // Embedded lists sit inside a panel that already pads its bottom.
        padding: widget.shrinkWrap
            ? EdgeInsets.zero
            : const EdgeInsets.only(bottom: 16),
        itemCount: widget.documents.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final document = widget.documents[index];
          return _DocumentCard(
            document: document,
            expanded: _expanded.contains(document.id),
            grid: false,
            onToggle: () => _toggle(document),
            onView: () => widget.onView(document),
            onOverflow: (anchorContext) =>
                widget.onOverflow(document, anchorContext, false),
            details: _DocumentDetails(
              document: document,
              onView: () => widget.onView(document),
              onVersions: () => widget.onVersions(document),
              onDownload: () => widget.onDownload(document),
              canDownload: widget.canDownload?.call(document) ?? true,
            ),
          );
        },
      );
    }

    final columns = widget.mode == ResponsiveDocumentViewMode.grid3 ? 3 : 2;
    if (columns == 2) {
      // Rows of two. Titles are a single line, so every card has the same
      // content height and both columns stay aligned with no empty space.
      Widget cell(Document document) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: _DocumentCard(
          document: document,
          grid: true,
          gridHeight: null,
          onToggle: () => _showExpandedDialog(document),
          onView: () => widget.onView(document),
          onOverflow: (anchorContext) =>
              widget.onOverflow(document, anchorContext, true),
        ),
      );
      final docs = widget.documents;
      return Column(
        children: [
          for (var i = 0; i < docs.length; i += 2)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cell(docs[i])),
                  const SizedBox(width: 12),
                  Expanded(
                    child: i + 1 < docs.length
                        ? cell(docs[i + 1])
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        // A Wrap is intentional here. GridView gives every item in a row the
        // height of the tallest item, which makes collapsed neighbours look
        // empty when one document is expanded. Each card now owns its height.
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: widget.documents.map((document) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: SizedBox(
                width: width - 8,
                child: _DocumentCard(
                  document: document,
                  grid: true,
                  gridHeight: 112,
                  expanded: false,
                  onToggle: () => _showExpandedDialog(document),
                  onView: () => widget.onView(document),
                  onOverflow: (anchorContext) =>
                      widget.onOverflow(document, anchorContext, true),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _DocumentCard extends StatelessWidget {
  final Document document;
  final bool grid;
  final bool expanded;

  /// Fixed grid height; null lets the card size to its content.
  final double? gridHeight;
  final VoidCallback onToggle;
  final VoidCallback onView;
  final ValueChanged<BuildContext> onOverflow;

  /// List mode only: details revealed below the header when [expanded].
  final Widget? details;

  const _DocumentCard({
    required this.document,
    required this.grid,
    required this.onToggle,
    required this.onView,
    required this.onOverflow,
    this.expanded = false,
    this.gridHeight = 166,
    this.details,
  });

  @override
  Widget build(BuildContext context) {
    final color = _fileColor(document.type);
    if (!grid) return _listCard(color);
    final card = Material(
      color: Colors.white,
      elevation: 0,
      shadowColor: Colors.black.withAlpha(35),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onView,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: gridHeight == null
              ? _gridHeader(color)
              : SizedBox(height: gridHeight! - 24, child: _gridHeader(color)),
        ),
      ),
    );

    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border.withAlpha(150)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(22),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: card,
    );

    return gridHeight != null
        ? SizedBox(height: gridHeight, child: decorated)
        : decorated;
  }

  /// List card: the header stays put and the details slide open beneath it.
  Widget _listCard(Color color) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: expanded
              ? _kAccent.withAlpha(70)
              : AppColors.border.withAlpha(150),
        ),
        boxShadow: [
          BoxShadow(
            color: expanded
                ? _kAccent.withAlpha(28)
                : Colors.black.withAlpha(22),
            blurRadius: expanded ? 20 : 14,
            offset: Offset(0, expanded ? 8 : 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: onView,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _listHeader(color),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: expanded && details != null
                    ? Padding(
                        key: const ValueKey('details'),
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: details,
                      )
                    : const SizedBox(
                        key: ValueKey('collapsed'),
                        width: double.infinity,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _listHeader(Color color) => Row(
    children: [
      _FileIcon(document: document, color: color, size: 52),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Long names loop sideways, like the 2-column grid cards.
            _ScrollingTitle(
              text: document.name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 5),
            _DateSize(document: document),
          ],
        ),
      ),
      _FavoriteBadge(documentId: document.id),
      Builder(
        builder: (buttonContext) =>
            _MenuButton(onPressed: () => onOverflow(buttonContext)),
      ),
      _ChevronButton(expanded: expanded, onPressed: onToggle),
    ],
  );

  Widget _gridHeader(Color color) {
    final big = gridHeight == null || gridHeight! >= 140;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: gridHeight == null ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Row(
          // Menu sits level with the middle of the icon, nudged in from the
          // card edge like the folder card's menu.
          crossAxisAlignment: big
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            _FileIcon(document: document, color: color, size: big ? 52 : 28),
            const SizedBox(width: 4),
            // Narrow 3-column cards can't fit the icon plus all three
            // actions at full size; scale the actions down instead of
            // overflowing the row.
            Expanded(
              child: Align(
                alignment: Alignment.topRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _FavoriteBadge(
                        documentId: document.id,
                        size: big ? 16 : 13,
                      ),
                      Builder(
                        builder: (buttonContext) => _SmallIconButton(
                          icon: Icons.more_vert,
                          onPressed: () => onOverflow(buttonContext),
                        ),
                      ),
                      _SmallIconButton(
                        icon: Icons.keyboard_arrow_down_rounded,
                        onPressed: onToggle,
                      ),
                      if (big) const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: big ? 10 : 4),
        if (big)
          // One line keeps every 2-column card the same height; long names
          // scroll sideways instead of being cut off.
          _ScrollingTitle(
            text: document.name,
            style: const TextStyle(
              fontSize: 14.5,
              height: 1.25,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          )
        else
          Text(
            document.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              height: 1.25,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        if (big) ...[
          const SizedBox(height: 4),
          _GridMeta(document: document),
        ] else ...[
          const SizedBox(height: 2),
          _DateSize(document: document, compact: true),
        ],
      ],
    );
  }
}

/// Single-line title that, when too long for its card, scrolls continuously
/// in one direction as a seamless loop (marquee): a second copy of the text
/// follows the first after a small gap, so the name never bounces back.
class _ScrollingTitle extends StatefulWidget {
  final String text;
  final TextStyle style;
  const _ScrollingTitle({required this.text, required this.style});

  @override
  State<_ScrollingTitle> createState() => _ScrollingTitleState();
}

class _ScrollingTitleState extends State<_ScrollingTitle>
    with SingleTickerProviderStateMixin {
  static const _gap = 32.0;
  static const _speed = 30.0; // logical px per second

  late final AnimationController _controller = AnimationController(vsync: this);
  double _cycle = 0; // text width + gap: one full loop distance

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _sync(double cycle) {
    if (cycle == _cycle) return;
    _cycle = cycle;
    if (cycle <= 0) {
      _controller.stop();
      return;
    }
    _controller
      ..duration = Duration(milliseconds: (cycle / _speed * 1000).round())
      ..repeat();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final textWidth = painter.width;
        final textHeight = painter.height;
        painter.dispose();
        final fits = textWidth <= constraints.maxWidth;
        final cycle = fits ? 0.0 : textWidth + _gap;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _sync(cycle);
        });

        final text = Text(
          widget.text,
          maxLines: 1,
          softWrap: false,
          style: widget.style,
        );
        if (fits) return text;

        return SizedBox(
          height: textHeight,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) => OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: 0,
                maxWidth: double.infinity,
                child: Transform.translate(
                  offset: Offset(-_controller.value * cycle, 0),
                  child: child,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  text,
                  const SizedBox(width: _gap),
                  text,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Two-line metadata for 2-column cards: location, then size · age.
class _GridMeta extends StatelessWidget {
  final Document document;
  const _GridMeta({required this.document});

  static String _size(String raw) {
    final bytes = int.tryParse(raw.replaceAll(RegExp(r'[^0-9]'), ''));
    if (bytes == null || !raw.toLowerCase().contains('byte')) return raw;
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  static String _age(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    final diff = DateTime.now().difference(dt);
    if (diff.inDays >= 7) return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays >= 1) return '${diff.inDays}d ago';
    if (diff.inHours >= 1) return '${diff.inHours}h ago';
    return 'just now';
  }

  @override
  Widget build(BuildContext context) {
    final location = document.folder.isNotEmpty
        ? document.folder
        : document.path;
    final line = [
      if (location.isNotEmpty) location,
      if (document.size.isNotEmpty) _size(document.size),
      if (document.uploadDate.isNotEmpty) _age(document.uploadDate),
    ].join(' · ');
    return Text(
      line,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      ),
    );
  }
}

class _ExpandedDocumentCard extends StatelessWidget {
  final Document document;
  final bool grid;
  final VoidCallback onClose;
  final VoidCallback onView;
  final VoidCallback onVersions;
  final VoidCallback onDownload;
  final bool canDownload;

  const _ExpandedDocumentCard({
    required this.document,
    this.grid = false,
    required this.onClose,
    required this.onView,
    required this.onVersions,
    required this.onDownload,
    required this.canDownload,
  });

  @override
  Widget build(BuildContext context) {
    final color = _fileColor(document.type);
    final dense = grid;
    return Container(
      padding: EdgeInsets.fromLTRB(
        dense ? 8 : 18,
        dense ? 8 : 18,
        dense ? 8 : 18,
        dense ? 8 : 16,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(dense ? 16 : 18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(30),
            blurRadius: dense ? 10 : 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _FileIcon(
                document: document,
                color: color,
                size: dense ? 32 : 50,
              ),
              SizedBox(width: dense ? 6 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.name,
                      maxLines: dense ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: dense ? 11 : 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: dense ? 2 : 5),
                    _DateSize(document: document, compact: dense),
                  ],
                ),
              ),
              dense
                  ? _SmallIconButton(
                      icon: Icons.keyboard_arrow_up_rounded,
                      onPressed: onClose,
                    )
                  : _ChevronButton(expanded: true, onPressed: onClose),
            ],
          ),
          SizedBox(height: dense ? 6 : 14),
          _DocumentDetails(
            document: document,
            dense: dense,
            onView: onView,
            onVersions: onVersions,
            onDownload: onDownload,
            canDownload: canDownload,
          ),
        ],
      ),
    );
  }
}

/// Metadata rows plus View / Versions / Download. Shown inline in an expanded
/// list card and inside the grid's details dialog.
class _DocumentDetails extends StatelessWidget {
  final Document document;
  final bool dense;
  final VoidCallback onView;
  final VoidCallback onVersions;
  final VoidCallback onDownload;
  final bool canDownload;

  const _DocumentDetails({
    required this.document,
    required this.onView,
    required this.onVersions,
    required this.onDownload,
    required this.canDownload,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final path = document.path.isEmpty ? document.folder : document.path;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: dense ? 6 : 12),
          child: const Divider(height: 1),
        ),
        _DetailRow(
          icon: Icons.person_outline_rounded,
          label: 'Owner',
          value: document.owner.isEmpty ? 'Unknown' : document.owner,
          owner: true,
          dense: dense,
        ),
        _DetailRow(
          icon: Icons.folder_outlined,
          label: 'Path',
          value: path.isEmpty ? '/' : path,
          dense: dense,
        ),
        _DetailRow(
          icon: Icons.shield_outlined,
          label: 'Classification',
          value: document.classification.isEmpty
              ? 'Internal'
              : document.classification,
          dense: dense,
        ),
        _DetailRow(
          icon: Icons.share_outlined,
          label: 'Sharing',
          value: document.sharingType.isEmpty
              ? 'Private'
              : document.sharingType,
          dense: dense,
        ),
        Padding(
          padding: EdgeInsets.only(top: dense ? 4 : 8, bottom: dense ? 6 : 12),
          child: const Divider(height: 1),
        ),
        Row(
          children: [
            Expanded(
              child: _GhostButton(
                label: 'View',
                icon: Icons.visibility_outlined,
                tone: _ActionTone.view,
                onPressed: onView,
                compact: dense,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _GhostButton(
                label: 'Versions',
                icon: Icons.history_rounded,
                tone: _ActionTone.versions,
                onPressed: onVersions,
                compact: dense,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _GhostButton(
                label: 'Download',
                icon: Icons.download_rounded,
                tone: _ActionTone.download,
                onPressed: canDownload ? onDownload : null,
                compact: dense,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool owner;
  final bool dense;
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.owner = false,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: dense ? 3 : 5),
    child: Row(
      children: [
        Container(
          width: dense ? 26 : 38,
          height: dense ? 26 : 38,
          decoration: BoxDecoration(
            color: _kAccent.withAlpha(16),
            borderRadius: BorderRadius.circular(dense ? 8 : 11),
          ),
          child: Icon(icon, size: dense ? 15 : 20, color: _kAccent),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: dense ? 46 : 104,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: dense ? 9 : 14,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: owner
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: dense ? 9 : 13,
                        backgroundColor: _kAccent.withAlpha(22),
                        child: Text(
                          value.isEmpty ? '?' : value[0].toUpperCase(),
                          style: TextStyle(
                            fontSize: dense ? 9 : 12,
                            color: _kAccent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      SizedBox(width: dense ? 3 : 7),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: dense ? 56 : 150),
                        child: Text(
                          value,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: dense ? 9 : 14,
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  )
                : Container(
                    constraints: BoxConstraints(maxWidth: dense ? 76 : 190),
                    padding: EdgeInsets.symmetric(
                      horizontal: dense ? 4 : 9,
                      vertical: dense ? 3 : 6,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _kAccent.withAlpha(90)),
                    ),
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: dense ? 8 : 12,
                        color: _kAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    ),
  );
}

/// Colour pair for an action button: [edge] for the border, tint and glow,
/// [ink] — a deeper shade of the same hue — for readable icon and label.
enum _ActionTone {
  view(Color(0xFF4F9BF8), Color(0xFF1F6FE0)), // matches the + button blue
  versions(Color(0xFFF2B33D), Color(0xFFA86A00)),
  download(Color(0xFF34C38F), Color(0xFF138A5B));

  const _ActionTone(this.edge, this.ink);
  final Color edge;
  final Color ink;
}

/// Outlined action in its own colour. At rest: white with a soft tint and a
/// coloured edge. On touch it fills with its colour, glows, presses in and
/// gives a haptic tick — held briefly so a quick tap is still visible.
class _GhostButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final _ActionTone tone;
  final VoidCallback? onPressed;
  final bool compact;
  const _GhostButton({
    required this.label,
    required this.icon,
    required this.tone,
    required this.onPressed,
    this.compact = false,
  });

  @override
  State<_GhostButton> createState() => _GhostButtonState();
}

class _GhostButtonState extends State<_GhostButton> {
  static const _minPress = Duration(milliseconds: 160);

  bool _hovered = false;
  bool _pressed = false;
  DateTime _pressedAt = DateTime.fromMillisecondsSinceEpoch(0);

  void _setPressed(bool value) {
    if (value) {
      _pressedAt = DateTime.now();
      setState(() => _pressed = true);
      return;
    }
    // Keep the pressed look on screen long enough to be seen.
    final remaining = _minPress - DateTime.now().difference(_pressedAt);
    Future.delayed(remaining.isNegative ? Duration.zero : remaining, () {
      if (mounted) setState(() => _pressed = false);
    });
  }

  void _handleTap() {
    HapticFeedback.selectionClick();
    // Let the press animation register before a dialog or page covers it.
    Future.delayed(const Duration(milliseconds: 110), () {
      if (mounted) widget.onPressed?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final compact = widget.compact;
    final edge = widget.tone.edge;
    final fg = enabled ? widget.tone.ink : AppColors.textTertiary;
    final radius = BorderRadius.circular(compact ? 10 : 14);
    final active = enabled && (_pressed || _hovered);

    return AnimatedScale(
      scale: _pressed ? 0.95 : 1,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutBack,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: !enabled
              ? Colors.white
              : _pressed
              ? edge.withAlpha(46)
              : _hovered
              ? edge.withAlpha(26)
              : edge.withAlpha(12),
          borderRadius: radius,
          border: Border.all(
            color: enabled
                ? (active ? edge : edge.withAlpha(150))
                : AppColors.border,
            width: _pressed ? 2 : 1.4,
          ),
          boxShadow: [
            if (active)
              BoxShadow(
                color: edge.withAlpha(_pressed ? 90 : 50),
                blurRadius: _pressed ? 16 : 12,
                offset: Offset(0, _pressed ? 2 : 4),
              ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? _handleTap : null,
            onHover: (v) => setState(() => _hovered = v),
            onHighlightChanged: _setPressed,
            borderRadius: radius,
            splashColor: edge.withAlpha(60),
            highlightColor: Colors.transparent,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 2 : 6,
                vertical: compact ? 6 : 11,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.icon, size: compact ? 14 : 17, color: fg),
                  if (!compact) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: fg,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FileIcon extends StatelessWidget {
  final Document document;
  final Color color;
  final double size;
  const _FileIcon({
    required this.document,
    required this.color,
    required this.size,
  });
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color.withAlpha(10),
      borderRadius: BorderRadius.circular(12),
    ),
    child: FileTypeIcon.orElse(
      document.type,
      size * .7,
      Icon(Icons.insert_drive_file_rounded, size: size * .63, color: color),
    ),
  );
}

class _DateSize extends StatelessWidget {
  final Document document;
  final bool compact;
  const _DateSize({required this.document, this.compact = false});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(
        Icons.calendar_today_outlined,
        size: compact ? 11 : 13,
        color: AppColors.textTertiary,
      ),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          document.uploadDate.isEmpty
              ? document.size
              : '${document.uploadDate}${document.size.isEmpty ? '' : ' • ${document.size}'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compact ? 10 : 12,
            color: AppColors.textTertiary,
          ),
        ),
      ),
    ],
  );
}

class _MenuButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _MenuButton({required this.onPressed});
  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    icon: const Icon(Icons.more_vert),
    visualDensity: VisualDensity.compact,
    color: AppColors.textSecondary,
  );
}

class _ChevronButton extends StatelessWidget {
  final bool expanded;
  final VoidCallback onPressed;
  const _ChevronButton({required this.expanded, required this.onPressed});
  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    tooltip: expanded ? 'Hide details' : 'Show details',
    icon: AnimatedRotation(
      turns: expanded ? 0.5 : 0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: const Icon(Icons.keyboard_arrow_down_rounded),
    ),
    visualDensity: VisualDensity.compact,
    color: expanded ? _kAccent : AppColors.textSecondary,
  );
}

/// Amber star shown only while the document is a favourite. Listens to the
/// shared store, so it appears/disappears on every page at once.
class _FavoriteBadge extends StatelessWidget {
  final String documentId;
  final double size;
  const _FavoriteBadge({required this.documentId, this.size = 18});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: FavoritesStore.instance,
    builder: (context, _) => FavoritesStore.instance.isFavorite(documentId)
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Icon(
              Icons.star_rounded,
              size: size,
              color: Colors.amber,
              semanticLabel: 'Favourite',
            ),
          )
        : const SizedBox.shrink(),
  );
}

class _SmallIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  const _SmallIconButton({required this.icon, required this.onPressed});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onPressed,
    borderRadius: BorderRadius.circular(16),
    child: Padding(
      padding: const EdgeInsets.all(2),
      child: Icon(icon, size: 18, color: AppColors.textSecondary),
    ),
  );
}

Color _fileColor(String type) {
  switch (type.toLowerCase().replaceAll('.', '')) {
    case 'pdf':
      return AppColors.filePdf;
    case 'doc':
    case 'docx':
      return AppColors.fileWord;
    case 'xls':
    case 'xlsx':
      return AppColors.fileExcel;
    case 'ppt':
    case 'pptx':
      return AppColors.filePpt;
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
      return AppColors.fileImage;
    default:
      return AppColors.fileDefault;
  }
}
