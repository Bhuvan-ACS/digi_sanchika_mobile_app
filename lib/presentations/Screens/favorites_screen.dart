import 'package:digi_sanchika/utils/app_fonts.dart';
import 'package:digi_sanchika/presentations/Screens/folder_screen.dart';
import 'package:digi_sanchika/services/favorites_store.dart';
import 'package:digi_sanchika/widgets/file_type_icon.dart';
import 'package:digi_sanchika/widgets/folder_illustration.dart';
import 'package:digi_sanchika/widgets/section_panel.dart';
import 'package:flutter/material.dart';
import 'package:digi_sanchika/services/favorites_service.dart';
import 'package:digi_sanchika/models/favorite_item.dart';
import 'package:digi_sanchika/services/document_library_service.dart';
import 'package:digi_sanchika/local_storage.dart';
import 'package:digi_sanchika/models/document.dart';
import 'package:digi_sanchika/widgets/file_type_dropdown.dart';
import 'package:digi_sanchika/services/document_opener_service.dart';
import 'package:digi_sanchika/services/my_documents_service.dart';
import 'package:digi_sanchika/services/api_service.dart';
import 'package:digi_sanchika/widgets/share_access_sheet.dart';
import 'package:digi_sanchika/models/app_view_mode.dart';
import 'package:digi_sanchika/widgets/layout_capsule.dart';
import 'package:digi_sanchika/widgets/home_components.dart';
import 'package:digi_sanchika/widgets/ai_sparkle_button.dart';
import 'package:digi_sanchika/widgets/responsive_page.dart';

class FavoriteEntry {
  final FavoriteItem favorite;
  final Document document;

