// ignore_for_file: unused_import, use_build_context_synchronously

import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:digi_sanchika/widgets/dismiss_keyboard.dart';
import 'package:path_provider/path_provider.dart';
import 'package:digi_sanchika/models/document.dart';
import 'package:digi_sanchika/local_storage.dart';
import 'package:digi_sanchika/services/document_library_service.dart';
import 'package:path/path.dart' as path;
import 'package:digi_sanchika/services/api_service.dart';
import 'package:digi_sanchika/services/document_opener_service.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:digi_sanchika/services/my_documents_service.dart';
import 'package:digi_sanchika/widgets/share_access_sheet.dart';
import 'package:digi_sanchika/widgets/version_history_dialog.dart';
import 'package:digi_sanchika/widgets/responsive_page.dart';

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
  String _selectedFilter = 'All';
  List<Document> _publicDocuments = [];
  List<Document> _filteredDocuments = [];
  bool _isDownloading = false;
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';

  // NEW: Layout mode and file type filter variables (SAME AS SHARED ME)
  LibraryViewMode _currentViewMode = LibraryViewMode.list;
  bool _showFileTypeFilter = false;
  String _selectedFileType = 'All';
  List<String> _availableFileTypes = ['All'];

  // NEW: Collapsible states for document cards
  Map<String, bool> _expandedStates = {};

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

      if (!mounted) return;

      // Extract unique file types from documents
      final fileTypes = documents
          .map((doc) => doc.type.toUpperCase())
          .toSet()
          .toList();
      fileTypes.sort();

      setState(() {
        _publicDocuments = documents;
        _filteredDocuments = documents;
        _availableFileTypes = ['All', ...fileTypes];
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
          _availableFileTypes = ['All', ...fileTypes];
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

  void _refreshDocuments() {
    _loadPublicDocuments();
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
    if (query.isEmpty) {
      setState(() {
        _filteredDocuments = _publicDocuments;
        _searchQuery = query;
      });
      return;
    }

    final lowercaseQuery = query.toLowerCase();
    setState(() {
      _searchQuery = query;
      _filteredDocuments = _publicDocuments.where((doc) {
        return doc.name.toLowerCase().contains(lowercaseQuery) ||
            (doc.keyword.isNotEmpty &&
                doc.keyword.toLowerCase().contains(lowercaseQuery)) ||
            doc.type.toLowerCase().contains(lowercaseQuery) ||
            (doc.owner.isNotEmpty &&
                doc.owner.toLowerCase().contains(lowercaseQuery)) ||
            (doc.folder.isNotEmpty &&
                doc.folder.toLowerCase().contains(lowercaseQuery));
      }).toList();
    });
  }

  /// Clear search and reset filter
  void _clearSearch() {
    _searchController.clear();
    _filterDocuments('');
    _selectedFileType = 'All';
    _selectedFilter = 'All';
  }

  List<Document> get _finalFilteredDocuments {
    List<Document> filtered = _filteredDocuments.where((doc) {
      final docType = doc.type.toUpperCase();
      bool isExcelFile = docType == 'XLS' || docType == 'XLSX';

      bool matchesFilter;
      if (_selectedFilter == 'All') {
        matchesFilter = true;
      } else if (_selectedFilter == 'XLSX' && isExcelFile) {
        matchesFilter = true;
      } else {
        matchesFilter = doc.type.toLowerCase().contains(
          _selectedFilter.toLowerCase(),
        );
      }
      return matchesFilter;
    }).toList();

    // Apply file type filter
    if (_selectedFileType != 'All') {
      filtered = filtered.where((doc) {
        return doc.type.toUpperCase() == _selectedFileType;
      }).toList();
    }

    // Sort by upload date (newest first)
    filtered.sort((a, b) => b.uploadDate.compareTo(a.uploadDate));
    return filtered;
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
    switch (_currentViewMode) {
      case LibraryViewMode.list:
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 20),
          itemCount: documents.length,
          itemBuilder: (context, index) {
            return _buildDocumentCard(documents[index], index);
          },
        );
      case LibraryViewMode.grid2x2:
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.9,
          ),
          itemCount: documents.length,
          itemBuilder: (context, index) {
            return _buildDocumentGridItem(documents[index], index, 2);
          },
        );
      case LibraryViewMode.grid3x3:
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 0.85,
          ),
          itemCount: documents.length,
          itemBuilder: (context, index) {
            return _buildDocumentGridItem(documents[index], index, 3);
          },
        );
      case LibraryViewMode.compact:
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: documents.length,
          itemBuilder: (context, index) {
            return _buildDocumentCompactItem(documents[index], index);
          },
        );
      case LibraryViewMode.detailed:
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: documents.length,
          itemBuilder: (context, index) {
            return _buildDocumentDetailedItem(documents[index], index);
          },
        );
    }
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
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        elevation: 2,
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
                    child: Icon(iconData, color: color, size: 32),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                document.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: isExpanded ? 2 : 1,
                                overflow: TextOverflow.ellipsis,
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
                              onPressed: () =>
                                  _showDocumentActions(document),
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
                          Icons.label,
                        ),
                      _buildDetailRowWithIcon(
                        'Owner',
                        document.owner,
                        Icons.person,
                      ),
                      _buildDetailRowWithIcon(
                        'Folder',
                        document.folder,
                        Icons.folder,
                      ),
                      _buildDetailRowWithIcon(
                        'Classification',
                        document.classification,
                        Icons.security,
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
      elevation: 2,
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
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 8),
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
                    child: Icon(iconData, color: color, size: 24),
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
                    onPressed: () =>
                        _showDocumentActions(document),
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

  void _showDocumentActions(Document document) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.visibility, color: Colors.purple),
                title: const Text('View'),
                onTap: () {
                  Navigator.pop(context);
                  _documentOpener.openPreviewDialog(
                    context: context,
                    document: document,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline, color: Colors.blue),
                title: const Text('Properties'),
                onTap: () {
                  Navigator.pop(context);
                  _showDocumentDetails(document);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share, color: Colors.blue),
                title: const Text('Share'),
                onTap: () {
                  Navigator.pop(context);
                  _showShareDialog(document);
                },
              ),
              ListTile(
                leading: const Icon(Icons.history, color: Colors.blueGrey),
                title: const Text('Version History'),
                onTap: () {
                  Navigator.pop(context);
                  _showDocumentVersions(document);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // Search by keyword
  void _searchByKeyword(String keyword) {
    _searchController.text = keyword;
    _filterDocuments(keyword);
  }

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
                      backgroundColor:
                          result['success'] == true ? Colors.green : Colors.red,
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
                      backgroundColor:
                          result['success'] == true ? Colors.green : Colors.red,
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
          Icon(iconData, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _searchController.text.isEmpty
                ? Icons.folder_open
                : Icons.search_off,
            size: 80,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 20),
          Text(
            _searchController.text.isEmpty
                ? 'Document Library Empty'
                : 'No Documents Found',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              _hasError
                  ? _errorMessage
                  : _searchController.text.isEmpty
                  ? 'No public documents available in the library yet'
                  : 'No documents found for "${_searchController.text}"',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 20),
          if (_searchController.text.isNotEmpty)
            ElevatedButton.icon(
              onPressed: _clearSearch,
              icon: const Icon(Icons.clear_all),
              label: const Text('Clear Search'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Document Library',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.indigo,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: Colors.indigo,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: DismissKeyboard(
        child: ResponsivePage(
          padding: EdgeInsets.zero,
          child: Column(
          children: [
            // Search and filter section
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey.shade50,
              child: Column(
                children: [
                // Search and Filter Row
                Row(
                  children: [
                    // Search Bar
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withAlpha(10),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _searchController,
                          onChanged: _filterDocuments,
                          maxLines: 1,
                          decoration: InputDecoration(
                            hintText: 'Search library documents...',
                            hintStyle: TextStyle(color: Colors.grey.shade600),
                            prefixIcon: const Icon(
                              Icons.search,
                              color: Colors.indigo,
                            ),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    color: Colors.grey,
                                    onPressed: _clearSearch,
                                  )
                                : null,
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 14,
                              horizontal: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Layout Selector
                    _buildLayoutSelector(),
                    const SizedBox(width: 12),
                    // Filter Dropdown
                    Container(
                      constraints: const BoxConstraints(maxWidth: 120),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withAlpha(10),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: DropdownButton<String>(
                          value: _selectedFilter,
                          underline: const SizedBox(),
                          icon: const Icon(
                            Icons.filter_list,
                            color: Colors.indigo,
                          ),
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(
                              value: 'All',
                              child: Text('Filter'),
                            ),
                            DropdownMenuItem(value: 'PDF', child: Text('PDF')),
                            DropdownMenuItem(
                              value: 'DOCX',
                              child: Text('Word'),
                            ),
                            DropdownMenuItem(
                              value: 'XLSX',
                              child: Text('Excel'),
                            ),
                            DropdownMenuItem(value: 'PPTX', child: Text('PPT')),
                            DropdownMenuItem(
                              value: 'IMAGE',
                              child: Text('Images'),
                            ),
                            DropdownMenuItem(value: 'TXT', child: Text('Text')),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedFilter = value!;
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Stats row with filter badges
                Row(
                  children: [
                    Text(
                      '${_finalFilteredDocuments.length} document${_finalFilteredDocuments.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    if (_searchQuery.isNotEmpty || _selectedFilter != 'All')
                      TextButton(
                        onPressed: _clearSearch,
                        child: Text(
                          'Clear',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.indigo,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Filter Info Banner (when active)
          if (_searchQuery.isNotEmpty || _selectedFilter != 'All')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.blue.shade50,
              child: Row(
                children: [
                  Icon(Icons.info, size: 16, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _buildFilterText(),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Loading/Downloading Banner
          if (_isDownloading) _buildDownloadingBanner(),

          // Main Content Area
          Expanded(
            child: _isLoading
                ? _buildLoadingState()
                : _finalFilteredDocuments.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
                    onRefresh: _loadPublicDocuments,
                    color: Colors.indigo,
                    child: _buildDocumentsContent(_finalFilteredDocuments),
                  ),
          ),
        ],
          ),
        ),
      ),
    );
  }

  String _buildFilterText() {
    String text =
        'Showing ${_finalFilteredDocuments.length} of ${_publicDocuments.length} documents';

    if (_searchQuery.isNotEmpty && _selectedFilter != 'All') {
      text += ' for "$_searchQuery" in $_selectedFilter';
    } else if (_searchQuery.isNotEmpty) {
      text += ' for "$_searchQuery"';
    } else if (_selectedFilter != 'All') {
      text += ' in $_selectedFilter';
    }

    return text;
  }
}








