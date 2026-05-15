// ignore_for_file: use_build_context_synchronously, unnecessary_this
import 'package:digi_sanchika/local_storage.dart';
import 'package:digi_sanchika/utils/responsive_helper.dart';
import 'package:digi_sanchika/utils/design_tokens.dart';
import 'package:digi_sanchika/services/upload_service.dart';
import 'package:digi_sanchika/services/folder_helper.dart';
import 'package:digi_sanchika/services/folder_operations_service.dart';
import 'package:digi_sanchika/models/folder_tree_node.dart';
import 'package:digi_sanchika/services/folder_tree_service.dart'; // ADD THIS
import 'package:digi_sanchika/presentations/screens/folder_manager_screen.dart'; // ADD THIS
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:digi_sanchika/widgets/dismiss_keyboard.dart';
import 'package:file_picker/file_picker.dart';
import 'package:digi_sanchika/models/document.dart';
import 'package:digi_sanchika/models/folder.dart';
import 'package:digi_sanchika/services/document_library_service.dart';
import 'package:digi_sanchika/services/shares_service.dart';
import 'dart:io';
import 'package:digi_sanchika/widgets/upload_result_dialog.dart';

class UploadDocumentTab extends StatefulWidget {
  final Function(Document) onDocumentUploaded;
  final List<Folder> folders;
  final String? userName;

  const UploadDocumentTab({
    super.key,
    required this.onDocumentUploaded,
    required this.folders,
    this.userName,
  });

  @override
  State<UploadDocumentTab> createState() => _UploadDocumentTabState();
}

class _UploadDocumentTabState extends State<UploadDocumentTab> {
  // ============ STATE VARIABLES ============
  final TextEditingController _keywordsController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();

  String _selectedFolder = '';
  String _selectedClassification = 'General';
  bool _allowDownload = true;
  String _selectedSharingType = 'Public';
  final List<PlatformFile> _uploadedFiles = [];
  bool _isLoading = false;
  final bool _isConnected = true;

  // Share with specific users (upload-time)
  final SharesService _sharesService = SharesService();
  final DocumentLibraryService _libraryService = DocumentLibraryService();
  bool _shareWithSpecificUsers = false;
  bool _shareUsersLoading = false;
  List<Map<String, dynamic>> _shareUsers = [];
  final Set<String> _specificUserIds = <String>{};

  // Folder management variables
  bool _foldersLoading = false;

  // New folder tree variables
  List<FolderTreeNode> _folderTree = []; // For tree structure
  String? _selectedFolderName; // For display
  String? _selectedFolderId; // For upload (UUID string)

  // ============ CONSTANTS ============
  static const List<String> _allSupportedExtensions = [
    // Legacy Office
    'doc', 'xls', 'ppt', 'rtf', 'mdb', 'pub', 'pps', 'dot', 'xlt', 'pot',
    // Modern Office
    'docx', 'xlsx', 'pptx', 'dotx', 'xltx', 'potx', 'accdb', 'one',
    // OpenDocument Format
    'odt', 'ods', 'odp', 'odg', 'odf',
    // Apple iWork
    'pages', 'numbers', 'key',
    // PDFs
    'pdf',
    // Text Files
    'txt', 'md', 'markdown',
    // CSV/Data Files
    'csv', 'tsv', 'xml', 'json',
    // ZIP & Archives
    'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'iso',
    // Audio Files
    'mp3',
    'wav',
    'ogg',
    'flac',
    'aac',
    'm4a',
    'wma',
    'opus',
    'mid',
    'midi',
    'aiff',
    'au',
    // Video Files
    'mp4',
    'mov',
    'avi',
    'mkv',
    'flv',
    'wmv',
    'webm',
    'm4v',
    'mpg',
    'mpeg',
    '3gp',
    'mts',
    'vob',
    'ogv',
    // Image Files
    'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg', 'tiff', 'tif', 'jfif',
    // Code Files - Python
    'py', 'pyc', 'pyo', 'pyd',
    // JavaScript/TypeScript/React/Node.js
    'js', 'jsx', 'ts', 'tsx', 'node', 'njs',
    // HTML/CSS
    'html', 'htm', 'css', 'scss', 'sass', 'less',
    // Database
    'sql', 'db', 'sqlite', 'sqlite3', 'mdb', 'accdb', 'frm', 'myd', 'myi',
    // Other programming languages
    'java', 'class', 'jar', 'c', 'cpp', 'cc', 'cxx', 'h', 'hpp', 'hxx',
    'cs', 'php', 'phtml', 'rb', 'erb', 'go', 'rs', 'swift', 'kt', 'kts', 'dart',
    // Shell/Bash
    'sh', 'bash', 'zsh', 'fish', 'ps1', 'bat', 'cmd',
    // Configuration Files
    'env', 'config', 'toml', 'ini', 'yaml', 'yml',
    // JSON Files
    'json', 'jsonl', 'jsonc',
    // Google Files
    'gdoc', 'gsheet', 'gslides', 'gdraw',
    // Other Important
    'log', 'lock', 'license', 'readme', 'gitignore', 'dockerfile', 'makefile',
  ];