  FavoriteEntry({required this.favorite, required this.document});
}

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key, this.embedded = false});

  /// True when shown as a bottom-navigation tab: the host page already
  /// provides the title bar, so this screen skips its own app bar.
  final bool embedded;

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final FavoritesService _service = FavoritesService();
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  List<FavoriteEntry> _documents = [];
  List<FavoriteItem> _folders = [];
  AppViewMode _currentViewMode = AppViewMode.list;
  /// File count and total bytes per folder id, from locally cached documents.
  Map<String, ({int count, double bytes})> _folderDocStats = {};

  @override
  void initState() {
    super.initState();
    FavoritesStore.instance.addListener(_onFavoritesChanged);
    _load();
  }

  /// Keeps this list in step with favourites changed on any other page:
  /// removals disappear straight away, additions trigger a quiet reload.
  void _onFavoritesChanged() {
    if (!mounted || _isLoading) return;
    final store = FavoritesStore.instance;
    final hasNew = !_storeDocsShown(store) || !_storeFoldersShown(store);
    setState(() {
      _documents.removeWhere((e) => !store.isFavorite(e.favorite.entityId));
      _folders.removeWhere((f) => !store.isFavoriteFolder(f.entityId));
    });
    if (hasNew) _load(silent: true);
  }

  bool _storeDocsShown(FavoritesStore store) =>
      store.documentIds.every(
        (id) => _documents.any((e) => e.favorite.entityId == id),
      );

  bool _storeFoldersShown(FavoritesStore store) =>
      store.folderIds.every((id) => _folders.any((f) => f.entityId == id));

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      final items = await _service.listFavorites();
      final folderFavorites =
          items.where((i) => i.entityType.toLowerCase().contains('folder')).toList();
      final docFavorites =
          items
              .where((i) => i.entityType.toLowerCase().contains('doc'))
              .toList();

      final localDocs = await LocalStorageService.loadDocuments();
      final localMap = {for (final doc in localDocs) doc.id: doc};
      final folderStats = <String, ({int count, double bytes})>{};
      for (final doc in localDocs) {
        final id = doc.folderId;
        if (id == null || id.isEmpty) continue;
        final raw = doc.size.replaceAll(RegExp(r'[^0-9.]'), '');
        final prev = folderStats[id] ?? (count: 0, bytes: 0.0);
        folderStats[id] = (
          count: prev.count + 1,
          bytes: prev.bytes + (double.tryParse(raw) ?? 0),
        );
      }

      final List<FavoriteEntry?> entries =
          List<FavoriteEntry?>.filled(docFavorites.length, null);
      final List<Future<void>> fetches = [];

      for (int i = 0; i < docFavorites.length; i++) {
        final fav = docFavorites[i];
        final localDoc = localMap[fav.entityId];
        if (localDoc != null) {
          entries[i] = FavoriteEntry(favorite: fav, document: localDoc);
        } else {
          fetches.add(
            _fetchDocumentForFavorite(fav).then((doc) {
              entries[i] = FavoriteEntry(favorite: fav, document: doc);
            }),
          );
        }
      }

      if (fetches.isNotEmpty) {
        await Future.wait(fetches);
      }

      if (!mounted) return;
      setState(() {
        _folders = folderFavorites;
        _folderDocStats = folderStats;
        _documents = entries.whereType<FavoriteEntry>().toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _folders = [];
        _documents = [];
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load favorites: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    FavoritesStore.instance.removeListener(_onFavoritesChanged);
    _searchController.dispose();
    super.dispose();
  }

  /// Favourite documents after the search and the File Type choice.
  List<FavoriteEntry> get _visibleDocuments {
    final searched = _searchedDocuments;
    if (_docTypeFilter == 'All') return searched;
    return searched
        .where((e) => matchesFileTypeKey(e.document, _docTypeFilter))
        .toList();
  }

  List<FavoriteEntry> get _searchedDocuments {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _documents;
    final aiIds = _aiResultIds;
    if (aiIds != null) {
      return _documents.where((e) => aiIds.contains(e.document.id)).toList()
        ..sort(
          (a, b) => aiIds
              .indexOf(a.document.id)
              .compareTo(aiIds.indexOf(b.document.id)),
        );
    }
    return _documents
        .where((entry) => _displayName(entry).toLowerCase().contains(query))
        .toList();
  }

  List<FavoriteItem> get _visibleFolders {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _folders;
    return _folders
        .where((folder) => (folder.name ?? folder.entityId).toLowerCase().contains(query))
        .toList();
  }

  Future<Document> _fetchDocumentForFavorite(FavoriteItem favorite) async {
    try {
      final preferLibrary = _isLibraryFavorite(favorite.entityType);

      if (preferLibrary) {
        final libResult =
            await DocumentLibraryService().getDocumentDetails(favorite.entityId);
        if (libResult['success'] == true) {
          final details =
              libResult['data'] is Map<String, dynamic>
                  ? libResult['data'] as Map<String, dynamic>
                  : <String, dynamic>{};
          if (details.isNotEmpty) {
            final doc = _documentFromDetails(
              details,
              fallbackName: favorite.name,
              forcePublic: true,
            );
            return doc;
          }
        }
      }

      final result =
          await MyDocumentsService.getDocumentDetails(favorite.entityId);
      if (result['success'] == true) {
        final details =
            result['details'] is Map<String, dynamic>
                ? result['details'] as Map<String, dynamic>
                : <String, dynamic>{};
        if (details.isNotEmpty) {
          return _documentFromDetails(
            details,
            fallbackName: favorite.name,
          );
        }
      }

      if (!preferLibrary) {
        final libResult =
            await DocumentLibraryService().getDocumentDetails(favorite.entityId);
        if (libResult['success'] == true) {
          final details =
              libResult['data'] is Map<String, dynamic>
                  ? libResult['data'] as Map<String, dynamic>
                  : <String, dynamic>{};
          if (details.isNotEmpty) {
            return _documentFromDetails(
              details,
              fallbackName: favorite.name,
              forcePublic: true,
            );
          }
        }
      }
    } catch (_) {}

    final fallbackName =
        (favorite.name != null && favorite.name!.trim().isNotEmpty)
            ? favorite.name!.trim()
            : favorite.entityId;
    final fallbackType = _extractFileType(fallbackName);
    final fallbackIsPublic = _isLibraryFavorite(favorite.entityType);

    return Document(
      id: favorite.entityId,
      name: fallbackName,
      type: fallbackType,
      size: 'Unknown',
      keyword: '',
      uploadDate: DateTime.now().toString(),
      owner: '',
      details: '',
      classification: 'internal',
      allowDownload: true,
      sharingType: fallbackIsPublic ? 'Public' : 'Private',
      folder: 'Home',
      path: fallbackName,
      fileType: fallbackType,
    );
  }

  Document _documentFromDetails(
    Map<String, dynamic> doc, {
    String? fallbackName,
    bool forcePublic = false,
  }) {
    String safeString(dynamic value, {String fallback = ''}) {
      if (value == null) return fallback;
      return value.toString();
    }

    String extractOwnerName(dynamic ownerField) {
      if (ownerField == null) return 'Unknown';
      if (ownerField is Map) {
        return safeString(ownerField['name'], fallback: 'Unknown');
      }
      return safeString(ownerField, fallback: 'Unknown');
    }

    String extractFileName(Map<String, dynamic> docData) {
      return safeString(
        docData['name'] ??
            docData['original_filename'] ??
            docData['original_name'] ??
            docData['file_name'] ??
            docData['fileName'] ??
            docData['filename'],
        fallback: fallbackName ?? 'Unknown',
      );
    }

    final fileName = extractFileName(doc);
    final mimeType = doc['mime_type']?.toString();
    final fileType = mimeType != null && mimeType.isNotEmpty
        ? _extractFileTypeFromMime(mimeType, fileName)
        : _extractFileType(fileName);

    final classification = safeString(
      doc['classification'] ?? doc['doc_class'],
      fallback: 'internal',
    );
    final isPublic =
        forcePublic ||
        doc['is_public'] == true ||
        classification.toLowerCase() == 'public';

    return Document(
      id: safeString(doc['id']),
      name: fileName,
      type: fileType,
      size:
          '${safeString(doc['file_size_bytes'] ?? doc['file_size'], fallback: 'Unknown')} bytes',
      keyword: safeString(doc['keywords']),
      uploadDate: safeString(
        doc['created_at'] ?? doc['updated_at'] ?? doc['upload_date'],
        fallback: DateTime.now().toString(),
      ),
      owner: extractOwnerName(doc['owner']),
      details: safeString(doc['remarks']),
      classification: classification,
      allowDownload: doc['allow_download'] ?? true,
      sharingType: isPublic ? 'Public' : 'Private',
      folder: safeString(doc['folder_path'], fallback: 'Home'),
      folderId: doc['folder_id']?.toString(),
      path: fileName,
      fileType: fileType,
    );
  }

  bool _isLibraryFavorite(String rawType) {
    final value = rawType.toLowerCase();
    return value.contains('library') ||
        value.contains('public') ||
        value.contains('hub');
  }

  String _extractFileType(String filename) {
    if (filename.isEmpty) return 'UNKNOWN';
    final parts = filename.split('.');
    if (parts.length < 2) return 'UNKNOWN';
    final extension = parts.last.toLowerCase();
    final typeMap = {
      'pdf': 'PDF',
      'doc': 'DOC',
      'docx': 'DOCX',
      'xls': 'XLS',
      'xlsx': 'XLSX',
      'ppt': 'PPT',
      'pptx': 'PPTX',
      'txt': 'TXT',
      'csv': 'CSV',
      'jpg': 'JPG',
      'jpeg': 'JPEG',
      'jfif': 'JPG',
      'png': 'PNG',
      'zip': 'ZIP',
      'rar': 'RAR',
    };
    return typeMap[extension] ?? extension.toUpperCase();
  }

  String _extractFileTypeFromMime(String mimeType, String filename) {
    final type = mimeType.toLowerCase();
    if (type.contains('pdf')) return 'PDF';
    if (type.contains('word')) return 'DOCX';
    if (type.contains('sheet') || type.contains('excel')) return 'XLSX';
    if (type.contains('presentation') || type.contains('powerpoint')) {
      return 'PPTX';
    }
    if (type.startsWith('image/')) return 'IMAGE';
    if (type.startsWith('text/')) return 'TXT';
    return _extractFileType(filename);
  }

  String _displayName(FavoriteEntry entry) {
    final name = entry.document.name.trim();
    if (name.isNotEmpty && name.toLowerCase() != 'unknown') return name;
    final fallback = entry.favorite.name?.trim() ?? '';
    if (fallback.isNotEmpty) return fallback;
    return entry.favorite.entityId;
  }

  String _folderName(FavoriteItem folder) =>
      (folder.name?.trim().isNotEmpty ?? false)
          ? folder.name!.trim()
          : folder.entityId;

  // ── Flat design tokens ────────────────────────────────────────────────────
  static const _ink = Color(0xFF0F172A);
  static const _muted = Color(0xFF64748B);
  static const _accent = Color(0xFF2A76BD);
  static const _cardBorder = Color(0xFFF1F5F9);

  static const List<PopupMenuEntry<String>> _favoriteMenuItems = [
    PopupMenuItem(
      value: 'share',
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.share_outlined, color: Colors.blue),
        title: Text('Share'),
      ),
    ),
    PopupMenuItem(
      value: 'remove',
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.star_rounded, color: Colors.amber),
        title: Text('Remove from Favourites'),
      ),
    ),
  ];

  /// Vertical 3-dot menu with Share and Remove from Favourites.
  Widget _menu(Future<void> Function(String action) onSelected) {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      tooltip: 'More actions',
      style: const ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(36, 36)),
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Icon(Icons.more_vert, size: 20, color: _muted),
      itemBuilder: (_) => _favoriteMenuItems,
      onSelected: onSelected,
    );
  }

  bool _ensureOnline(String message) {
    if (ApiService.isConnected) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.orange),
    );
    return false;
  }

  Future<void> _onFolderAction(FavoriteItem folder, String action) async {
    if (action == 'share') {
      if (!_ensureOnline('Cannot share while offline')) return;
      await ShareAccessSheet.showForFolder(
        context: context,
        folderId: folder.entityId,
        folderName: _folderName(folder),
      );
    } else if (action == 'remove') {
      setState(() => _folders.remove(folder));
      final ok = await FavoritesStore.instance.removeFolder(folder.entityId);
      if (!ok && mounted) _load(silent: true);
    }
  }

  Future<void> _onDocumentAction(FavoriteEntry entry, String action) async {
    if (action == 'share') {
      if (!_ensureOnline('Cannot share while offline')) return;
      await ShareAccessSheet.showForDocument(
        context: context,
        documentId: entry.document.id,
        documentName: entry.document.name,
      );
    } else if (action == 'remove') {
      setState(() => _documents.remove(entry));
      final ok = await FavoritesStore.instance.removeDocument(
        entry.favorite.entityId,
      );
      if (!ok && mounted) _load(silent: true);
    }
  }

  void _openFolder(FavoriteItem folder) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FolderScreen(
          folderId: folder.entityId,
          folderName: _folderName(folder),
        ),
      ),
    );
  }

  // ── Subtitles ─────────────────────────────────────────────────────────────
  static String _formatBytes(double bytes) {
    final mb = bytes / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  String _folderSubtitle(FavoriteItem folder) {
    final stats = _folderDocStats[folder.entityId];
    final count = stats?.count ?? 0;
    return '$count ${count == 1 ? 'file' : 'files'} • '
        '${_formatBytes(stats?.bytes ?? 0)}';
  }

  String _documentSubtitle(Document doc) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final parts = <String>[];
    final date = DateTime.tryParse(doc.uploadDate)?.toLocal();
    if (date != null) {
      parts.add(
        '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]} '
        '${date.year}',
      );
    }
    final bytes = double.tryParse(doc.size.replaceAll(RegExp(r'[^0-9.]'), ''));
    if (bytes != null) {
      parts.add(_formatBytes(bytes));
    } else if (doc.size.isNotEmpty && doc.size != 'Unknown') {
      parts.add(doc.size);
    }
    return parts.join(' • ');
  }

  IconData _documentIcon(Document doc) {
    final type = (doc.type.isNotEmpty ? doc.type : doc.fileType).toUpperCase();
    switch (type) {
      case 'PDF':
        return Icons.picture_as_pdf_outlined;
      case 'DOC':
      case 'DOCX':
        return Icons.description_outlined;
      case 'XLS':
      case 'XLSX':
      case 'CSV':
        return Icons.table_chart_outlined;
      case 'PPT':
      case 'PPTX':
        return Icons.slideshow_outlined;
      case 'TXT':
        return Icons.article_outlined;
      case 'ZIP':
      case 'RAR':
        return Icons.folder_zip_outlined;
      case 'JPG':
      case 'JPEG':
      case 'PNG':
      case 'GIF':
      case 'WEBP':
      case 'IMAGE':
        return Icons.image_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  // ── Cards ─────────────────────────────────────────────────────────────────
  Widget _iconBox({required Color background, required Widget child}) {
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }

  Widget _folderIcon() => _iconBox(
    background: const Color(0xFFEBF3FF),
    child: const FolderIllustration(size: 32),
  );

  /// The app's existing coloured file-type icons.
  Widget _documentIconBox(Document doc) {
    final type = doc.type.isNotEmpty ? doc.type : doc.fileType;
    return _iconBox(
      background: const Color(0xFFEFF5FF),
      child: FileTypeIcon.orElse(
        type,
        28,
        Icon(_documentIcon(doc), color: _accent, size: 24),
      ),
    );
  }

  /// Flat card: white, 16px radius, 1px faint border, no shadow.
  Widget _flatCard({required VoidCallback onTap, required Widget child}) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: child),
    );
  }

  Widget _title(String text, {double size = 15}) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(fontSize: size, fontWeight: FontWeight.w600, color: _ink),
  );

  Widget _subtitle(String text, {bool calendar = false, double size = 12.5}) {
    final label = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: size, color: _muted),
    );
    if (!calendar) return label;
    return Row(
      children: [
        Icon(Icons.calendar_today_outlined, size: size, color: _muted),
        const SizedBox(width: 4),
        Expanded(child: label),
      ],
    );
  }

  /// List view row: icon · name over subtitle · 3-dot menu.
  Widget _listCard({
    required Widget leading,
    required String title,
    required Widget subtitle,
    required Widget menu,
    required VoidCallback onTap,
  }) {
    return _flatCard(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [_title(title), const SizedBox(height: 4), subtitle],
              ),
            ),
            menu,
          ],
        ),
      ),
    );
  }

  /// Grid tile: icon and menu on top, name and subtitle underneath.
  Widget _gridCard({
    required Widget leading,
    required String title,
    required Widget subtitle,
    required Widget menu,
    required VoidCallback onTap,
    required bool dense,
  }) {
    return _flatCard(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(dense ? 10 : 12, dense ? 10 : 12, 2, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [leading, const Spacer(), menu],
            ),
            const Spacer(),
            _title(title, size: dense ? 12.5 : 14),
            const SizedBox(height: 3),
            subtitle,
          ],
        ),
      ),
    );
  }

  Widget _buildFolderCard(FavoriteItem folder, {bool? dense}) {
    final menu = _menu((action) => _onFolderAction(folder, action));
    final name = _folderName(folder);
    if (dense == null) {
      return _listCard(
        leading: _folderIcon(),
        title: name,
        subtitle: _subtitle(_folderSubtitle(folder)),
        menu: menu,
        onTap: () => _openFolder(folder),
      );
    }
    return _gridCard(
      leading: _folderIcon(),
      title: name,
      subtitle: _subtitle(_folderSubtitle(folder), size: dense ? 10.5 : 11.5),
      menu: menu,
      onTap: () => _openFolder(folder),
      dense: dense,
    );
  }

  Widget _buildDocumentCard(FavoriteEntry entry, {bool? dense}) {
    final doc = entry.document;
    final menu = _menu((action) => _onDocumentAction(entry, action));
    void open() =>
        DocumentOpenerService().openPreviewDialog(context: context, document: doc);
    if (dense == null) {
      return _listCard(
        leading: _documentIconBox(doc),
        title: _displayName(entry),
        subtitle: _subtitle(_documentSubtitle(doc), calendar: true),
        menu: menu,
        onTap: open,
      );
    }
    return _gridCard(
      leading: _documentIconBox(doc),
      title: _displayName(entry),
      subtitle: _subtitle(
        _documentSubtitle(doc),
        calendar: true,
        size: dense ? 10.5 : 11.5,
      ),
      menu: menu,
      onTap: open,
      dense: dense,
    );
  }

  /// Lays items out as a list (10px apart) or a 2x2 / 3x3 grid.
  Widget _buildItems<T>(
    List<T> items,
    Widget Function(T item, {bool? dense}) builder,
  ) {
    final isGrid = _currentViewMode == AppViewMode.grid2x2 ||
        _currentViewMode == AppViewMode.grid3x3;
    if (!isGrid) {
      return Column(
        children: [
          for (int i = 0; i < items.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
              child: builder(items[i]),
            ),
        ],
      );
    }
    final dense = _currentViewMode == AppViewMode.grid3x3;
    return GridView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: dense ? 3 : 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        mainAxisExtent: dense ? 112 : 124,
      ),
      itemBuilder: (context, index) => builder(items[index], dense: dense),
    );
  }

  // ── Page sections ─────────────────────────────────────────────────────────
  Widget _emptyNote(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Center(child: Text(text, style: const TextStyle(color: _muted))),
  );

  Widget _buildFavoritesContent() {
    final documents = _visibleDocuments;
    final folders = _visibleFolders;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _buildFavoritesSearch(),
        const SizedBox(height: 18),
        SectionPanel(
          margin: EdgeInsets.zero,
          header: _buildSectionHeader(
            'Folders',
            trailing: folders.isEmpty ? null : _moreFilesButton(),
          ),
          child: folders.isEmpty
              ? _emptyNote('No favourite folders yet')
              : _buildItems<FavoriteItem>(folders, _buildFolderCard),
        ),
        const SizedBox(height: 16),
        SectionPanel(
          margin: EdgeInsets.zero,
          header: _buildSectionHeader('Documents', trailing: _fileTypeButton()),
          child: documents.isEmpty
              ? _emptyNote('No favourite documents yet')
              : _buildItems<FavoriteEntry>(documents, _buildDocumentCard),
        ),
      ],
    );
  }

  /// Document ids from the last AI search, in relevance order; null when the
  /// list is filtered by plain text instead.
  List<String>? _aiResultIds;
  bool _aiSearching = false;

  /// File Type dropdown choice ('All', 'PDF', 'PPT', 'Docs', ...).
  String _docTypeFilter = 'All';

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// AI assistant search (POST /search/semantic) over everything I can see,
  /// narrowed to my favourite documents. Folders still match by name.
  Future<void> _handleAiSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      _snack('Enter a search query first.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _aiSearching = true);
    final result = await MyDocumentsService.semanticSearch(
      query: query,
      scope: 'all',
      limit: 50,
    );
    if (!mounted) return;
    final results = result['results'];
    setState(() {
      _aiSearching = false;
      _aiResultIds = result['success'] == true && results is List
          ? results.map((r) => r['documentId'].toString()).toList()
          : null;
    });
    if (result['success'] != true) {
      _snack('${result['error'] ?? 'AI search failed'}. Showing name matches.');
    }
  }

  Widget _buildFavoritesSearch() {
    return Row(
      children: [
        Expanded(
          child: PillSearchField(
            controller: _searchController,
            hint: 'Search favourites...',
            flat: true,
            loading: _aiSearching,
            onChanged: (_) => setState(() => _aiResultIds = null),
            onClear: () {
              _searchController.clear();
              setState(() => _aiResultIds = null);
            },
            onSubmitted: (_) => _handleAiSearch(),
            trailing: AiSparkleButton(onTap: _handleAiSearch),
          ),
        ),
        const SizedBox(width: 10),
        LayoutCapsule(
          value: _currentViewMode,
          activeColor: _accent,
          onChanged: (mode) => setState(() => _currentViewMode = mode),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, {Widget? trailing}) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _ink,
          ),
        ),
        const Spacer(),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _moreFilesButton() {
    return TextButton(
      onPressed: () {},
      style: TextButton.styleFrom(
        foregroundColor: _accent,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'More Files',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          Icon(Icons.chevron_right_rounded, size: 18),
        ],
      ),
    );
  }

  /// Same pill and menu as the Workspace Documents section; counts are for
  /// all favourite documents.
  Widget _fileTypeButton() {
    return FileTypeDropdown(
      value: _docTypeFilter,
      onChanged: (v) => setState(() => _docTypeFilter = v),
      options: fileTypeOptionsFor([for (final e in _documents) e.document]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(onRefresh: _load, child: _buildFavoritesContent());
    if (widget.embedded) {
      return ColoredBox(
        color: const Color(0xFFF4F9FF),
        child: ResponsivePage(padding: EdgeInsets.zero, child: body),
      );
    }
    return Scaffold(
      // Same light blue as My Files and Shared.
      backgroundColor: const Color(0xFFF4F9FF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: const RuledTitle(
          'Favourites',
          style: TextStyle(
            fontFamily: appFontFamily,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _ink,
          ),
        ),
        leadingWidth: 56,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Center(
            child: Material(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.of(context).pop(),
                child: const SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 16,
                    color: _ink,
                  ),
                ),
              ),
            ),
          ),
        ),
        actions: const [SizedBox(width: 56)],
      ),
      body: ResponsivePage(padding: EdgeInsets.zero, child: body),
    );
  }
}
