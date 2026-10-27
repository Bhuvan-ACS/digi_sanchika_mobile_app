import 'package:digi_sanchika/utils/app_fonts.dart';
import 'package:digi_sanchika/widgets/file_type_icon.dart';
import 'package:flutter/material.dart';
import 'package:digi_sanchika/services/recycle_bin_service.dart';
import 'package:digi_sanchika/models/recycle_bin_item.dart';
import 'package:digi_sanchika/models/app_view_mode.dart';
import 'package:digi_sanchika/widgets/view_mode_popup_button.dart';

class RecycleBinScreen extends StatefulWidget {
  const RecycleBinScreen({super.key});

  @override
  State<RecycleBinScreen> createState() => _RecycleBinScreenState();
}

class _RecycleBinScreenState extends State<RecycleBinScreen> {
  final RecycleBinService _service = RecycleBinService();
  bool _isLoading = true;
  List<RecycleBinItem> _items = [];
  AppViewMode _currentViewMode = AppViewMode.list;
  final Set<String> _busyEntityIds = {};
  final Set<String> _selectedEntityIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final items = await _service.listRecycleBin();
    setState(() {
      _items = items;
      _isLoading = false;
      _selectedEntityIds.clear();
    });
  }

  String _busyKey(RecycleBinItem item) => item.recordId ?? item.entityId;

  bool _isSelected(RecycleBinItem item) =>
      _selectedEntityIds.contains(_busyKey(item));

  void _toggleSelected(RecycleBinItem item) {
    final key = _busyKey(item);
    setState(() {
      if (_selectedEntityIds.contains(key)) {
        _selectedEntityIds.remove(key);
      } else {
        _selectedEntityIds.add(key);
      }
    });
  }

  void _clearSelection() => setState(() => _selectedEntityIds.clear());

  List<RecycleBinItem> _selectedItems() {
    if (_selectedEntityIds.isEmpty) return const [];
    final keys = _selectedEntityIds;
    return _items.where((item) => keys.contains(_busyKey(item))).toList();
  }

  String _inferFileType(RecycleBinItem item) {
    final n = item.name.trim();
    final dot = n.lastIndexOf('.');
    if (dot > 0 && dot < n.length - 1) {
      final ext = n.substring(dot + 1).toLowerCase();
      if (RegExp(r'^[a-z0-9]{1,10}$').hasMatch(ext)) return ext;
    }
    return item.entityType.toLowerCase().contains('folder') ? 'folder' : 'file';
  }

  IconData _getIconForItem(RecycleBinItem item) {
    final t = _inferFileType(item);
    switch (t) {
      case 'folder':
        return Icons.folder_rounded;
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
        return Icons.description_rounded;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Icons.table_chart_rounded;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow_rounded;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'jiff':
        return Icons.image_rounded;
      case 'txt':
        return Icons.text_snippet_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color _getColorForItem(RecycleBinItem item) {
    final t = _inferFileType(item);
    switch (t) {
      case 'folder':
        return Colors.amber.shade800;
      case 'pdf':
        return const Color(0xFFD32F2F);
      case 'doc':
      case 'docx':
        return const Color(0xFF3B5CDB);
      case 'xls':
      case 'xlsx':
        return const Color(0xFF2E7D32);
      case 'csv':
        return const Color(0xFF2E7D32);
      case 'ppt':
      case 'pptx':
        return const Color(0xFFE65100);
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'jiff':
        return const Color(0xFF6A1B9A);
      case 'txt':
        return Colors.grey.shade700;
      default:
        return const Color(0xFF2B41BD);
    }
  }

  /// Short badge label shown in the leading tile, e.g. "PDF", "DOCX", "XLSX".
  String _badgeLabel(RecycleBinItem item) {
    final t = _inferFileType(item);
    if (t == 'folder') return 'DIR';
    if (t == 'file') return 'FILE';
    return t.toUpperCase();
  }

  /// Turns an ISO/free-text deletedAt value into a relative string like
  /// "2 days ago". Falls back to the raw string if it can't be parsed.
  String _deletedAgo(RecycleBinItem item) {
    final deleted = item.deletedAt?.trim();
    if (deleted == null || deleted.isEmpty) return '';
    final dt = DateTime.tryParse(deleted);
    if (dt == null) return deleted;
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Deleted just now';
    if (diff.inMinutes < 60) return 'Deleted ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Deleted ${diff.inHours}h ago';
    if (diff.inDays < 7) {
      final d = diff.inDays;
      return 'Deleted $d day${d == 1 ? '' : 's'} ago';
    }
    if (diff.inDays < 30) {
      final w = (diff.inDays / 7).floor();
      return 'Deleted $w week${w == 1 ? '' : 's'} ago';
    }
    final mo = (diff.inDays / 30).floor();
    return 'Deleted $mo month${mo == 1 ? '' : 's'} ago';
  }

  String _subtitleForItem(RecycleBinItem item) {
    final ago = _deletedAgo(item);
    if (ago.isNotEmpty) return ago;
    final isFolder = item.entityType.toLowerCase().contains('folder');
    return isFolder ? 'Folder' : _inferFileType(item).toUpperCase();
  }

  Future<void> _restore(RecycleBinItem item) async {
    final key = _busyKey(item);
    if (_busyEntityIds.contains(key)) return;
    setState(() => _busyEntityIds.add(key));
    final result = await _service.restoreItemFlexible(
      entityType: item.entityType,
      entityId: item.entityId,
      recordId: item.recordId,
    );
    if (!mounted) return;
    setState(() => _busyEntityIds.remove(key));

    if (result['success'] == true) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Restored "${item.name}"'),
          backgroundColor: Colors.green,
        ),
      );
      return;
    }

    final endpoint = [
      result['method']?.toString(),
      result['path']?.toString(),
    ].where((s) => (s ?? '').trim().isNotEmpty).join(' ');
    final qp = result['queryParameters']?.toString();
    final suffix = endpoint.isEmpty
        ? ''
        : ' ($endpoint${(qp == null || qp.trim().isEmpty) ? '' : ' $qp'})';

    final msg = ((result['message']?.toString() ?? 'Restore failed') + suffix)
        .trim();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg.length > 180 ? '${msg.substring(0, 180)}…' : msg),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _restoreSelected() async {
    final selected = _selectedItems();
    if (selected.isEmpty) return;

    var restored = 0;
    var failed = 0;
    String? firstError;

    setState(() {
      for (final item in selected) {
        _busyEntityIds.add(_busyKey(item));
      }
    });

    for (final item in selected) {
      final result = await _service.restoreItemFlexible(
        entityType: item.entityType,
        entityId: item.entityId,
        recordId: item.recordId,
      );
      if (result['success'] == true) {
        restored++;
      } else {
        failed++;
        firstError ??= () {
          final endpoint = [
            result['method']?.toString(),
            result['path']?.toString(),
          ].where((s) => (s ?? '').trim().isNotEmpty).join(' ');
          final qp = result['queryParameters']?.toString();
          final suffix = endpoint.isEmpty
              ? ''
              : ' ($endpoint${(qp == null || qp.trim().isEmpty) ? '' : ' $qp'})';
          return ((result['message']?.toString() ?? 'Restore failed') + suffix)
              .trim();
        }();
      }
    }

    if (!mounted) return;
    setState(() {
      for (final item in selected) {
        _busyEntityIds.remove(_busyKey(item));
      }
      _selectedEntityIds.clear();
    });

    await _load();
    if (!mounted) return;

    final error = firstError?.trim();
    final msg = failed == 0
        ? 'Restored $restored item(s)'
        : 'Restored $restored item(s), failed $failed'
              '${(error == null || error.isEmpty) ? '' : ' • $error'}';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green));
  }

  Future<void> _deleteForever(RecycleBinItem item) async {
    final key = _busyKey(item);
    if (_busyEntityIds.contains(key)) return;
    setState(() => _busyEntityIds.add(key));
    final result = await _service.deletePermanentlyFlexible(
      entityType: item.entityType,
      entityId: item.entityId,
      recordId: item.recordId,
    );
    if (!mounted) return;
    setState(() => _busyEntityIds.remove(key));

    if (result['success'] == true) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deleted "${item.name}" permanently'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final endpoint = [
      result['method']?.toString(),
      result['path']?.toString(),
    ].where((s) => (s ?? '').trim().isNotEmpty).join(' ');
    final qp = result['queryParameters']?.toString();
    final suffix = endpoint.isEmpty
        ? ''
        : ' ($endpoint${(qp == null || qp.trim().isEmpty) ? '' : ' $qp'})';

    final msg = ((result['message']?.toString() ?? 'Delete failed') + suffix)
        .trim();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg.length > 180 ? '${msg.substring(0, 180)}…' : msg),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _deleteSelectedForever() async {
    final selected = _selectedItems();
    if (selected.isEmpty) return;

    var deleted = 0;
    var failed = 0;
    String? firstError;

    setState(() {
      for (final item in selected) {
        _busyEntityIds.add(_busyKey(item));
      }
    });

    for (final item in selected) {
      final result = await _service.deletePermanentlyFlexible(
        entityType: item.entityType,
        entityId: item.entityId,
        recordId: item.recordId,
      );
      if (result['success'] == true) {
        deleted++;
      } else {
        failed++;
        firstError ??= () {
          final endpoint = [
            result['method']?.toString(),
            result['path']?.toString(),
          ].where((s) => (s ?? '').trim().isNotEmpty).join(' ');
          final qp = result['queryParameters']?.toString();
          final suffix = endpoint.isEmpty
              ? ''
              : ' ($endpoint${(qp == null || qp.trim().isEmpty) ? '' : ' $qp'})';
          return ((result['message']?.toString() ?? 'Delete failed') + suffix)
              .trim();
        }();
      }
    }

    if (!mounted) return;
    setState(() {
      for (final item in selected) {
        _busyEntityIds.remove(_busyKey(item));
      }
      _selectedEntityIds.clear();
    });

    await _load();
    if (!mounted) return;

    final error = firstError?.trim();
    final msg = failed == 0
        ? 'Deleted $deleted item(s) permanently'
        : 'Deleted $deleted item(s), failed $failed'
              '${(error == null || error.isEmpty) ? '' : ' • $error'}';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        titleSpacing: 0,
        title: _selectedEntityIds.isEmpty
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Recycle Bin',
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    'Items are permanently removed after 30 days',
                    style: w400_13Poppins(color: Colors.grey.shade600),
                  ),
                ],
              )
            : Text('${_selectedEntityIds.length} selected'),
        actions: [
          if (_selectedEntityIds.isNotEmpty) ...[
            IconButton(
              tooltip: 'Restore selected',
              icon: const Icon(Icons.restore_rounded,color: Colors.black87),
              onPressed: _restoreSelected,
            ),
            IconButton(
              tooltip: 'Delete selected permanently',
              icon: const Icon(Icons.delete_forever_rounded,color: Colors.black87),
              onPressed: _deleteSelectedForever,
            ),
            IconButton(
              tooltip: 'Clear selection',
              icon: const Icon(Icons.close_rounded,color: Colors.black87),
              onPressed: _clearSelection,
            ),
          ] else ...[
            // ViewModePopupButton(
            //   value: _currentViewMode,
            //   iconColor: Colors.black87,
            //   onSelected: (mode) => setState(() => _currentViewMode = mode),
            // ),
            IconButton(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded,color: Colors.black87),
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? const Center(child: Text('Recycle bin is empty'))
          : RefreshIndicator(
              onRefresh: _load,
              child: Column(
                children: [
                  _buildInfoBanner(),
                  Expanded(child: _buildItemsContent()),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFE0B2)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFFE65100),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Items are permanently removed after 30 days',
              style: TextStyle(
                color: Colors.orange.shade900,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsContent() {
    switch (_currentViewMode) {
      case AppViewMode.list:
      case AppViewMode.detailed:
        return ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          itemCount: _items.length,
          itemBuilder: (context, index) => _buildItemTile(_items[index]),
        );
      case AppViewMode.compact:
        return ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          itemCount: _items.length,
          itemBuilder: (context, index) =>
              _buildItemTile(_items[index], dense: true),
        );
      case AppViewMode.grid2x2:
      case AppViewMode.grid3x3:
        final crossAxisCount = _currentViewMode == AppViewMode.grid3x3 ? 3 : 2;
        final spacing = _currentViewMode == AppViewMode.grid3x3 ? 8.0 : 12.0;
        final aspect = _currentViewMode == AppViewMode.grid3x3 ? 1.05 : 1.15;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: aspect,
          ),
          itemCount: _items.length,
          itemBuilder: (context, index) => _buildItemGrid(_items[index]),
        );
    }
  }

  Widget _buildItemTile(RecycleBinItem item, {bool dense = false}) {
    final isBusy = _busyEntityIds.contains(_busyKey(item));
    final isSelected = _isSelected(item);
    final color = _getColorForItem(item);
    final badge = _badgeLabel(item);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: _selectedEntityIds.isEmpty ? null : () => _toggleSelected(item),
        onLongPress: () => _toggleSelected(item),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: dense ? 12 : 14,
            vertical: dense ? 10 : 14,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: isSelected
                ? Border.all(color: Colors.grey.shade600, width: 2)
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(8),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: dense ? 42 : 48,
                height: dense ? 42 : 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withAlpha(24),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: FileTypeIcon.orElse(
                  _inferFileType(item),
                  dense ? 28 : 32,
                  Text(
                    badge,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: dense ? 10 : 11,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: dense ? 13 : 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitleForItem(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: dense ? 11 : 13,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isBusy)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else ...[
                _circleIconButton(
                  tooltip: 'Restore',
                  icon: Icons.restore_rounded,
                  color: const Color(0xFF4F63FF),
                  onPressed: () => _restore(item),
                ),
                const SizedBox(width: 8),
                _circleIconButton(
                  tooltip: 'Delete permanently',
                  icon: Icons.delete_forever_rounded,
                  color: Colors.red,
                  onPressed: () => _deleteForever(item),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Small rounded, tinted icon button used for Restore / Delete actions,
  /// matching the pill-style buttons in the target design.
  Widget _circleIconButton({
    required String tooltip,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withAlpha(24),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }

  Widget _buildItemGrid(RecycleBinItem item) {
    final isBusy = _busyEntityIds.contains(_busyKey(item));
    final isSelected = _isSelected(item);
    final color = _getColorForItem(item);
    final badge = _badgeLabel(item);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: _selectedEntityIds.isEmpty ? null : () => _toggleSelected(item),
      onLongPress: () => _toggleSelected(item),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: isSelected
              ? Border.all(color: Colors.grey.shade600, width: 2)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withAlpha(24),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: FileTypeIcon.orElse(
                  _inferFileType(item),
                  30,
                  Text(
                    badge,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _subtitleForItem(item),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (isBusy)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else ...[
                    _circleIconButton(
                      tooltip: 'Restore',
                      icon: Icons.restore_rounded,
                      color: const Color(0xFF4F63FF),
                      onPressed: () => _restore(item),
                    ),
                    const SizedBox(width: 8),
                    _circleIconButton(
                      tooltip: 'Delete permanently',
                      icon: Icons.delete_forever_rounded,
                      color: Colors.red,
                      onPressed: () => _deleteForever(item),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}