  @override
  void dispose() {
    _keywordsController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  // ============ HELPER METHODS (DECLARE THESE FIRST) ============
  String _getFileSizeString(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  String _mapClassificationForApi(String value) {
    switch (value.trim().toLowerCase()) {
      case 'general':
        // "public" classification is interpreted as public-facing by some backends.
        // Default "General" uploads should remain non-public unless explicitly published.
        return 'internal';
      case 'unclassified':
        return 'internal';
      case 'internal use only':
        return 'internal';
      case 'corporate confidential':
        return 'confidential';
      case 'restricted':
        return 'restricted';
      case 'confidential':
        return 'confidential';
      case 'secret':
        return 'secret';
      default:
        return "internal";
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _resolveUploadedDocumentId(
    Map<String, dynamic> uploadResult,
    int index,
  ) {
    final uploadedItems = uploadResult['uploaded_items'];
    if (uploadedItems is List && uploadedItems.length > index) {
      final item = uploadedItems[index];
      if (item is Map<String, dynamic>) {
        final id = item['document_id'] ?? item['documentId'] ?? item['id'];
        if (id != null && id.toString().isNotEmpty) {
          return id.toString();
        }
      }
    }

    if (_uploadedFiles.length == 1) {
      final id =
          uploadResult['document_id'] ??
          uploadResult['documentId'] ??
          uploadResult['id'];
      if (id != null && id.toString().isNotEmpty) {
        return id.toString();
      }
    }

    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  Document _buildUploadedDocument({
    required PlatformFile platformFile,
    required String currentUser,
    required DateTime now,
    required String documentId,
  }) {
    final fileName = platformFile.name;
    final fileExtension = fileName.contains('.')
        ? fileName.split('.').last
        : '';

    return Document(
      id: documentId,
      name: fileName,
      type: fileExtension.isNotEmpty ? fileExtension.toUpperCase() : 'FILE',
      size: _getFileSizeString(platformFile.size),
      keyword: _keywordsController.text.trim(),
      uploadDate: now.toIso8601String(),
      owner: currentUser,
      details: _remarksController.text.trim(),
      classification: _selectedClassification,
      allowDownload: _allowDownload,
      sharingType: _selectedSharingType,
      folder: _selectedFolderName?.trim().isNotEmpty == true
          ? _selectedFolderName!.trim()
          : 'Home',
      folderId: _selectedFolderId?.toString(),
      path: fileName,
      fileType: fileExtension.isNotEmpty
          ? fileExtension.toLowerCase()
          : 'unknown',
    );
  }

  // ============ FOLDER MANAGEMENT METHODS ============
  Future<void> _loadFolders() async {
    if (mounted) {
      setState(() => _foldersLoading = true);
    }

    try {
      final folderService = FolderTreeService();
      final folders = await folderService.fetchFolderTree(forceRefresh: true);

      if (mounted) {
        setState(() {
          _folderTree = folders;
          _foldersLoading = false;

          // Initialize with ALL folders COLLAPSED by default
          _expandedFolders = {};

          // Set default folder to "Root" first
          _selectedFolder = ''; // Root
          _selectedFolderName = null;
          _selectedFolderId = null;
        });
      }

      if (kDebugMode) {
        print(
          '✅ Loaded ${folders.length} root folders (all collapsed by default)',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _foldersLoading = false);
      }
      if (kDebugMode) {
        print('❌ Error loading folders: $e');
      }
      _showErrorSnackBar('Failed to load folders: $e');
    }
  }

  // Method to navigate to folder manager
  Future<void> _navigateToFolderManager(BuildContext context) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FolderManagerScreen(userName: widget.userName),
      ),
    );

    // When returning from FolderManagerScreen, refresh the folder list
    if (mounted && result == true) {
      await _loadFolders();
    }
  }

  // NEW STATE VARIABLES FOR MODAL (add these to your state class)
  List<FolderTreeNode> _filteredFolders = [];
  Map<String, bool> _expandedFolders = {}; // Tracks which folders are expanded
  final Map<String, bool> _loadingFolderChildren =
      {}; // Lazy-load child folders
  String _searchQuery = '';

  // NEW METHOD: Show folder selector in a modal bottom sheet
  Future<void> _showFolderSelector(BuildContext context) async {
    // Reset search and expanded state
    _searchQuery = '';
    _expandedFolders = {};
    _filteredFolders = List.from(_folderTree);

    // Initialize with all top-level folders expanded
    for (final folder in _folderTree) {
      _expandedFolders[folder.id] = true;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final r = ResponsiveHelper.of(context);
        return StatefulBuilder(
          builder: (context, setModalState) {
            final selectedLabel = _destinationLabel();
            final isRootSelected = _selectedFolderId == null;
            final inSearch = _searchQuery.isNotEmpty;

            return SafeArea(
              child: Container(
                height: MediaQuery.of(context).size.height * 0.82,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(r.p(20)),
                    topRight: Radius.circular(r.p(20)),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, -6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Drag handle + header
                    Padding(
                      padding: EdgeInsets.only(
                        top: r.p(10),
                        left: r.p(16),
                        right: r.p(8),
                        bottom: r.p(8),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: r.p(44),
                            height: r.p(4),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(r.p(999)),
                            ),
                          ),
                          SizedBox(height: r.p(10)),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Select destination folder',
                                      style: TextStyle(
                                        fontSize: r.sp(18),
                                        fontWeight: FontWeight.w700,
                                        color: Colors.indigo.shade800,
                                      ),
                                    ),
                                    SizedBox(height: r.p(4)),
                                    Text(
                                      'Files will be uploaded to the selected location.',
                                      style: TextStyle(
                                        fontSize: r.sp(12),
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Close',
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Search bar
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        r.p(16),
                        r.p(4),
                        r.p(16),
                        r.p(10),
                      ),
                      child: TextField(
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Search folders',
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            color: Colors.grey.shade600,
                          ),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  tooltip: 'Clear',
                                  icon: Icon(
                                    Icons.clear_rounded,
                                    size: r.sp(18),
                                  ),
                                  onPressed: () {
                                    setModalState(() {
                                      _searchQuery = '';
                                      _filteredFolders = List.from(_folderTree);
                                    });
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: r.p(14),
                            vertical: r.p(12),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(r.p(12)),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(r.p(12)),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(r.p(12)),
                            borderSide: const BorderSide(
                              color: Colors.indigo,
                              width: 1.2,
                            ),
                          ),
                        ),
                        onChanged: (value) {
                          setModalState(() {
                            _searchQuery = value;
                            if (value.trim().isEmpty) {
                              _filteredFolders = List.from(_folderTree);
                            } else {
                              _filteredFolders = _searchFolders(
                                _folderTree,
                                value.toLowerCase(),
                              );
                            }
                          });
                        },
                      ),
                    ),

                    // Root option
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: r.p(16)),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(r.p(14)),
                        onTap: () {
                          setState(() {
                            _selectedFolder = '';
                            _selectedFolderName = null;
                            _selectedFolderId = null;
                          });
                          // Ensure the bottom sheet UI updates immediately.
                          setModalState(() {});
                        },
                        child: Container(
                          padding: EdgeInsets.all(r.p(12)),
                          decoration: BoxDecoration(
                            color: isRootSelected
                                ? Colors.indigo.shade50
                                : Colors.white,
                            borderRadius: BorderRadius.circular(r.p(14)),
                            border: Border.all(
                              color: isRootSelected
                                  ? Colors.indigo.shade200
                                  : Colors.grey.shade200,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: r.p(40),
                                height: r.p(40),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(r.p(12)),
                                ),
                                child: Icon(
                                  Icons.home_rounded,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              SizedBox(width: r.p(12)),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Root',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Colors.grey.shade900,
                                      ),
                                    ),
                                    SizedBox(height: r.p(2)),
                                    Text(
                                      'Upload without choosing a folder',
                                      style: TextStyle(
                                        fontSize: r.sp(12),
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                isRootSelected
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_off_rounded,
                                color: isRootSelected
                                    ? Colors.indigo
                                    : Colors.grey.shade500,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    SizedBox(height: r.p(10)),

                    // Folder list header
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: r.p(16)),
                      child: Row(
                        children: [
                          Text(
                            'Folders',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          const Spacer(),
                          if (inSearch)
                            Text(
                              '${_filteredFolders.length} result${_filteredFolders.length == 1 ? '' : 's'}',
                              style: TextStyle(
                                fontSize: r.sp(12),
                                color: Colors.grey.shade600,
                              ),
                            ),
                        ],
                      ),
                    ),

                    SizedBox(height: r.p(8)),

                    // Folder tree list
                    Expanded(
                      child: (_filteredFolders.isEmpty && inSearch)
                          ? Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: r.p(24),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.folder_off_rounded,
                                      size: r.sp(52),
                                      color: Colors.grey.shade400,
                                    ),
                                    SizedBox(height: r.p(10)),
                                    Text(
                                      'No matching folders',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Colors.grey.shade800,
                                      ),
                                    ),
                                    SizedBox(height: r.p(6)),
                                    Text(
                                      'Try a different name, or clear the search.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: r.sp(12),
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView(
                              padding: EdgeInsets.fromLTRB(
                                r.p(12),
                                0,
                                r.p(12),
                                r.p(8),
                              ),
                              children: [
                                ..._buildTreeListWithCollapse(
                                  _filteredFolders,
                                  0,
                                  setModalState,
                                  inSearch,
                                  context: context,
                                ),
                              ],
                            ),
                    ),

                    // Current selection indicator
                    Container(
                      padding: EdgeInsets.fromLTRB(
                        r.p(16),
                        r.p(12),
                        r.p(16),
                        r.p(14),
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          top: BorderSide(color: Colors.grey.shade200),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: r.p(38),
                            height: r.p(38),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade50,
                              borderRadius: BorderRadius.circular(r.p(12)),
                            ),
                            child: Icon(
                              Icons.folder_rounded,
                              color: Colors.indigo.shade700,
                              size: r.sp(20),
                            ),
                          ),
                          SizedBox(width: r.p(12)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Destination',
                                  style: TextStyle(
                                    fontSize: r.sp(11),
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                SizedBox(height: r.p(2)),
                                Text(
                                  selectedLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: r.sp(14),
                                    color: Colors.grey.shade900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: r.p(10)),
                          ElevatedButton.icon(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: const Text('Use'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(
                                horizontal: r.p(16),
                                vertical: r.p(10),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(r.p(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Helper method to search folders
  List<FolderTreeNode> _searchFolders(
    List<FolderTreeNode> nodes,
    String query,
  ) {
    final List<FolderTreeNode> results = [];

    for (final node in nodes) {
      // Check if node name contains query
      if (node.name.toLowerCase().contains(query)) {
        results.add(node);
      }

      // Always search in children
      if (node.children.isNotEmpty) {
        final childResults = _searchFolders(node.children, query);
        results.addAll(childResults);
      }
    }

    return results;
  }

  // Helper method to build tree list with collapsible sections
  List<Widget> _buildTreeListWithCollapse(
    List<FolderTreeNode> nodes,
    int depth,
    StateSetter setModalState,
    bool isSearchMode, {
    required BuildContext context,
  }) {
    final r = ResponsiveHelper.of(context);
    final List<Widget> widgets = [];

    for (final node in nodes) {
      final isExpanded = _expandedFolders[node.id] ?? false;
      final isSelected = _selectedFolderId == node.id;
      final isLoadingChildren = _loadingFolderChildren[node.id] ?? false;
      final hasLoadedChildren = node.children.isNotEmpty;
      final leftIndent = depth * r.p(14);
      final baseBg = depth == 0 ? Colors.white : Colors.grey.shade50;
      final itemBg = isSelected
          ? Colors.indigo.shade50
          : (isExpanded ? Colors.grey.withValues(alpha: 0.06) : baseBg);
      final borderColor = isSelected
          ? Colors.indigo.shade200
          : (isExpanded ? Colors.grey.shade300 : Colors.grey.shade200);

      widgets.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Folder item
            Padding(
              padding: EdgeInsets.fromLTRB(leftIndent, r.p(4), 0, r.p(4)),
              child: Material(
                color: itemBg,
                borderRadius: BorderRadius.circular(r.p(14)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(r.p(14)),
                  onTap: () {
                    setState(() {
                      _selectedFolder = node.name;
                      _selectedFolderName = node.name;
                      _selectedFolderId = node.id;
                    });
                    // Ensure the bottom sheet UI updates immediately.
                    setModalState(() {});
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: r.p(12),
                      vertical: r.p(10),
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(r.p(14)),
                      border: Border.all(color: borderColor),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isExpanded
                              ? Icons.folder_open_rounded
                              : Icons.folder_rounded,
                          color: Colors.amber.shade700,
                        ),
                        SizedBox(width: r.p(10)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                node.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: isSelected
                                      ? Colors.indigo.shade800
                                      : Colors.grey.shade900,
                                ),
                              ),
                              SizedBox(height: r.p(2)),
                              Text(
                                () {
                                  if (isLoadingChildren)
                                    return 'Loading subfolders…';
                                  if (hasLoadedChildren) {
                                    final c = node.children.length;
                                    return '$c subfolder${c == 1 ? '' : 's'}';
                                  }
                                  if (isExpanded) return '';
                                  return 'Tap ▾ to view subfolders';
                                }(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: r.sp(12),
                                  color: isSelected
                                      ? Colors.indigo.shade600
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: r.p(10)),
                        if (!isSearchMode)
                          isLoadingChildren
                              ? SizedBox(
                                  width: r.p(18),
                                  height: r.p(18),
                                  child: const CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : IconButton(
                                  tooltip: isExpanded ? 'Collapse' : 'Expand',
                                  icon: Icon(
                                    isExpanded
                                        ? Icons.expand_less_rounded
                                        : Icons.expand_more_rounded,
                                    size: r.sp(22),
                                    color: Colors.grey.shade700,
                                  ),
                                  onPressed: () async {
                                    if (isExpanded) {
                                      setModalState(() {
                                        _expandedFolders[node.id] = false;
                                      });
                                      return;
                                    }

                                    setModalState(() {
                                      _expandedFolders[node.id] = true;
                                      _loadingFolderChildren[node.id] = true;
                                    });

                                    final children = await FolderTreeService()
                                        .fetchChildFolders(parent: node);

                                    if (!mounted) return;
                                    setModalState(() {
                                      node.children
                                        ..clear()
                                        ..addAll(children);
                                      _loadingFolderChildren[node.id] = false;
                                    });
                                  },
                                  padding: EdgeInsets.all(r.p(4)),
                                  constraints: const BoxConstraints(),
                                ),
                        InkResponse(
                          radius: r.p(22),
                          onTap: () {
                            setState(() {
                              _selectedFolder = node.name;
                              _selectedFolderName = node.name;
                              _selectedFolderId = node.id;
                            });
                            setModalState(() {});
                          },
                          child: Icon(
                            isSelected
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_off_rounded,
                            color: isSelected
                                ? Colors.indigo
                                : Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Show children if expanded (or always show in search mode)
            if ((isExpanded || isSearchMode) && hasLoadedChildren)
              ...(isSearchMode
                  ? _buildTreeListWithCollapse(
                      node.children,
                      depth + 1,
                      setModalState,
                      isSearchMode,
                      context: context,
                    )
                  : [
                      Padding(
                        padding: EdgeInsets.only(
                          left: leftIndent + r.p(10),
                          right: r.p(2),
                          top: r.p(2),
                          bottom: r.p(6),
                        ),
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: r.p(6)),
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(r.p(14)),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _buildTreeListWithCollapse(
                              node.children,
                              depth + 1,
                              setModalState,
                              false,
                              context: context,
                            ),
                          ),
                        ),
                      ),
                    ]),
          ],
        ),
      );
    }

    return widgets;
  }

  String _destinationLabel() {
    final parts = _selectedFolderId == null
        ? <String>['Root']
        : (_selectedFolderName != null &&
              _selectedFolderName!.trim().isNotEmpty)
        ? <String>['Root', _selectedFolderName!.trim()]
        : <String>['Root'];
    return 'Destination: ${parts.join(' / ')}';
  }

  Future<void> _showUploadSummaryDialog({
    required int total,
    required int uploaded,
    required int failed,
    required int savedLocally,
    String? subtitle,
    String? destinationLabelOverride,
    List<Map<String, String>> failedDetails = const [],
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => UploadResultDialog(
        title: failed == 0 && uploaded > 0
            ? 'Upload successful'
            : 'Upload summary',
        subtitle: subtitle,
        total: total,
        uploaded: uploaded,
        failed: failed,
        savedLocally: savedLocally,
        destinationLabel: destinationLabelOverride ?? _destinationLabel(),
        failedDetails: failedDetails,
      ),
    );
  }

  // Get folder ID for upload - UPDATED VERSION
  Future<String> _getFolderIdForUpload() async {
    // Use the new _selectedFolderId if available
    if (_selectedFolderId != null) {
      if (kDebugMode) {
        print(
          '📁 Using folder ID: $_selectedFolderId for name: $_selectedFolderName',
        );
      }
      return _selectedFolderId.toString();
    }

    // Fallback to old method for backward compatibility
    if (_selectedFolder.isEmpty) {
      if (kDebugMode) {
        print('📁 No folder selected, using empty folder_id');
      }
      return '';
    }

    try {
      final folderId = await FolderHelper.findFolderIdByName(_selectedFolder);

      if (folderId != null) {
        if (kDebugMode) {
          print('📁 Using folder ID: $folderId for name: $_selectedFolder');
        }
        return folderId.toString();
      } else {
        if (kDebugMode) {
          print('⚠ Folder "$_selectedFolder" not found, using empty folder_id');
        }
        return '';
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting folder ID: $e');
      }
      return '';
    }
  }

  // ============ UPLOAD METHODS ============
  Future<void> _uploadDocument() async {
    if (_uploadedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one file to upload'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selectedSharingType == 'Specific Users' && _specificUserIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one user to share with'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String currentUser = widget.userName ?? 'Employee';
      DateTime now = DateTime.now();

      // Convert PlatformFile to File objects
      final List<File> files = [];
      for (var platformFile in _uploadedFiles) {
        if (platformFile.path != null) {
          files.add(File(platformFile.path!));
        }
      }

      if (files.isEmpty) {
        throw Exception('No valid files selected');
      }

      // Get folder ID - FIXED: Use new method
      String folderId = await _getFolderIdForUpload();

      // Prepare form data
      final keywords = _keywordsController.text.isNotEmpty
          ? _keywordsController.text
          : '';
      final remarks = _remarksController.text.isNotEmpty
          ? _remarksController.text
          : '';
      final apiClassification = _mapClassificationForApi(
        _selectedClassification,
      );

      // Call the appropriate upload method based on connection
      if (_isConnected) {
        final shouldPublishToLibrary = _selectedSharingType == 'Public';
        final shouldShareWithUsers =
            _selectedSharingType == 'Specific Users' || _shareWithSpecificUsers;
        final shareUserIds = shouldShareWithUsers
            ? _specificUserIds.toList()
            : const <String>[];

        // Online mode - use UploadService
        Map<String, dynamic> uploadResult;
        if (_uploadedFiles.length == 1) {
          // Single file upload
          uploadResult = await UploadService.uploadSingleFile(
            file: files.first,
            keywords: keywords,
            remarks: remarks,
            docClass: apiClassification,
            allowDownload: _allowDownload,
            folderId: folderId, // Now numeric ID or empty
            // Share/publish happens after upload-confirm via dedicated APIs.
            sharing: 'private',
            specificUsers: '[]',
          );
        } else {
          // Multiple files upload
          uploadResult = await UploadService.uploadMultipleFiles(
            files: files,
            keywords: keywords,
            remarks: remarks,
            docClass: apiClassification,
            allowDownload: _allowDownload,
            folderId: folderId, // Now numeric ID or empty
            // Share/publish happens after upload-confirm via dedicated APIs.
            sharing: 'private',
            specificUsers: '[]',
          );
        }

        if (kDebugMode) {
          print('📊 Upload result: $uploadResult');
        }

        final total = _uploadedFiles.length;
        final destLabel = _destinationLabel();

        // Prefer per-file results when available (supports partial uploads + reasons).
        final fileResultsRaw = uploadResult['file_results'];
        final fileResults = (fileResultsRaw is List)
            ? fileResultsRaw
                  .whereType<Map>()
                  .map((m) => Map<String, dynamic>.from(m))
                  .toList()
            : <Map<String, dynamic>>[];

        final successNames = <String>{};
        final failedDetails = <Map<String, String>>[];

        for (final r in fileResults) {
          final name = (r['fileName'] ?? r['file_name'] ?? '').toString();
          final ok = r['success'] == true;
          if (name.isEmpty) continue;
          if (ok) {
            successNames.add(name);
          } else {
            failedDetails.add({
              'file': name,
              'reason':
                  (r['error'] ?? uploadResult['message'] ?? 'Upload failed')
                      .toString(),
            });
          }
        }

        final uploadedCount = successNames.isNotEmpty
            ? successNames.length
            : (uploadResult['success'] == true ? total : 0);
        final failedCount = fileResults.isNotEmpty
            ? failedDetails.length
            : (uploadResult['success'] == true ? 0 : total);

        if (uploadResult['success'] == true || uploadedCount > 0) {
          // Create Document objects only for uploaded files (prevents false positives on partial uploads).
          final isPublic = shouldPublishToLibrary;
          for (var i = 0; i < _uploadedFiles.length; i++) {
            final platformFile = _uploadedFiles[i];
            final name = platformFile.name;
            if (successNames.isNotEmpty && !successNames.contains(name)) {
              continue;
            }

            String docId = _resolveUploadedDocumentId(uploadResult, i);
            for (final r in fileResults) {
              final rn = (r['fileName'] ?? '').toString();
              if (rn == name && r['documentId'] != null) {
                docId = r['documentId'].toString();
                break;
              }
            }

            final newDoc = _buildUploadedDocument(
              platformFile: platformFile,
              currentUser: currentUser,
              now: now,
              documentId: docId,
            );

            widget.onDocumentUploaded(newDoc);
            LocalStorageService.addDocument(newDoc, isPublic: isPublic);

            // Post-upload access controls:
            // - "Public" means publish-to-library (separate endpoint)
            // - "Specific Users" means create share records (separate endpoint)
            if (docId.isNotEmpty) {
              if (shouldPublishToLibrary) {
                try {
                  await _libraryService.publishDocument(docId);
                } catch (_) {}
              }
              if (shareUserIds.isNotEmpty) {
                for (final uid in shareUserIds) {
                  try {
                    await _sharesService.share(
                      type: ShareEntityType.document,
                      entityId: docId,
                      sharedWithIdOrEmail: uid,
                      permission: 'view',
                      allowDownload: _allowDownload,
                    );
                  } catch (_) {}
                }
              }
            }
          }

          final subtitle = failedCount == 0
              ? 'All files uploaded to server.'
              : 'Some files could not be uploaded. You can retry the failed ones.';

          await _showUploadSummaryDialog(
            total: total,
            uploaded: uploadedCount,
            failed: failedCount,
            savedLocally: 0,
            subtitle: subtitle,
            destinationLabelOverride: destLabel,
            failedDetails: failedDetails,
          );

          if (failedCount == 0) {
            _resetForm();
          } else {
            // Keep failed files selected to allow quick retry.
            if (successNames.isNotEmpty) {
              setState(() {
                _uploadedFiles.removeWhere(
                  (f) => successNames.contains(f.name),
                );
              });
            }
          }
        } else {
          // Upload failed - check if it's authentication error
          if (uploadResult['requiresLogin'] == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Session expired. Please login again.'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 3),
                action: SnackBarAction(
                  label: 'Login',
                  textColor: Colors.white,
                  onPressed: () {
                    // Navigate to login page
                    Navigator.pushReplacementNamed(context, '/login');
                  },
                ),
              ),
            );
            return;
          }

          final status = uploadResult['statusCode'];
          final errorBody = uploadResult['error'];
          final details = (status != null || errorBody != null)
              ? ' (status: ${status ?? 'n/a'}) ${errorBody ?? ''}'
              : '';

          final failSubtitle =
              'Server upload failed: ${uploadResult['message']}$details. Saved locally instead.';

          _saveDocumentsLocally(currentUser, now);

          await _showUploadSummaryDialog(
            total: total,
            uploaded: 0,
            failed: 0,
            savedLocally: total,
            subtitle: failSubtitle,
            destinationLabelOverride: destLabel,
          );
        }
      } else {
        // Offline mode - save locally only
        final total = _uploadedFiles.length;
        final destLabel = _destinationLabel();
        _saveDocumentsLocally(currentUser, now);

        await _showUploadSummaryDialog(
          total: total,
          uploaded: 0,
          failed: 0,
          savedLocally: total,
          subtitle:
              'Offline mode: saved locally. Upload will sync when online.',
          destinationLabelOverride: destLabel,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Upload error: $e');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _ensureShareUsersLoaded() async {
    if (_shareUsersLoading || _shareUsers.isNotEmpty) return;
    setState(() => _shareUsersLoading = true);
    try {
      final users = await _sharesService.getUsers();
      if (!mounted) return;
      setState(() => _shareUsers = users);
    } catch (_) {
      // keep empty; UI will show "no users"
    } finally {
      if (mounted) setState(() => _shareUsersLoading = false);
    }
  }

  String _shareUserId(Map<String, dynamic> u) {
    return (u['id'] ?? u['user_id'] ?? u['userId'] ?? '').toString();
  }

  String _shareUserName(Map<String, dynamic> u) {
    return (u['name'] ??
            u['full_name'] ??
            u['display_name'] ??
            u['username'] ??
            'User')
        .toString();
  }

  String _shareUserSubtitle(Map<String, dynamic> u) {
    final employeeId = (u['employee_id'] ?? u['emp_id'] ?? '').toString();
    final email = (u['email'] ?? u['email_address'] ?? '').toString();
    if (employeeId.isNotEmpty && email.isNotEmpty)
      return '$employeeId • $email';
    if (employeeId.isNotEmpty) return employeeId;
    if (email.isNotEmpty) return email;
    return '';
  }

  Future<void> _pickSpecificUsers() async {
    await _ensureShareUsersLoaded();
    if (!mounted) return;

    final search = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(context.r.p(20)),
        ),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final r = ResponsiveHelper.of(context);
          final q = search.text.trim().toLowerCase();
          final users = q.isEmpty
              ? _shareUsers
              : _shareUsers.where((u) {
                  final hay = '${_shareUserName(u)} ${_shareUserSubtitle(u)}'
                      .toLowerCase();
                  return hay.contains(q);
                }).toList();

          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.85,
              child: Column(
                children: [
                  SizedBox(height: r.p(10)),
                  Container(
                    width: r.p(40),
                    height: r.p(4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(r.p(2)),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      r.p(16),
                      r.p(12),
                      r.p(16),
                      r.p(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Share with Specific Users',
                            style: TextStyle(
                              fontSize: r.sp(16),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      r.p(16),
                      r.p(4),
                      r.p(16),
                      r.p(8),
                    ),
                    child: TextField(
                      controller: search,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Search users...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: search.text.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () {
                                  search.clear();
                                  setState(() {});
                                },
                                icon: const Icon(Icons.clear),
                              ),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(r.p(12)),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: _shareUsersLoading
                        ? const Center(child: CircularProgressIndicator())
                        : users.isEmpty
                        ? Center(
                            child: Text(
                              'No users found',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          )
                        : ListView.builder(
                            itemCount: users.length,
                            itemBuilder: (context, index) {
                              final u = users[index];
                              final id = _shareUserId(u);
                              if (id.isEmpty) return const SizedBox.shrink();
                              final selected = _specificUserIds.contains(id);
                              final subtitle = _shareUserSubtitle(u);
                              return CheckboxListTile(
                                value: selected,
                                title: Text(_shareUserName(u)),
                                subtitle: subtitle.isNotEmpty
                                    ? Text(subtitle)
                                    : null,
                                onChanged: (v) {
                                  setState(() {
                                    if (v == true) {
                                      _specificUserIds.add(id);
                                    } else {
                                      _specificUserIds.remove(id);
                                    }
                                  });
                                  this.setState(() {});
                                },
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      r.p(16),
                      r.p(8),
                      r.p(16),
                      r.p(12),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: r.p(46),
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.check),
                        label: Text(
                          _specificUserIds.isEmpty
                              ? 'Done'
                              : 'Done (${_specificUserIds.length} selected)',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    search.dispose();
  }

  // Helper method to save documents locally
  void _saveDocumentsLocally(String currentUser, DateTime now) {
    for (var platformFile in _uploadedFiles) {
      final newDoc = _buildUploadedDocument(
        platformFile: platformFile,
        currentUser: currentUser,
        now: now,
        documentId: DateTime.now().millisecondsSinceEpoch.toString(),
      );

      widget.onDocumentUploaded(newDoc);
      final isPublic = _selectedSharingType == 'Public';
      LocalStorageService.addDocument(newDoc, isPublic: isPublic);
    }

    // Reset form after local save
    _resetForm();
  }

  // Reset form after upload
  void _resetForm() {
    setState(() {
      _uploadedFiles.clear();
      _keywordsController.clear();
      _remarksController.clear();
      _selectedClassification = 'General';
      _allowDownload = true;
      _selectedSharingType = 'Public';

      // Reset folder selection
      _selectedFolder = '';
      _selectedFolderName = null;
      _selectedFolderId = null;
    });
  }

  // ============ FILE PICKER METHODS ============
  Future<void> _pickSingleFile() async {
    try {
      setState(() => _isLoading = true);

      // Show a dialog to select file type
      String? fileType = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Select File Type'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.audio_file),
                title: const Text('Audio Files'),
                onTap: () => Navigator.pop(context, 'audio'),
              ),
              ListTile(
                leading: const Icon(Icons.video_file),
                title: const Text('Video Files'),
                onTap: () => Navigator.pop(context, 'video'),
              ),
              ListTile(
                leading: const Icon(Icons.image),
                title: const Text('Image Files'),
                onTap: () => Navigator.pop(context, 'image'),
              ),
              ListTile(
                leading: const Icon(Icons.description),
                title: const Text('Document Files'),
                onTap: () => Navigator.pop(context, 'document'),
              ),
              ListTile(
                leading: const Icon(Icons.code),
                title: const Text('Code Files'),
                onTap: () => Navigator.pop(context, 'code'),
              ),
              ListTile(
                leading: const Icon(Icons.insert_drive_file),
                title: const Text('All Files'),
                onTap: () => Navigator.pop(context, 'all'),
              ),
            ],
          ),
        ),
      );

      if (fileType == null) return;

      FilePickerResult? result;

      switch (fileType) {
        case 'audio':
          result = await FilePicker.platform.pickFiles(
            type: FileType.audio,
            allowMultiple: false,
          );
          break;
        case 'video':
          result = await FilePicker.platform.pickFiles(
            type: FileType.video,
            allowMultiple: false,
          );
          break;
        case 'image':
          result = await FilePicker.platform.pickFiles(
            type: FileType.image,
            allowMultiple: false,
          );
          break;
        case 'document':
          result = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: [
              // Legacy Office
              'doc',
              'xls',
              'ppt',
              'rtf',
              'mdb',
              'pub',
              'pps',
              'dot',
              'xlt',
              'pot',
              // Modern Office
              'docx', 'xlsx', 'pptx', 'dotx', 'xltx', 'potx', 'accdb', 'one',
              // OpenDocument
              'odt', 'ods', 'odp', 'odg', 'odf',
              // Apple iWork
              'pages', 'numbers', 'key',
              // PDFs
              'pdf',
              // Text Files
              'txt', 'md', 'markdown',
              // CSV/Data
              'csv', 'tsv', 'xml', 'json',
              // ZIP & Archives
              'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'iso',
              // Google Files
              'gdoc', 'gsheet', 'gslides', 'gdraw',
            ],
            allowMultiple: false,
          );
          break;
        case 'code':
          result = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: [
              'doc', 'docx', 'dot', 'dotx', 'gdoc',
              // Python
              'py',
              'pyc',
              'pyo',
              'pyd',
              // JavaScript/TypeScript/React/Node.js
              'js',
              'jsx',
              'ts',
              'tsx',
              'node',
              'njs',
              // HTML/CSS
              'html', 'htm', 'css', 'scss', 'sass', 'less',
              // Database
              'sql',
              'db',
              'sqlite',
              'sqlite3',
              'mdb',
              'accdb',
              'frm',
              'myd',
              'myi',
              // Other programming languages
              'java',
              'class',
              'jar',
              'c',
              'cpp',
              'cc',
              'cxx',
              'h',
              'hpp',
              'hxx',
              'cs',
              'php',
              'phtml',
              'rb',
              'erb',
              'go',
              'rs',
              'swift',
              'kt',
              'kts',
              'dart',
              // Shell/Bash
              'sh', 'bash', 'zsh', 'fish', 'ps1', 'bat', 'cmd',
              // Configuration Files
              'env', 'config', 'toml', 'ini', 'yaml', 'yml',
              // JSON Files
              'json', 'jsonl', 'jsonc',
              // Other Code Files
              'log',
              'lock',
              'license',
              'readme',
              'gitignore',
              'dockerfile',
              'makefile',
            ],
            allowMultiple: false,
          );
          break;
        case 'all':
        default:
          result = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: _allSupportedExtensions,
            allowMultiple: false,
          );
          break;
      }

      if (result != null && result.files.isNotEmpty && mounted) {
        PlatformFile file = result.files.first;

        if (kDebugMode) {
          print('📄 ===== FILE PICKER DEBUG =====');
          print('📄 File name: ${file.name}');
          print('📄 File path: ${file.path}');
          print('📄 File size: ${file.size} bytes');
          print(
            "📄 File extension: ${file.name.split('.').last.toLowerCase()}",
          );
        }

        if (file.size > 500 * 1024 * 1024) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('File "${file.name}" exceeds 500MB limit'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        if (file.path == null || file.path!.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Cannot access file "${file.name}". Please try again.',
              ),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        final fileObj = File(file.path!);
        if (!fileObj.existsSync()) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('File "${file.name}" not found or inaccessible.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        setState(() {
          _uploadedFiles.add(file);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Selected: ${file.name}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('File picker error: $e');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking file: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickMultipleFiles() async {
    try {
      setState(() => _isLoading = true);

      // Show a dialog to select file type
      String? fileType = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Select File Type'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.audio_file),
                title: const Text('Audio Files'),
                onTap: () => Navigator.pop(context, 'audio'),
              ),
              ListTile(
                leading: const Icon(Icons.video_file),
                title: const Text('Video Files'),
                onTap: () => Navigator.pop(context, 'video'),
              ),
              ListTile(
                leading: const Icon(Icons.image),
                title: const Text('Image Files'),
                onTap: () => Navigator.pop(context, 'image'),
              ),
              ListTile(
                leading: const Icon(Icons.description),
                title: const Text('Document Files'),
                onTap: () => Navigator.pop(context, 'document'),
              ),
              ListTile(
                leading: const Icon(Icons.code),
                title: const Text('Code Files'),
                onTap: () => Navigator.pop(context, 'code'),
              ),
              ListTile(
                leading: const Icon(Icons.insert_drive_file),
                title: const Text('All Files'),
                onTap: () => Navigator.pop(context, 'all'),
              ),
            ],
          ),
        ),
      );

      if (fileType == null) return;

      FilePickerResult? result;
      List<String> selectedExtensions = [];

      switch (fileType) {
        case 'audio':
          result = await FilePicker.platform.pickFiles(
            type: FileType.audio,
            allowMultiple: true,
          );
          selectedExtensions = [
            'mp3',
            'wav',
            'ogg',
            'flac',
            'aac',
            'm4a',
            'wma',
            'opus',
            'mid',
            'midi',
            'aiff',
            'au',
          ];
          break;
        case 'video':
          result = await FilePicker.platform.pickFiles(
            type: FileType.video,
            allowMultiple: true,
          );
          selectedExtensions = [
            'mp4',
            'mov',
            'avi',
            'mkv',
            'flv',
            'wmv',
            'webm',
            'm4v',
            'mpg',
            'mpeg',
            '3gp',
            'mts',
            'vob',
            'ogv',
          ];
          break;
        case 'image':
          result = await FilePicker.platform.pickFiles(
            type: FileType.image,
            allowMultiple: true,
          );
          selectedExtensions = [
            'jpg',
            'jpeg',
            'jfif',
            'png',
            'gif',
            'bmp',
            'webp',
            'svg',
            'tiff',
            'tif',
            'ico',
            'heic',
            'heif',
            'raw',
            'cr2',
            'nef',
            'orf',
            'sr2',
          ];
          break;
        case 'document':
          result = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: [
              // Legacy Office
              'doc',
              'xls',
              'ppt',
              'rtf',
              'mdb',
              'pub',
              'pps',
              'dot',
              'xlt',
              'pot',
              // Modern Office
              'docx', 'xlsx', 'pptx', 'dotx', 'xltx', 'potx', 'accdb', 'one',
              // OpenDocument
              'odt', 'ods', 'odp', 'odg', 'odf',
              // Apple iWork
              'pages', 'numbers', 'key',
              // PDFs
              'pdf',
              // Text Files
              'txt', 'md', 'markdown',
              // CSV/Data
              'csv', 'tsv', 'xml', 'json',
              // ZIP & Archives
              'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'iso',
              // Google Files
              'gdoc', 'gsheet', 'gslides', 'gdraw',
            ],
            allowMultiple: true,
          );
          selectedExtensions = [
            'doc',
            'xls',
            'ppt',
            'rtf',
            'mdb',
            'pub',
            'pps',
            'dot',
            'xlt',
            'pot',
            'docx',
            'xlsx',
            'pptx',
            'dotx',
            'xltx',
            'potx',
            'accdb',
            'one',
            'odt',
            'ods',
            'odp',
            'odg',
            'odf',
            'pages',
            'numbers',
            'key',
            'pdf',
            'txt',
            'md',
            'markdown',
            'csv',
            'tsv',
            'xml',
            'json',
            'zip',
            'rar',
            '7z',
            'tar',
            'gz',
            'bz2',
            'xz',
            'iso',
            'gdoc',
            'gsheet',
            'gslides',
            'gdraw',
          ];
          break;
        case 'code':
          result = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: [
              // Python
              'py', 'pyc', 'pyo', 'pyd',
              // JavaScript/TypeScript/React/Node.js
              'js', 'jsx', 'ts', 'tsx', 'node', 'njs',
              // HTML/CSS
              'html', 'htm', 'css', 'scss', 'sass', 'less',
              // Database
              'sql',
              'db',
              'sqlite',
              'sqlite3',
              'mdb',
              'accdb',
              'frm',
              'myd',
              'myi',
              // Other programming languages
              'java',
              'class',
              'jar',
              'c',
              'cpp',
              'cc',
              'cxx',
              'h',
              'hpp',
              'hxx',
              'cs',
              'php',
              'phtml',
              'rb',
              'erb',
              'go',
              'rs',
              'swift',
              'kt',
              'kts',
              'dart',
              // Shell/Bash
              'sh', 'bash', 'zsh', 'fish', 'ps1', 'bat', 'cmd',
              // Configuration Files
              'env', 'config', 'toml', 'ini', 'yaml', 'yml',
              // JSON Files
              'json', 'jsonl', 'jsonc',
              // Other Code Files
              'log',
              'lock',
              'license',
              'readme',
              'gitignore',
              'dockerfile',
              'makefile',
            ],
            allowMultiple: true,
          );
          selectedExtensions = [
            'py',
            'pyc',
            'pyo',
            'pyd',
            'js',
            'jsx',
            'ts',
            'tsx',
            'node',
            'njs',
            'html',
            'htm',
            'css',
            'scss',
            'sass',
            'less',
            'sql',
            'db',
            'sqlite',
            'sqlite3',
            'mdb',
            'accdb',
            'frm',
            'myd',
            'myi',
            'java',
            'class',
            'jar',
            'c',
            'cpp',
            'cc',
            'cxx',
            'h',
            'hpp',
            'hxx',
            'cs',
            'php',
            'phtml',
            'rb',
            'erb',
            'go',
            'rs',
            'swift',
            'kt',
            'kts',
            'dart',
            'sh',
            'bash',
            'zsh',
            'fish',
            'ps1',
            'bat',
            'cmd',
            'env',
            'config',
            'toml',
            'ini',
            'yaml',
            'yml',
            'json',
            'jsonl',
            'jsonc',
            'log',
            'lock',
            'license',
            'readme',
            'gitignore',
            'dockerfile',
            'makefile',
          ];
          break;
        case 'all':
        default:
          result = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: _allSupportedExtensions,
            allowMultiple: true,
          );
          selectedExtensions = _allSupportedExtensions;
          break;
      }

      if (result != null && result.files.isNotEmpty && mounted) {
        int addedFiles = 0;
        int skippedFiles = 0;

        for (var file in result.files) {
          final extension = file.name.split('.').last.toLowerCase();

          if (fileType == 'all' || selectedExtensions.contains(extension)) {
            if (file.size > 500 * 1024 * 1024) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('File "${file.name}" exceeds 500MB limit'),
                  backgroundColor: Colors.red,
                ),
              );
              skippedFiles++;
              continue;
            }

            setState(() {
              _uploadedFiles.add(file);
            });
            addedFiles++;
          } else {
            skippedFiles++;
          }
        }

        if (addedFiles > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "✅ Added $addedFiles file(s)${skippedFiles > 0 ? ' (skipped $skippedFiles)' : ''}",
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Multiple file picker error: $e');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking files: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickFolder() async {
    setState(() => _isLoading = true);
    try {
      final dirPath = await FilePicker.platform.getDirectoryPath();
      if (dirPath == null) return;

      final rootDir = Directory(dirPath);
      final rootName = dirPath.split(Platform.pathSeparator).last;

      final allEntities = rootDir.listSync(recursive: true, followLinks: false);
      final files = allEntities.whereType<File>().toList();

      if (files.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No files found in selected folder'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Collect unique relative sub-directory paths
      final relDirs = <String>{};
      for (final file in files) {
        final rel = file.path
            .replaceFirst(rootDir.path, '')
            .replaceAll('\\', '/');
        final parts = rel.split('/').where((p) => p.isNotEmpty).toList();
        for (int i = 0; i < parts.length - 1; i++) {
          relDirs.add(parts.sublist(0, i + 1).join('/'));
        }
      }

      // Create folder structure via API
      final Map<String, String> pathToId = {};
      if (relDirs.isNotEmpty) {
        final folderPayload = relDirs
            .map(
              (p) => {
                'name': p.split('/').last,
                'path': p,
                'parentId': _selectedFolderId,
              },
            )
            .toList();
        final result = await FolderOperationsService().bulkCreateFolders(
          folderPayload,
        );
        if (result['success'] == true) {
          final created = result['data']?['folders'] ?? result['data'] ?? [];
          if (created is List) {
            for (final f in created) {
              if (f is Map) {
                final p = f['path']?.toString() ?? '';
                final id = f['id']?.toString() ?? '';
                if (p.isNotEmpty && id.isNotEmpty) pathToId[p] = id;
              }
            }
          }
        }
      }

      // Add files to the upload list
      int added = 0;
      for (final file in files) {
        final rel = file.path
            .replaceFirst(rootDir.path, '')
            .replaceAll('\\', '/');
        final parts = rel.split('/').where((p) => p.isNotEmpty).toList();
        final fileName = parts.last;

        final stat = await file.stat();
        final pf = PlatformFile(
          path: file.path,
          name: fileName,
          size: stat.size,
        );
        setState(() => _uploadedFiles.add(pf));
        added++;
      }

      if (added > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added $added file(s) from "$rootName"'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Folder pick error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ============ FILE ICON/COLOR METHODS ============
  IconData _getFileIcon(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'docx':
      case 'doc':
      case 'dot':
      case 'dotx':
        return Icons.description;
      case 'xlsx':
      case 'xls':
      case 'csv':
      case 'ods':
        return Icons.table_chart;
      case 'pptx':
      case 'ppt':
      case 'odp':
        return Icons.slideshow;
      case 'txt':
      case 'rtf':
      case 'md':
      case 'odt':
        return Icons.text_fields;
      case 'js':
      case 'jsx':
        return Icons.code;
      case 'ts':
      case 'tsx':
        return Icons.data_object;
      case 'json':
        return Icons.data_array;
      case 'py':
      case 'pyc':
      case 'pyo':
      case 'pyd':
        return Icons.account_tree;
      case 'html':
      case 'htm':
        return Icons.language;
      case 'css':
      case 'scss':
      case 'sass':
      case 'less':
        return Icons.palette;
      case 'node':
      case 'njs':
        return Icons.dns;
      case 'java':
      case 'class':
      case 'jar':
        return Icons.coffee;
      case 'c':
      case 'cpp':
      case 'cc':
      case 'h':
      case 'hpp':
        return Icons.memory;
      case 'php':
        return Icons.web;
      case 'rb':
      case 'erb':
        return Icons.diamond;
      case 'go':
        return Icons.rocket_launch;
      case 'rs':
        return Icons.settings;
      case 'kt':
      case 'kts':
        return Icons.android;
      case 'swift':
        return Icons.phone_iphone;
      case 'dart':
        return Icons.flutter_dash;
      case 'sql':
      case 'db':
      case 'sqlite':
        return Icons.storage;
      case 'xml':
      case 'yaml':
      case 'yml':
        return Icons.format_align_left;
      case 'env':
      case 'config':
      case 'toml':
      case 'ini':
        return Icons.settings_applications;
      case 'sh':
      case 'bash':
      case 'zsh':
      case 'fish':
        return Icons.terminal;
      case 'mp3':
      case 'wav':
      case 'aac':
      case 'm4a':
      case 'ogg':
      case 'flac':
      case 'wma':
        return Icons.audiotrack;
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv':
      case 'flv':
      case 'wmv':
      case 'webm':
        return Icons.videocam;
      case 'jpg':
      case 'jpeg':
      case 'jfif':
      case 'png':
      case 'gif':
      case 'bmp':
      case 'tiff':
      case 'svg':
      case 'webp':
        return Icons.image;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
      case 'bz2':
        return Icons.archive;
      case 'exe':
      case 'app':
      case 'dmg':
      case 'deb':
      case 'rpm':
        return Icons.play_arrow;
      case 'vue':
        return Icons.view_quilt;
      case 'svelte':
        return Icons.dashboard;
      case 'lock':
      case 'package':
        return Icons.inventory;
      case 'log':
        return Icons.assignment;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileColor(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'pdf':
        return Colors.red;
      case 'docx':
      case 'gdoc':
      case 'gslides':
      case 'gsheet':
      case 'gform':
      case 'gscript':
        return Colors.blue;
      case 'xlsx':
      case 'xls':
      case 'csv':
        return Colors.green;
      case 'pptx':
      case 'ppt':
        return Colors.orange;
      case 'txt':
      case 'rtf':
      case 'md':
        return Colors.grey;
      case 'js':
      case 'jsx':
        return Colors.yellow[700]!;
      case 'ts':
      case 'tsx':
        return Colors.blue[700]!;
      case 'json':
        return Colors.amber;
      case 'py':
      case 'pyc':
      case 'pyo':
      case 'pyd':
        return Colors.blue[400]!;
      case 'html':
      case 'htm':
        return Colors.deepOrange;
      case 'css':
      case 'scss':
      case 'sass':
      case 'less':
        return Colors.blue[300]!;
      case 'node':
      case 'njs':
        return Colors.green[600]!;
      case 'java':
      case 'class':
      case 'jar':
        return Colors.red[700]!;
      case 'c':
      case 'cpp':
      case 'cc':
      case 'h':
      case 'hpp':
        return Colors.purple;
      case 'php':
        return Colors.purple[400]!;
      case 'rb':
      case 'erb':
        return Colors.red[900]!;
      case 'go':
        return Colors.cyan;
      case 'rs':
        return Colors.deepOrange[900]!;
      case 'kt':
      case 'kts':
        return Colors.purple[600]!;
      case 'swift':
        return Colors.orange;
      case 'dart':
        return Colors.blue[500]!;
      case 'sql':
      case 'db':
      case 'sqlite':
        return Colors.brown;
      case 'xml':
      case 'yaml':
      case 'yml':
        return Colors.green[400]!;
      case 'env':
      case 'config':
      case 'toml':
      case 'ini':
        return Colors.grey[600]!;
      case 'sh':
      case 'bash':
      case 'zsh':
      case 'fish':
        return Colors.green[800]!;
      case 'mp3':
      case 'wav':
      case 'aac':
      case 'm4a':
      case 'ogg':
      case 'flac':
      case 'wma':
        return Colors.purple;
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv':
      case 'flv':
      case 'wmv':
      case 'webm':
        return Colors.deepOrange;
      case 'jpg':
      case 'jpeg':
      case 'jfif':
      case 'png':
      case 'gif':
      case 'bmp':
      case 'tiff':
      case 'svg':
      case 'webp':
        return Colors.pink;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
      case 'bz2':
        return Colors.brown;
      case 'exe':
      case 'app':
      case 'dmg':
      case 'deb':
      case 'rpm':
        return Colors.green[700]!;
      case 'vue':
        return Colors.green[400]!;
      case 'svelte':
        return Colors.orange[300]!;
      case 'lock':
      case 'package':
        return Colors.blueGrey;
      case 'log':
        return Colors.grey[700]!;
      default:
        return Colors.grey;
    }
  }

  // ============ BUILD METHOD ============
  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final layout = AppLayout.of(context);
    return DismissKeyboard(
      child: Container(
        color: Colors.white,
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: layout.gutter,
            vertical: r.p(24),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: layout.maxContentWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    'Upload Files',
                    style: TextStyle(
                      fontSize: r.sp(24),
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                    ),
                  ),
                  SizedBox(height: r.p(20)),

                  // Upload Type Selection
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(r.p(12)),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(r.p(16)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Upload Type',
                            style: TextStyle(
                              fontSize: r.sp(16),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: r.p(12)),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              if (constraints.maxWidth < 600) {
                                return Column(
                                  children: [
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: _isLoading
                                            ? null
                                            : _pickSingleFile,
                                        icon: const Icon(
                                          Icons.insert_drive_file,
                                        ),
                                        label: const Text('Single File'),
                                        style: OutlinedButton.styleFrom(
                                          padding: EdgeInsets.symmetric(
                                            vertical: r.p(12),
                                          ),
                                          side: const BorderSide(
                                            color: Colors.indigo,
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: r.p(12)),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: _isLoading
                                            ? null
                                            : _pickMultipleFiles,
                                        icon: const Icon(Icons.folder_copy),
                                        label: const Text('Multiple Files'),
                                        style: OutlinedButton.styleFrom(
                                          padding: EdgeInsets.symmetric(
                                            vertical: r.p(12),
                                          ),
                                          side: const BorderSide(
                                            color: Colors.indigo,
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: r.p(12)),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: _isLoading
                                            ? null
                                            : _pickFolder,
                                        icon: const Icon(Icons.folder),
                                        label: const Text('Entire Folder'),
                                        style: OutlinedButton.styleFrom(
                                          padding: EdgeInsets.symmetric(
                                            vertical: r.p(12),
                                          ),
                                          side: const BorderSide(
                                            color: Colors.indigo,
                                          ),
                                          foregroundColor: Colors.indigo,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              } else {
                                return Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: _isLoading
                                            ? null
                                            : _pickSingleFile,
                                        icon: const Icon(
                                          Icons.insert_drive_file,
                                        ),
                                        label: const Text('Single File'),
                                        style: OutlinedButton.styleFrom(
                                          padding: EdgeInsets.symmetric(
                                            vertical: r.p(12),
                                          ),
                                          side: const BorderSide(
                                            color: Colors.indigo,
                                          ),
                                          foregroundColor: Colors.indigo,
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: r.p(12)),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: _isLoading
                                            ? null
                                            : _pickMultipleFiles,
                                        icon: const Icon(Icons.folder_copy),
                                        label: const Text('Multiple Files'),
                                        style: OutlinedButton.styleFrom(
                                          padding: EdgeInsets.symmetric(
                                            vertical: r.p(12),
                                          ),
                                          side: const BorderSide(
                                            color: Colors.indigo,
                                          ),
                                          foregroundColor: Colors.indigo,
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: r.p(12)),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: _isLoading
                                            ? null
                                            : _pickFolder,
                                        icon: const Icon(Icons.folder),
                                        label: const Text('Entire Folder'),
                                        style: OutlinedButton.styleFrom(
                                          padding: EdgeInsets.symmetric(
                                            vertical: r.p(12),
                                          ),
                                          side: const BorderSide(
                                            color: Colors.indigo,
                                          ),
                                          foregroundColor: Colors.indigo,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: r.p(24)),

                  if (_uploadedFiles.isNotEmpty) ...[
                    SizedBox(height: r.p(24)),
                    Text(
                      'Selected Files:',
                      style: TextStyle(
                        fontSize: r.sp(16),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: r.p(8)),
                    ..._uploadedFiles.map(
                      (file) => Card(
                        color: Colors.white,
                        margin: EdgeInsets.only(bottom: r.p(8)),
                        child: ListTile(
                          leading: Icon(
                            _getFileIcon(file.name),
                            color: _getFileColor(file.name),
                          ),
                          title: Text(file.name),
                          subtitle: Text(_getFileSizeString(file.size)),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            onPressed: () {
                              setState(() {
                                _uploadedFiles.remove(file);
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                  ],

                  SizedBox(height: r.p(24)),
                  const Divider(),

                  // Document Details Section
                  Text(
                    'Document Details',
                    style: TextStyle(
                      fontSize: r.sp(18),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: r.p(16)),

                  // Destination Folder Dropdown with Create Folder option
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(r.p(12)),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(r.p(16)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Container(
                              width: r.p(44),
                              height: r.p(44),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2B41BD).withAlpha(18),
                                borderRadius: BorderRadius.circular(r.p(12)),
                                border: Border.all(
                                  color: const Color(0xFF2B41BD).withAlpha(35),
                                ),
                              ),
                              child: Icon(
                                _selectedFolderId == null
                                    ? Icons.home_rounded
                                    : Icons.folder_rounded,
                                color: const Color(0xFF2B41BD),
                              ),
                            ),
                            title: const Text(
                              'Destination folder',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              _selectedFolderId == null
                                  ? 'Root (No folder)'
                                  : (_selectedFolderName ?? 'Selected folder'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: _foldersLoading
                                ? SizedBox(
                                    width: r.p(20),
                                    height: r.p(20),
                                    child: const CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.chevron_right_rounded),
                            onTap: _foldersLoading
                                ? null
                                : () => _showFolderSelector(context),
                          ),
                          SizedBox(height: r.p(10)),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _foldersLoading
                                      ? null
                                      : () => _showFolderSelector(context),
                                  icon: Icon(
                                    Icons.folder_open_rounded,
                                    size: r.sp(18),
                                  ),
                                  label: const Text('Change'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF2B41BD),
                                    side: BorderSide(
                                      color: const Color(
                                        0xFF2B41BD,
                                      ).withAlpha(70),
                                    ),
                                    padding: EdgeInsets.symmetric(
                                      vertical: r.p(12),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        r.p(12),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(width: r.p(12)),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () =>
                                      _navigateToFolderManager(context),
                                  icon: Icon(
                                    Icons.create_new_folder_rounded,
                                    size: r.sp(18),
                                  ),
                                  label: const Text('Create'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF2B41BD),
                                    padding: EdgeInsets.symmetric(
                                      vertical: r.p(12),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        r.p(12),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: r.p(8)),
                          Text(
                            _selectedFolderId == null
                                ? 'Uploads will go to the root directory.'
                                : 'Uploads will go to "${_selectedFolderName ?? 'selected folder'}".',
                            style: TextStyle(
                              fontSize: r.sp(12),
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: r.p(16)),

                  // Classification Dropdown with specified options
                  DropdownButtonFormField<String>(
                    initialValue: _selectedClassification,
                    decoration: InputDecoration(
                      labelText: 'Classification',
                      prefixIcon: const Icon(
                        Icons.security,
                        color: Colors.indigo,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(r.p(8)),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    items:
                        const [
                          'General',
                          'Unclassified',
                          'Internal Use Only',
                          'Corporate Confidential',
                          'Restricted',
                          'Confidential',
                          'Secret',
                        ].map((classification) {
                          return DropdownMenuItem(
                            value: classification,
                            child: Text(classification),
                          );
                        }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedClassification = value;
                        });
                      }
                    },
                  ),

                  SizedBox(height: r.p(16)),

                  // Keywords Text Field
                  TextField(
                    controller: _keywordsController,
                    decoration: InputDecoration(
                      labelText: 'Keywords',
                      hintText: 'Enter keywords separated by commas',
                      prefixIcon: const Icon(Icons.label, color: Colors.indigo),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(r.p(8)),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),

                  SizedBox(height: r.p(16)),

                  // Remarks Description Box
                  TextField(
                    controller: _remarksController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Remarks',
                      hintText: 'Enter description or remarks',
                      prefixIcon: const Icon(
                        Icons.description,
                        color: Colors.indigo,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(r.p(8)),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      alignLabelWithHint: true,
                    ),
                  ),

                  SizedBox(height: r.p(16)),

                  SizedBox(height: r.p(16)),

                  // Sharing Type Dropdown
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _selectedSharingType,
                    decoration: InputDecoration(
                      labelText: 'Sharing',
                      prefixIcon: const Icon(Icons.share, color: Colors.indigo),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(r.p(8)),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'Public',
                        child: Row(
                          children: [
                            Icon(
                              Icons.public,
                              color: Colors.green,
                              size: r.sp(18),
                            ),
                            SizedBox(width: r.p(10)),
                            Expanded(
                              child: Text(
                                'Public - Visible in Document Library',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'Private',
                        child: Row(
                          children: [
                            Icon(Icons.lock, color: Colors.red, size: r.sp(18)),
                            SizedBox(width: r.p(10)),
                            Expanded(
                              child: Text(
                                'Private - Only in My Documents',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'Specific Users',
                        child: Row(
                          children: [
                            Icon(
                              Icons.group,
                              color: Colors.indigo,
                              size: r.sp(18),
                            ),
                            SizedBox(width: r.p(10)),
                            Expanded(
                              child: Text(
                                'Share with Specific Users',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedSharingType = value;
                          if (_selectedSharingType == 'Public') {
                            _shareWithSpecificUsers = false;
                            _specificUserIds.clear();
                          } else if (_selectedSharingType == 'Private') {
                            _shareWithSpecificUsers = false;
                            _specificUserIds.clear();
                          } else if (_selectedSharingType == 'Specific Users') {
                            _shareWithSpecificUsers = true;
                          }
                        });

                        if (value == 'Specific Users') {
                          WidgetsBinding.instance.addPostFrameCallback((
                            _,
                          ) async {
                            if (!mounted) return;
                            await _pickSpecificUsers();
                            if (!mounted) return;
                            if (_specificUserIds.isEmpty) {
                              setState(() {
                                _selectedSharingType = 'Private';
                                _shareWithSpecificUsers = false;
                              });
                            }
                          });
                        }
                      }
                    },
                  ),

                  SizedBox(height: r.p(32)),

                  if (_selectedSharingType == 'Private') ...[
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _shareWithSpecificUsers,
                      onChanged: (v) async {
                        setState(() {
                          _shareWithSpecificUsers = v;
                          if (!v) {
                            _specificUserIds.clear();
                          }
                        });
                        if (v) {
                          await _pickSpecificUsers();
                        }
                      },
                      title: const Text('Share with Specific Users'),
                      subtitle: Text(
                        _specificUserIds.isEmpty
                            ? 'Optional: limit access to selected users'
                            : '${_specificUserIds.length} user(s) selected',
                      ),
                    ),
                    if (_shareWithSpecificUsers)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _pickSpecificUsers,
                          icon: const Icon(Icons.group_add),
                          label: const Text('Select users'),
                        ),
                      ),
                    SizedBox(height: r.p(12)),
                  ],

                  if (_selectedSharingType == 'Specific Users') ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.group, color: Colors.indigo),
                      title: const Text('Share with Specific Users'),
                      subtitle: Text(
                        _specificUserIds.isEmpty
                            ? 'Select users who can access this document'
                            : '${_specificUserIds.length} user(s) selected',
                      ),
                      trailing: TextButton(
                        onPressed: _pickSpecificUsers,
                        child: const Text('Change'),
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _pickSpecificUsers,
                        icon: const Icon(Icons.group_add),
                        label: const Text('Select users'),
                      ),
                    ),
                    SizedBox(height: r.p(12)),
                  ],

                  SizedBox(height: r.p(16)),

                  // Upload Document Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (_isLoading || _foldersLoading)
                          ? null
                          : _uploadDocument,
                      icon: Icon(Icons.cloud_upload, size: r.sp(24)),
                      label: _isLoading
                          ? SizedBox(
                              width: r.p(20),
                              height: r.p(20),
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Text(
                              'Upload Document',
                              style: TextStyle(
                                fontSize: r.sp(18),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: r.p(16)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(r.p(12)),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                  SizedBox(height: r.p(24)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
