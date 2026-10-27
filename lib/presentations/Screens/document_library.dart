// ignore_for_file: unused_import, use_build_context_synchronously

import 'dart:io';
import 'dart:convert';
import 'package:digi_sanchika/utils/app_fonts.dart';
import 'package:digi_sanchika/widgets/file_type_icon.dart';
import 'package:digi_sanchika/widgets/favorite_menu.dart';
import 'package:digi_sanchika/widgets/section_panel.dart';
import 'package:flutter/material.dart';
import 'package:digi_sanchika/widgets/dismiss_keyboard.dart';
import 'package:path_provider/path_provider.dart';
import 'package:digi_sanchika/models/document.dart';
import 'package:digi_sanchika/models/folder.dart';
import 'package:digi_sanchika/local_storage.dart';
import 'package:digi_sanchika/services/document_library_service.dart';
import 'package:path/path.dart' as path;
import 'package:digi_sanchika/services/api_service.dart';
import 'package:digi_sanchika/services/document_opener_service.dart';
import 'package:open_filex/open_filex.dart';
import 'package:digi_sanchika/services/my_documents_service.dart';
import 'package:digi_sanchika/widgets/share_access_sheet.dart';
import 'package:digi_sanchika/widgets/version_history_dialog.dart';
import 'package:digi_sanchika/widgets/responsive_page.dart';
import 'package:digi_sanchika/widgets/home_components.dart';
import 'package:digi_sanchika/widgets/ai_sparkle_button.dart';
import 'package:digi_sanchika/widgets/folder_illustration.dart';
import 'package:digi_sanchika/widgets/responsive_document_gallery.dart';
import 'package:digi_sanchika/widgets/layout_capsule.dart';
import 'package:digi_sanchika/models/app_view_mode.dart';
import 'package:digi_sanchika/presentations/Screens/folder_screen.dart';

// Add enum for layout modes (SAME AS SHARED ME)
enum LibraryViewMode { list, grid2x2, grid3x3, compact, detailed }

class DocumentLibrary extends StatefulWidget {
  const DocumentLibrary({super.key});

  @override
  State<DocumentLibrary> createState() => _DocumentLibraryState();
}

class _DocumentLibraryState extends State<DocumentLibrary>
    with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  final DocumentLibraryService _libraryService = DocumentLibraryService();
  final DocumentOpenerService _documentOpener = DocumentOpenerService();

  String _searchQuery = '';

  /// Document ids from the last AI search, in relevance order; null when the
  /// list is filtered by plain text instead.
  List<String>? _aiResultIds;
  bool _aiSearching = false;
  String _selectedFilter = 'All';
  String _selectedCategory = 'All Documents';
  List<Document> _publicDocuments = [];
  List<Document> _filteredDocuments = [];
  List<Folder> _libraryFolders = [];
  List<Folder> _filteredLibraryFolders = [];
  final bool _isDownloading = false;
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';

  // NEW: Layout mode and file type filter variables (SAME AS SHARED ME)
  LibraryViewMode _currentViewMode = LibraryViewMode.list;
  final bool showFileTypeFilter = false;
  String _selectedFileType = 'All';
  List<String> availableFileTypes = ['All'];

  // NEW: Collapsible states for document cards
  final Map<String, bool> _expandedStates = {};

  /// Published folder opened inside the Browse Library panel.
  String? _openFolderId;
  bool _showAllCollections = false;
  /// Browse Library layout, shared by folder and document items.
  ResponsiveDocumentViewMode _browseMode = ResponsiveDocumentViewMode.list;

  static const _collectionAccents = [
    Color(0xFF60A5FA),
    Color(0xFFC084FC),
    Color(0xFF6EE7B7),
    Color(0xFFFDBA74),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPublicDocuments();
  }

  Future<void> _loadPublicDocuments() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = '';
    });

    try {
      // Check internet connection - use ApiService instead
      if (!ApiService.isConnected) {
        // Load from local storage
        _loadFromLocalStorage();
        return;
      }

      // Try to load from backend first
      final documents = await _libraryService.fetchLibraryDocuments();
      final folders = await _libraryService.fetchLibraryFolders();

      if (!mounted) return;

      // Tag documents with their folder name so search matches it too.
      final folderNames = {for (final f in folders) f.id: f.name};
      for (final doc in documents) {
        final name = folderNames[doc.folderId];
        if (name != null) doc.folder = name;
      }

      // Extract unique file types from documents
      final fileTypes = documents
          .map((doc) => doc.type.toUpperCase())
          .toSet()
          .toList();
      fileTypes.sort();

      setState(() {
        _publicDocuments = documents;
        _filteredDocuments = documents;
        _libraryFolders = folders;
        _filteredLibraryFolders = folders;
        availableFileTypes = ['All', ...fileTypes];
        _isLoading = false;
      });

      // Save to local storage for offline access
      await _saveToLocalStorage();
    } catch (e) {
      if (!mounted) return;

      debugPrint('Error loading library documents: $e');

      // Try to load from local storage as fallback
      _loadFromLocalStorage();
    }
  }

  /// Load data from local storage
  Future<void> _loadFromLocalStorage() async {
    try {
      final localDocs = await LocalStorageService.loadDocuments(isPublic: true);

      // Extract file types from local docs too
      final fileTypes = localDocs
          .map((doc) => doc.type.toUpperCase())
          .toSet()
          .toList();
      fileTypes.sort();

      if (mounted) {
        setState(() {
          _publicDocuments = localDocs;
          _filteredDocuments = localDocs;
          _libraryFolders = const [];
          _filteredLibraryFolders = const [];
          availableFileTypes = ['All', ...fileTypes];
          _hasError = true;
          _errorMessage = 'Using cached data. No internet connection.';
          _isLoading = false;
        });
      }
    } catch (localError) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage =
              'Failed to load data. Please check your internet connection.';
          _isLoading = false;
        });
      }
    }
  }

  /// Save data to local storage
  Future<void> _saveToLocalStorage() async {
    if (_publicDocuments.isNotEmpty) {
      try {
        await LocalStorageService.saveDocuments(
          _publicDocuments,
          isPublic: true,
        );
        debugPrint(
          '✅ Saved ${_publicDocuments.length} documents to local storage',
        );
      } catch (e) {
        debugPrint('❌ Error saving to local storage: $e');
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadPublicDocuments();
    }
  }

  /// Filter documents based on search query
  void _filterDocuments(String query) {
    setState(() {
      _searchQuery = query;
      _aiResultIds = null;
      _applyFilters();
    });
  }

  /// AI assistant search over the org library (POST /search/semantic).
  Future<void> _runAiSearch(String query) async {
    setState(() => _aiSearching = true);
    final result = await MyDocumentsService.semanticSearch(
      query: query,
      scope: 'library',
      limit: 50,
    );
    if (!mounted) return;
    final results = result['results'];
    setState(() {
      _aiSearching = false;
      _searchQuery = query;
      _aiResultIds = result['success'] == true && results is List
          ? results.map((r) => r['documentId'].toString()).toList()
          : null;
      _applyFilters();
    });
    if (result['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result['error'] ?? 'AI search failed'}. Showing name matches.',
          ),
        ),
      );
    }
  }

  static const Map<String, List<String>> _categoryKeywords = {
    'HR Policies': [
      'hr',
      'policy',
      'leave',
      'holiday',
      'posh',
      'handbook',
      'employee',
    ],
    'IOTIQ Certificates': [
      'iotiq',
      'certificate',
      'iso',
      'incorporation',
      'trademark',
      'compliance',
      'license',
    ],
    'Infra Projects': [
      'infra',
      'civil',
      'site',
      'drawing',
      'cad',
      'construction',
      'work plan',
      'floor',
    ],
    'Finance Documents': [
      'finance',
      'tax',
      'invoice',
      'audit',
      'salary',
      'payroll',
      'budget',
      'billing',
      'expense',
    ],
    'Software Projects': [
      'software',
      'code',
      'api',
      'architecture',
      'srs',
      'release',
      'developer',
      'sanchika',
      'acs',
    ],
  };

  void _applyFilters() {
    final query = _searchQuery.trim().toLowerCase();
    final categoryTerms = _categoryKeywords[_selectedCategory];

    bool containsAny(String value, List<String>? terms) {
      if (terms == null) return true;
      return terms.any(value.contains);
    }

    bool matchesType(Document doc) {
      final type = doc.type.toUpperCase();
      final selectedType = _selectedFilter.toUpperCase();
      final matchesSelectedType =
          selectedType == 'ALL' ||
          // Folders-only keeps every document so folder counts stay right;
          // the loose document list is hidden in _buildDocumentsTab.
          selectedType == 'FOLDERS' ||
          type == selectedType ||
          (selectedType == 'XLSX' && (type == 'XLS' || type == 'XLSX')) ||
          (selectedType == 'DOCX' && (type == 'DOC' || type == 'DOCX')) ||
          (selectedType == 'IMAGE' &&
              const {
                'PNG',
                'JPG',
                'JPEG',
                'GIF',
                'WEBP',
                'IMAGE',
              }.contains(type));
      if (!matchesSelectedType) {
        return false;
      }
      final selectedFileType = _selectedFileType.toUpperCase();
      return selectedFileType == 'ALL' ||
          type == selectedFileType ||
          (selectedFileType == 'IMAGE' &&
              const {
                'PNG',
                'JPG',
                'JPEG',
                'GIF',
                'WEBP',
                'IMAGE',
              }.contains(type));
    }

    bool matchesSearch(Document doc) {
      if (query.isEmpty) return true;
      final searchable = [
        doc.name,
        doc.keyword,
        doc.type,
        doc.owner,
        doc.folder,
      ].join(' ').toLowerCase();
      return searchable.contains(query);
    }

    final aiIds = _aiResultIds;
    _filteredDocuments = _publicDocuments.where((doc) {
      final searchable = [
        doc.name,
        doc.keyword,
        doc.type,
        doc.owner,
        doc.folder,
      ].join(' ').toLowerCase();
      return containsAny(searchable, categoryTerms) &&
          matchesType(doc) &&
          (aiIds != null ? aiIds.contains(doc.id) : matchesSearch(doc));
    }).toList();
    if (aiIds != null) {
      // Keep the AI relevance order returned by the server.
      _filteredDocuments.sort(
        (a, b) => aiIds.indexOf(a.id).compareTo(aiIds.indexOf(b.id)),
      );
    } else {
      _filteredDocuments.sort((a, b) => b.uploadDate.compareTo(a.uploadDate));
    }

    _filteredLibraryFolders = _libraryFolders.where((folder) {
      return query.isEmpty || folder.name.toLowerCase().contains(query);
    }).toList();
  }

  /// Clear search and reset filter
  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _aiResultIds = null;
      _selectedFileType = 'All';
      _selectedFilter = 'All';
      _selectedCategory = 'All Documents';
      _applyFilters();
    });
  }

  List<Document> get _finalFilteredDocuments {
    return _filteredDocuments;
  }

  // ============ LAYOUT MODES IMPLEMENTATION ============

  /// Method to build layout selector (SAME AS SHARED ME)
  Widget _buildLayoutSelector() {
    return PopupMenuButton<LibraryViewMode>(
      tooltip: 'Change Layout',
      icon: Icon(
        _getViewModeIcon(_currentViewMode),
        color: Colors.indigo,
        size: 24,
      ),
      onSelected: (LibraryViewMode mode) {
        setState(() {
          _currentViewMode = mode;
        });
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<LibraryViewMode>>[
        PopupMenuItem<LibraryViewMode>(
          value: LibraryViewMode.list,
          child: Row(
            children: [
              Icon(Icons.list, color: Colors.indigo),
              SizedBox(width: 8),
              Text('List View'),
              if (_currentViewMode == LibraryViewMode.list)
                Icon(Icons.check, color: Colors.green, size: 16),
            ],
          ),
        ),
        PopupMenuItem<LibraryViewMode>(
          value: LibraryViewMode.grid2x2,
          child: Row(
            children: [
              Icon(Icons.grid_on, color: Colors.indigo),
              SizedBox(width: 8),
              Text('Grid (2x2)'),
              if (_currentViewMode == LibraryViewMode.grid2x2)
                Icon(Icons.check, color: Colors.green, size: 16),
            ],
          ),
        ),
        PopupMenuItem<LibraryViewMode>(
          value: LibraryViewMode.grid3x3,
          child: Row(
            children: [
              Icon(Icons.view_module, color: Colors.indigo),
              SizedBox(width: 8),
              Text('Grid (3x3)'),
              if (_currentViewMode == LibraryViewMode.grid3x3)
                Icon(Icons.check, color: Colors.green, size: 16),
            ],
          ),
        ),
        PopupMenuItem<LibraryViewMode>(
          value: LibraryViewMode.compact,
          child: Row(
            children: [
              Icon(Icons.view_headline, color: Colors.indigo),
              SizedBox(width: 8),
              Text('Compact View'),
              if (_currentViewMode == LibraryViewMode.compact)
                Icon(Icons.check, color: Colors.green, size: 16),
            ],
          ),
        ),
        PopupMenuItem<LibraryViewMode>(
          value: LibraryViewMode.detailed,
          child: Row(
            children: [
              Icon(Icons.table_rows, color: Colors.indigo),
              SizedBox(width: 8),
              Text('Detailed View'),
              if (_currentViewMode == LibraryViewMode.detailed)
                Icon(Icons.check, color: Colors.green, size: 16),
            ],
          ),
        ),
      ],
    );
  }

  IconData _getViewModeIcon(LibraryViewMode mode) {
    switch (mode) {
      case LibraryViewMode.list:
        return Icons.list;
      case LibraryViewMode.grid2x2:
        return Icons.grid_on;
      case LibraryViewMode.grid3x3:
        return Icons.view_module;
      case LibraryViewMode.compact:
        return Icons.view_headline;
      case LibraryViewMode.detailed:
        return Icons.table_rows;
    }
  }

  /// Method to build documents content based on view mode
  Widget _buildDocumentsContent(List<Document> documents) {
    final gallery = ResponsiveDocumentGallery(
      documents: documents,
      mode: _browseMode,
      shrinkWrap: true,
      onView: _handleDocumentDoubleTap,
      onOverflow: (document, anchorContext, isGrid) =>
          _showDocumentActions(document, anchorContext, isGrid),
      onVersions: _showDocumentVersions,
      onDownload: (document) => _showDocumentActions(document),
      onShare: _showShareDialog,
    );

    return gallery;
  }

  // ============ PUBLISHED COLLECTIONS ============

  Map<String, Folder> get _libraryFolderById => {
    for (final f in _libraryFolders) f.id: f,
  };

  /// Library documents grouped by their published folder, newest first.
  /// Follows the current search, category and file-type filters.
  List<_LibraryCollection> get _collections {
    final folders = _libraryFolderById;
    final groups = <String, List<Document>>{};
    for (final doc in _finalFilteredDocuments) {
      final id = doc.folderId;
      if (id == null || !folders.containsKey(id)) continue;
      groups.putIfAbsent(id, () => []).add(doc);
    }
    return [
      for (final e in groups.entries)
        _LibraryCollection(folder: folders[e.key]!, documents: e.value),
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  /// Library documents that don't belong to a published folder.
  List<Document> get _looseDocuments {
    final folders = _libraryFolderById;
    return _finalFilteredDocuments
        .where((d) => d.folderId == null || !folders.containsKey(d.folderId))
        .toList();
  }

  String _collectionDate(DateTime date, {bool withTime = false}) {
    if (date.year <= 1970) return 'N/A';
    final l = date.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final day = '${l.year}-${two(l.month)}-${two(l.day)}';
    return withTime ? '$day ${two(l.hour)}:${two(l.minute)}' : day;
  }

  void _openCollection(String? folderId) {
    setState(() => _openFolderId = folderId);
  }

  Widget _buildDocumentsTab() {
    if (_isLoading) return _buildLoadingState();

    final foldersOnly = _selectedFilter == 'FOLDERS';
    final collections = _collections;
    final loose = foldersOnly ? const <Document>[] : _looseDocuments;
    final openFolder = _openFolderId == null
        ? null
        : _libraryFolderById[_openFolderId];
    final openCollection = openFolder == null
        ? null
        : collections.where((c) => c.folder.id == openFolder.id).firstOrNull;

    if (openFolder == null && collections.isEmpty && loose.isEmpty) {
      if (foldersOnly) {
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.folder_off_outlined,
                size: 64,
                color: Color(0xFF94A3B8),
              ),
              SizedBox(height: 16),
              Text(
                'No published folders',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
        );
      }
      return _buildEmptyState();
    }

    final visibleCollections = _showAllCollections
        ? collections
        : collections.take(4).toList();

    return RefreshIndicator(
      onRefresh: _loadPublicDocuments,
      color: Colors.indigo,
      child: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        children: [
          if (openFolder == null && collections.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildCollectionsHeader(collections.length),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildCollectionsGrid(visibleCollections),
            ),
            const SizedBox(height: 18),
          ],
          SectionPanel(
            // Lines up with the search bar's 16px gutter.
            margin: const EdgeInsets.symmetric(horizontal: 16),
            header: openFolder != null
                ? _buildOpenFolderHeader(
                    openFolder,
                    openCollection?.documents.length ?? 0,
                  )
                : _buildBrowseHeader(collections.length + loose.length),
            child: openFolder != null
                ? (openCollection == null
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              'No matching documents in this folder',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ),
                        )
                      : _buildDocumentsContent(openCollection.documents))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_browseMode == ResponsiveDocumentViewMode.list)
                        for (final c in collections) _buildFolderRow(c)
                      else if (collections.isNotEmpty) ...[
                        _buildFolderGrid(collections),
                        if (loose.isNotEmpty) const SizedBox(height: 12),
                      ],
                      if (loose.isNotEmpty) _buildDocumentsContent(loose),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollectionsHeader(int count) {
    return Row(
      children: [
        const Icon(
          Icons.grid_view_rounded,
          color: Color(0xFF0866E9),
          size: 24,
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Published Collections',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
        ),
        if (count > 4)
          TextButton(
            onPressed: () =>
                setState(() => _showAllCollections = !_showAllCollections),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              foregroundColor: const Color(0xFF0866E9),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _showAllCollections ? 'Show less' : 'View all',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Icon(
                  _showAllCollections
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.chevron_right_rounded,
                  size: 20,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCollectionsGrid(List<_LibraryCollection> collections) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final width = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < collections.length; i++)
              SizedBox(
                width: width,
                child: _buildCollectionCard(
                  collections[i],
                  _collectionAccents[i % _collectionAccents.length],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _collectionMeta(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF94A3B8)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
        ),
      ],
    );
  }

  Widget _buildCollectionCard(_LibraryCollection collection, Color accent) {
    final count = collection.documents.length;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openCollection(collection.folder.id),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE1E7F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 64,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [
                        accent.withValues(alpha: 0.30),
                        accent.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF3FF),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const FolderIllustration(size: 30),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            collection.folder.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF102A56),
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Color(0xFF64748B),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _collectionMeta(
                      Icons.calendar_today_outlined,
                      '$count ${count == 1 ? 'item' : 'items'}',
                    ),
                    const SizedBox(height: 4),
                    _collectionMeta(
                      Icons.schedule_rounded,
                      'Updated · ${_collectionDate(collection.updatedAt)}',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBrowseHeader(int count) {
    return Row(
      children: [
        const Icon(
          Icons.description_outlined,
          color: Color(0xFF0F172A),
          size: 22,
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Browse Library',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
        ),
        _buildBrowseLayoutToggle(),
        const SizedBox(width: 10),
        Text(
          '$count ${count == 1 ? 'item' : 'items'}',
          style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
        ),
      ],
    );
  }

  Widget _buildOpenFolderHeader(Folder folder, int count) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Back to library',
          onPressed: () => _openCollection(null),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A)),
        ),
        Expanded(
          child: Text(
            folder.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
        ),
        _buildBrowseLayoutToggle(),
        const SizedBox(width: 10),
        Text(
          '$count ${count == 1 ? 'file' : 'files'}',
          style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
        ),
      ],
    );
  }

  Widget _buildBrowseLayoutToggle() {
    Widget seg(ResponsiveDocumentViewMode mode, IconData icon, String tip) {
      final active = _browseMode == mode;
      return Tooltip(
        message: tip,
        child: GestureDetector(
          onTap: () => setState(() => _browseMode = mode),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 32,
            height: 30,
            decoration: BoxDecoration(
              color: active ? const Color(0xFF0095E8) : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Icon(
              icon,
              size: 18,
              color: active ? Colors.white : const Color(0xFF526783),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg(ResponsiveDocumentViewMode.list, Icons.view_list_rounded, 'List'),
          seg(ResponsiveDocumentViewMode.grid2, Icons.grid_view_rounded, '2×2 grid'),
          seg(ResponsiveDocumentViewMode.grid3, Icons.apps_rounded, '3×3 grid'),
        ],
      ),
    );
  }

  /// Folder cards for the 2×2 / 3×3 layouts. Same cell geometry as the
  /// document gallery (12px gaps, 4px inset per cell) so folder and document
  /// cards line up column for column.
  Widget _buildFolderGrid(List<_LibraryCollection> collections) {
    final compact = _browseMode == ResponsiveDocumentViewMode.grid3;
    final columns = compact ? 3 : 2;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final c in collections)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: SizedBox(
                  width: width - 8,
                  // 3×3 matches the document gallery's fixed 112px cards.
                  height: compact ? 112 : null,
                  child: _buildFolderGridCard(c, compact: compact),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildFolderGridCard(
    _LibraryCollection collection, {
    required bool compact,
  }) {
    final count = collection.documents.length;
    final items = '$count ${count == 1 ? 'item' : 'items'}';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x96E1E5F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(22),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openCollection(collection.folder.id),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: compact
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: compact ? 28 : 52,
                      height: compact ? 28 : 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF3FF),
                        borderRadius: BorderRadius.circular(compact ? 9 : 16),
                      ),
                      child: FolderIllustration(size: compact ? 20 : 34),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topRight,
                        child: _libraryFolderMenu(
                          collection.folder,
                          compact: true,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 4 : 10),
                Text(
                  collection.folder.name,
                  maxLines: compact ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 13 : 14.5,
                    height: 1.25,
                    fontWeight: compact ? FontWeight.w700 : FontWeight.w600,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                SizedBox(height: compact ? 2 : 4),
                Text(
                  compact
                      ? items
                      : '$items · ${_collectionDate(collection.updatedAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 10 : 12,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFolderRow(_LibraryCollection collection) {
    final count = collection.documents.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _openCollection(collection.folder.id),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE1E7F0)),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF3FF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const FolderIllustration(size: 34),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        collection.folder.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF102A56),
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      _collectionMeta(
                        Icons.calendar_today_outlined,
                        '$count ${count == 1 ? 'item' : 'items'} · '
                        'Updated · '
                        '${_collectionDate(collection.updatedAt, withTime: true)}',
                      ),
                    ],
                  ),
                ),
                _libraryFolderMenu(collection.folder),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFoldersTab() {
    if (_isLoading) return _buildLoadingState();
    if (_filteredLibraryFolders.isEmpty) {
      return const Center(
        child: Text(
          'No folders available',
          style: TextStyle(color: Color(0xFF667085)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      itemCount: _filteredLibraryFolders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final folder = _filteredLibraryFolders[index];
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          elevation: 0,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    FolderScreen(folderId: folder.id, folderName: folder.name),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE1E7F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF3FF),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const FolderIllustration(size: 46),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          folder.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF102A56),
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${folder.documentCount} items • Created ${_formatDateDDMMYYYY(folder.createdAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _libraryFolderMenu(folder),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLibraryFoldersSection() {
    if (_filteredLibraryFolders.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 116,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        scrollDirection: Axis.horizontal,
        itemCount: _filteredLibraryFolders.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final folder = _filteredLibraryFolders[index];
          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    FolderScreen(folderId: folder.id, folderName: folder.name),
              ),
            ),
            child: Container(
              width: 190,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF3FF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const FolderIllustration(size: 34),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      folder.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF102A56),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _libraryFolderMenu(folder),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _libraryFolderMenu(Folder folder, {bool compact = false}) {
    final menu = PopupMenuButton<String>(
      tooltip: 'Folder actions',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      padding: EdgeInsets.zero,
      iconSize: compact ? 18 : null,
      icon: const Icon(Icons.more_vert_rounded, color: Colors.indigo),
      itemBuilder: (_) => const [
        PopupMenuItem<String>(
          value: 'open',
          child: Row(
            children: [
              Icon(Icons.folder_open_outlined, color: Colors.indigo),
              SizedBox(width: 10),
              Text('Open Folder'),
            ],
          ),
        ),
      ],
      onSelected: (value) {
        if (value != 'open') return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                FolderScreen(folderId: folder.id, folderName: folder.name),
          ),
        );
      },
    );
    // Grid cards: a small 28px hit box so the menu fits narrow 3×3 cells.
    return compact ? SizedBox.square(dimension: 28, child: menu) : menu;
  }

  // ============ DOCUMENT CARD BUILDERS ============

  String _getEffectiveFileType(Document document) {
    final nameExt = _extensionFromNameOrPath(document.name);
    if (nameExt != null) return nameExt;

    final pathExt = _extensionFromNameOrPath(document.path);
    if (pathExt != null) return pathExt;

    final t = (document.type.isNotEmpty ? document.type : document.fileType)
        .trim()
        .toLowerCase();
    return t.isEmpty ? 'unknown' : t;
  }

  String? _extensionFromNameOrPath(String value) {
    final v = value.trim();
    final dot = v.lastIndexOf('.');
    if (dot < 0 || dot == v.length - 1) return null;
    final ext = v.substring(dot + 1).trim().toLowerCase();
    if (ext.isEmpty) return null;
    if (!RegExp(r'^[a-z0-9]{1,10}$').hasMatch(ext)) return null;
    return ext;
  }

  String _getDisplayFileType(Document document) {
    final t = _getEffectiveFileType(document);
    if (t == 'jpeg') return 'JPG';
    if (t == 'jiff') return 'JIF';
    return t.toUpperCase();
  }

  /// Get file icon based on type (SAME AS SHARED ME)
  IconData _getFileIcon(String type) {
    switch (type.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'docx':
      case 'doc':
        return Icons.description;
      case 'xlsx':
      case 'xls':
        return Icons.table_chart;
      case 'pptx':
      case 'ppt':
        return Icons.slideshow;
      case 'image':
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image;
      case 'txt':
        return Icons.text_fields;
      case 'csv':
      case 'tsv':
        return Icons.table_chart;
      default:
        return Icons.insert_drive_file;
    }
  }

  /// Get file color based on type (SAME AS SHARED ME)
  Color _getFileColor(String type) {
    switch (type.toLowerCase()) {
      case 'pdf':
        return Colors.red;
      case 'docx':
      case 'doc':
        return Colors.blue;
      case 'xlsx':
      case 'xls':
        return Colors.green;
      case 'pptx':
      case 'ppt':
        return Colors.orange;
      case 'image':
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Colors.purple;
      case 'txt':
        return Colors.grey;
      case 'csv':
      case 'tsv':
        return Colors.green.shade700;
      default:
        return Colors.indigo;
    }
  }

  // Build document item card with COLLAPSIBLE functionality (LIKE SHARED ME)
  Widget _buildDocumentCard(Document document, int index) {
    final effectiveType = _getEffectiveFileType(document);
    final iconData = _getFileIcon(effectiveType);
    final color = _getFileColor(effectiveType);

    // Format the date to DD MM YYYY
    String formattedDate = _formatDateDDMMYYYY(document.uploadDate);

    // Check if this specific document is expanded
    bool isExpanded = _expandedStates[document.id] ?? false;

    return InkWell(
      onTap: () => _handleDocumentDoubleTap(document),
      borderRadius: BorderRadius.circular(12),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        elevation: 0.5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row with icon, document info, and expand/collapse button
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withAlpha(10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: FileTypeIcon.orElse(
                      effectiveType,
                      32,
                      Icon(iconData, color: color, size: 32),
                    ),
                  ),
                  width10,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    document.name,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: isExpanded ? 2 : 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Type: ${_getDisplayFileType(document)} • $formattedDate',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // COLLAPSIBLE EXPAND/COLLAPSE BUTTON
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  // Toggle only this specific document using its ID
                                  _expandedStates[document.id] = !isExpanded;
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: isExpanded
                                      ? color.withAlpha(20)
                                      : Colors.grey.shade100,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isExpanded
                                        ? color.withAlpha(100)
                                        : Colors.transparent,
                                    width: 1.5,
                                  ),
                                ),
                                child: Center(
                                  child: AnimatedRotation(
                                    duration: const Duration(milliseconds: 300),
                                    turns: isExpanded ? 0.5 : 0,
                                    child: Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      size: 22,
                                      color: isExpanded
                                          ? color
                                          : Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Vertical More Options Button
                            IconButton(
                              onPressed: () => _showDocumentActions(document),
                              icon: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.more_vert,
                                    size: 20,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // COLLAPSIBLE CONTENT SECTION
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: SizedBox(
                  height: isExpanded ? null : 0,
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      // Metadata details section
                      if (document.keyword.isNotEmpty)
                        _buildDetailRowWithIcon(
                          'Keyword',
                          document.keyword,
                          Icons.label_important_outline,
                        ),
                      _buildDetailRowWithIcon(
                        'Owner',
                        document.owner,
                        Icons.person_2_outlined,
                      ),
                      _buildDetailRowWithIcon(
                        'Folder',
                        document.folder,
                        Icons.folder_open_outlined,
                      ),
                      _buildDetailRowWithIcon(
                        'Classification',
                        document.classification,
                        Icons.security_outlined,
                      ),
                      if (document.details.isNotEmpty)
                        _buildDetailRowWithIcon(
                          'Details',
                          document.details,
                          Icons.info_outline,
                        ),
                      const SizedBox(height: 16),

                      // ACTION BUTTONS ROW
                      Row(
                        children: [
                          // VIEW BUTTON
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  _handleDocumentDoubleTap(document),
                              icon: const Icon(Icons.visibility, size: 18),
                              label: const Text('View'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.purple,
                                side: const BorderSide(color: Colors.purple),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 8),

                          // VERSIONS BUTTON
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _showDocumentVersions(document),
                              icon: const Icon(Icons.history, size: 18),
                              label: const Text('Versions'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.blue,
                                side: const BorderSide(color: Colors.blue),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
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
            ],
          ),
        ),
      ),
    );
  }

  // Grid view item (SAME AS SHARED ME)
  Widget _buildDocumentGridItem(Document document, int index, int columns) {
    final effectiveType = _getEffectiveFileType(document);
    final iconData = _getFileIcon(effectiveType);
    final color = _getFileColor(effectiveType);

    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _handleDocumentDoubleTap(document),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(columns == 2 ? 12 : 8),
                decoration: BoxDecoration(
                  color: color.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  iconData,
                  color: color,
                  size: columns == 2 ? 26 : 18,
                ),
              ),
              const SizedBox(height: 6),
              Flexible(
                child: Text(
                  document.name,
                  style: TextStyle(
                    fontSize: columns == 2 ? 11 : 9,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: columns == 2 ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _getDisplayFileType(document),
                style: TextStyle(
                  fontSize: columns == 2 ? 9 : 8,
                  color: Colors.grey.shade600,
                ),
              ),
              if (columns == 2) ...[
                const SizedBox(height: 2),
                Text(
                  _formatDateDDMMYYYY(document.uploadDate),
                  style: TextStyle(fontSize: 8, color: Colors.grey.shade500),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Compact view item (SAME AS SHARED ME)
  Widget _buildDocumentCompactItem(Document document, int index) {
    final effectiveType = _getEffectiveFileType(document);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        elevation: 0.5,
        child: InkWell(
          onTap: () => _handleDocumentDoubleTap(document),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey.shade100, width: 1),
            ),
            child: Row(
              children: [
                Icon(
                  _getFileIcon(effectiveType),
                  color: _getFileColor(effectiveType),
                  size: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    document.name,
                    style: const TextStyle(fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatDateDDMMYYYY(document.uploadDate),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Detailed view item (SAME AS SHARED ME)
  Widget _buildDocumentDetailedItem(Document document, int index) {
    final effectiveType = _getEffectiveFileType(document);
    final iconData = _getFileIcon(effectiveType);
    final color = _getFileColor(effectiveType);

    return Card(
      elevation: 0.5,
      margin: const EdgeInsets.only(bottom: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _handleDocumentDoubleTap(document),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withAlpha(20),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: FileTypeIcon.orElse(
                      effectiveType,
                      24,
                      Icon(iconData, color: color, size: 24),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          document.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.person,
                                  size: 12,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    document.owner,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.folder,
                                  size: 12,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    document.folder,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.calendar_today,
                                  size: 12,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _formatDateDDMMYYYY(document.uploadDate),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.security,
                                  size: 12,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  document.classification,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _showDocumentActions(document),
                    icon: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.more_vert,
                        size: 16,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _handleDocumentDoubleTap(document),
                      icon: Icon(
                        Icons.visibility,
                        size: 14,
                        color: Colors.purple,
                      ),
                      label: Text(
                        'View',
                        style: TextStyle(fontSize: 12, color: Colors.purple),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.purple),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showDocumentVersions(document),
                      icon: Icon(Icons.history, size: 14, color: Colors.blue),
                      label: Text(
                        'Versions',
                        style: TextStyle(fontSize: 12, color: Colors.blue),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.blue),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============ ACTION METHODS ============

  /// Handle document double-tap (same as SharedMeScreen)
  void _handleDocumentDoubleTap(Document document) {
    _documentOpener.openPreviewDialog(context: context, document: document);
  }

  Future<void> _showDocumentActions(
    Document document, [
    BuildContext? anchorContext,
    bool isGrid = false,
  ]) async {
    final action = await showMenu<String>(
      context: anchorContext ?? context,
      position: _menuPositionBelow(
        anchorContext ?? context,
        extraOffset: anchorContext == null ? 4 : (isGrid ? 116 : 62),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: [
        const PopupMenuItem(
          value: 'properties',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.info_outline, color: Colors.blue),
            title: Text('Properties'),
          ),
        ),
        const PopupMenuItem(
          value: 'share',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.share, color: Colors.blue),
            title: Text('Share'),
          ),
        ),
        favoriteMenuItem(document.id),
      ],
    );

    if (!mounted) return;
    if (action == 'properties') {
      await _showDocumentDetails(document);
    } else if (action == 'share') {
      _showShareDialog(document);
    } else if (action == favoriteMenuValue) {
      await toggleFavoriteWithFeedback(context, document.id);
    }
  }

  RelativeRect _menuPositionBelow(
    BuildContext anchorContext, {
    double extraOffset = 4,
  }) {
    final button = anchorContext.findRenderObject() as RenderBox;
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
    final rect =
        button.localToGlobal(Offset.zero, ancestor: overlay) & button.size;
    final bottomGap = overlay.size.height - rect.bottom - 4;
    return RelativeRect.fromLTRB(
      rect.left,
      rect.bottom + extraOffset,
      overlay.size.width - rect.right,
      bottomGap < 0 ? 0 : bottomGap,
    );
  }

  // Search by keyword

  Future<void> _showDocumentVersions(Document document) async {
    await VersionHistoryDialog.show(context, document: document);
  }

  /// Show document details.
  Future<void> _showDocumentDetails(Document document) async {
    try {
      final result = await _libraryService.getDocumentDetails(document.id);

      if (result['success'] == true && result['data'] != null) {
        final data = result['data'] as Map<String, dynamic>;
        final effectiveType = _getEffectiveFileType(document);

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  _getFileIcon(effectiveType),
                  size: 24,
                  color: _getFileColor(effectiveType),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(document.name, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDetailRow(
                    'File Name',
                    data['original_filename']?.toString() ?? document.name,
                  ),
                  _buildDetailRow('File Type', _getDisplayFileType(document)),
                  _buildDetailRow(
                    'Size',
                    '${data['file_size']?.toString() ?? '0'} bytes',
                  ),
                  _buildDetailRow(
                    'Owner',
                    data['owner']?['name']?.toString() ?? document.owner,
                  ),
                  _buildDetailRow(
                    'Employee ID',
                    data['owner']?['employee_id']?.toString() ?? 'N/A',
                  ),
                  _buildDetailRow('Upload Date', document.uploadDate),
                  _buildDetailRow(
                    'Folder',
                    data['folder_path']?.toString() ?? document.folder,
                  ),
                  _buildDetailRow(
                    'Classification',
                    data['doc_class']?.toString() ?? document.classification,
                  ),
                  _buildDetailRow(
                    'Keywords',
                    data['keywords']?.toString() ?? document.keyword,
                  ),
                  _buildDetailRow(
                    'Remarks',
                    data['remarks']?.toString() ?? document.details,
                  ),
                  _buildDetailRow(
                    'Public Access',
                    data['is_public']?.toString() == 'true' ? 'Yes' : 'No',
                  ),
                  _buildDetailRow(
                    'Download Allowed',
                    document.allowDownload ? 'Yes' : 'No',
                  ),
                  _buildDetailRow(
                    'Version',
                    data['version_number']?.toString() ?? '1',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              if (!document.isPublishedToLibrary)
                TextButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    final result = await _libraryService.publishDocument(
                      document.id,
                    );

                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          result['success'] == true
                              ? 'Published to library'
                              : (result['message'] ?? 'Publish failed'),
                        ),
                        backgroundColor: result['success'] == true
                            ? Colors.green
                            : Colors.red,
                      ),
                    );
                    setState(() {
                      document.isPublishedToLibrary = result['success'] == true;
                    });
                  },
                  child: const Text('Publish'),
                ),
              if (document.isPublishedToLibrary)
                TextButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    final result = await _libraryService.unpublishDocument(
                      document.id,
                    );

                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          result['success'] == true
                              ? 'Unpublished from library'
                              : (result['message'] ?? 'Unpublish failed'),
                        ),
                        backgroundColor: result['success'] == true
                            ? Colors.green
                            : Colors.red,
                      ),
                    );
                    setState(() {
                      document.isPublishedToLibrary = result['success'] != true;
                    });
                  },
                  child: const Text('Unpublish'),
                ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _showDocumentVersions(document);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history, size: 18),
                    SizedBox(width: 6),
                    Text('Versions'),
                  ],
                ),
              ),
            ],
          ),
        );
      } else {
        throw Exception(result['message'] ?? 'Failed to load details');
      }
    } catch (e) {
      _showSnackBar('Failed to load details: $e', Colors.red);
    }
  }

  Future<void> _showShareDialog(Document document) async {
    if (!ApiService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot share while offline'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    await ShareAccessSheet.showForDocument(
      context: context,
      documentId: document.id,
      documentName: document.name,
    );
  }

  // ============ HELPER METHODS ============

  // Helper method to build detail row
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label: ',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to build detail row WITH icons (for the new design)
  Widget _buildDetailRowWithIcon(
    String label,
    String value,
    IconData iconData,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(iconData, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: w400_13Poppins(color: Colors.grey.shade700),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade800),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // Format date to DD-MM-YYYY - Fixed to handle both YYYY-MM-DD and DD/MM/YYYY formats
  String _formatDateDDMMYYYY(dynamic date) {
    try {
      if (date == null || date.toString().isEmpty) {
        return 'N/A';
      }

      final dateStr = date.toString().trim();

      if (dateStr.contains('T')) {
        final datePart = dateStr.split('T')[0];
        final parts = datePart.split('-');
        if (parts.length == 3) {
          // Convert YYYY-MM-DD to DD/MM/YYYY
          final day = parts[2].padLeft(2, '0');
          final month = parts[1].padLeft(2, '0');
          final year = parts[0];
          return '$day/$month/$year'; // Changed from - to /
        }
      }

      // Check if date is in DD/MM/YYYY format (e.g., "29/10/2025")
      if (dateStr.contains('/')) {
        final parts = dateStr.split('/');
        if (parts.length >= 3) {
          final day = parts[0].padLeft(2, '0');
          final month = parts[1].padLeft(2, '0');
          final year = parts[2];
          return '$day-$month-$year';
        }
      }

      // Check if date is in YYYY-MM-DD format (e.g., "2025-10-29")
      if (dateStr.contains('-')) {
        final parts = dateStr.split('-');
        if (parts.length >= 3) {
          // If first part is 4 digits, assume YYYY-MM-DD format
          if (parts[0].length == 4) {
            final year = parts[0];
            final month = parts[1].padLeft(2, '0');
            final day = parts[2].split(' ')[0].padLeft(2, '0');
            return '$day-$month-$year';
          } else {
            // Assume DD-MM-YYYY format
            final day = parts[0].padLeft(2, '0');
            final month = parts[1].padLeft(2, '0');
            final year = parts[2];
            return '$day-$month-$year';
          }
        }
      }

      // Try to parse as DateTime
      try {
        final dateTime = DateTime.parse(dateStr);
        final day = dateTime.day.toString().padLeft(2, '0');
        final month = dateTime.month.toString().padLeft(2, '0');
        final year = dateTime.year.toString();
        return '$day-$month-$year';
      } catch (e) {
        // If parsing fails, return original string
        return dateStr;
      }
    } catch (e) {
      debugPrint('Error formatting date: $e for input: $date');
      return date.toString();
    }
  }

  /// Build downloading banner widget
  Widget _buildDownloadingBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: Colors.green[50],
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Downloading document...',
              style: TextStyle(
                color: const Color.fromARGB(255, 57, 170, 57),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Show snackbar
  void _showSnackBar(String message, Color backgroundColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.indigo),
          ),
          SizedBox(height: 16),
          Text(
            'Loading library documents...',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final hasCategory = _selectedCategory != 'All Documents';
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasCategory ? Icons.folder_off_outlined : Icons.search_off_rounded,
            size: 64,
            color: const Color(0xFF94A3B8),
          ),
          const SizedBox(height: 16),
          Text(
            hasCategory
                ? 'No files found in $_selectedCategory'
                : 'No documents found',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              hasCategory
                  ? 'There are currently no documents filed under this department.'
                  : (_hasError
                        ? _errorMessage
                        : 'Try another search or file type.'),
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 18),
          if (hasCategory)
            TextButton(
              onPressed: () {
                setState(() {
                  _selectedCategory = 'All Documents';
                  _applyFilters();
                });
              },
              child: const Text('View All Documents'),
            )
          else if (_searchQuery.isNotEmpty)
            TextButton(
              onPressed: _clearSearch,
              child: const Text('Clear Search'),
            ),
          if (_hasError)
            ElevatedButton.icon(
              onPressed: _loadPublicDocuments,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _filterMenuItem(String value, String label) {
    final selected = _selectedFilter == value;
    return PopupMenuItem<String>(
      value: value,
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF0866E9).withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: selected
              ? Border.all(
                  color: const Color(0xFF0866E9).withValues(alpha: 0.22),
                  width: 1,
                )
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: const Color(0xFF102A56),
            fontSize: 14,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  String _filterButtonLabel() {
    switch (_selectedFilter) {
      case 'FOLDERS':
        return 'Folders';
      case 'DOCX':
        return 'Word';
      case 'XLSX':
        return 'Excel';
      case 'IMAGE':
        return 'Images';
      case 'TXT':
        return 'Text';
      case 'All':
        return 'File Type';
      default:
        return _selectedFilter;
    }
  }

  Widget _libraryCategoryChip(String label, {bool selected = false}) {
    return SizedBox(
      height: 42,
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Center(
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () {
              setState(() {
                _selectedCategory = label;
                _applyFilters();
              });
            },
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF0095E8) : Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected
                      ? const Color(0xFF0095E8)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFF526783),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F9FF),
      appBar: AppBar(
        toolbarHeight: 0,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: DismissKeyboard(
        child: ResponsivePage(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: PillSearchField(
                            controller: _searchController,
                            hint: 'Search catalog / policies...',
                            onChanged: _filterDocuments,
                            onClear: _clearSearch,
                            onSubmitted: _filterDocuments,
                            loading: _aiSearching,
                            trailing: AiSparkleButton(
                              onTap: () {
                                final query = _searchController.text.trim();
                                if (query.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Enter a search query first.',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                FocusScope.of(context).unfocus();
                                _runAiSearch(query);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 108,
                          height: 54,
                          child: PopupMenuButton<String>(
                            tooltip: 'Filter documents',
                            padding: EdgeInsets.zero,
                            offset: const Offset(0, 58),
                            elevation: 6,
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(color: Colors.grey.shade200),
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 108,
                              maxWidth: 116,
                            ),
                            onSelected: (value) {
                              setState(() {
                                _selectedFilter = value;
                                _applyFilters();
                              });
                            },
                            itemBuilder: (context) => [
                              _filterMenuItem('All', 'Filter'),
                              _filterMenuItem('FOLDERS', 'Folders'),
                              _filterMenuItem('PDF', 'PDF'),
                              _filterMenuItem('DOCX', 'Word'),
                              _filterMenuItem('XLSX', 'Excel'),
                              _filterMenuItem('PPTX', 'PPT'),
                              _filterMenuItem('IMAGE', 'Images'),
                              _filterMenuItem('TXT', 'Text'),
                            ],
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                color: _selectedFilter == 'All'
                                    ? Colors.white
                                    : const Color(0xFF2196F3),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: Colors.grey.shade300),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      _filterButtonLabel(),
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: _selectedFilter == 'All'
                                            ? Colors.indigo
                                            : Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: _selectedFilter == 'All'
                                        ? Colors.indigo
                                        : Colors.white,
                                    size: 24,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 42,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final category in const [
                      'All Documents',
                      'HR Policies',
                      'IOTIQ Certificates',
                      'Infra Projects',
                      'Finance Documents',
                      'Software Projects',
                    ])
                      _libraryCategoryChip(
                        category,
                        selected: _selectedCategory == category,
                      ),
                  ],
                ),
              ),
              if (_isDownloading) _buildDownloadingBanner(),
              Expanded(child: _buildDocumentsTab()),
            ],
          ),
        ),
      ),
    );
  }
}

/// A published folder in the library and the library documents inside it.
class _LibraryCollection {
  _LibraryCollection({required this.folder, required this.documents})
    : updatedAt = documents
          .map(
            (d) =>
                DateTime.tryParse(d.updatedAt ?? d.uploadDate) ?? DateTime(1970),
          )
          .reduce((a, b) => a.isAfter(b) ? a : b);

  final Folder folder;
  final List<Document> documents;
  final DateTime updatedAt;
}
