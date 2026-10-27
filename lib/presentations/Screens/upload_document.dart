// ignore_for_file: use_build_context_synchronously, unnecessary_this
import 'package:digi_sanchika/local_storage.dart';
import 'package:digi_sanchika/widgets/file_type_icon.dart';
import 'package:digi_sanchika/theme/ui_theme.dart';
import 'package:digi_sanchika/widgets/folder_illustration.dart';
import 'package:digi_sanchika/widgets/home_components.dart' show PillSearchField;
import 'package:digi_sanchika/utils/responsive_helper.dart';
import 'package:digi_sanchika/utils/design_tokens.dart';
import 'package:digi_sanchika/services/upload_service.dart';
import 'package:digi_sanchika/services/folder_helper.dart';
import 'package:digi_sanchika/services/folder_operations_service.dart';
import 'package:digi_sanchika/models/folder_tree_node.dart';
import 'package:digi_sanchika/services/folder_tree_service.dart'; // ADD THIS
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:digi_sanchika/models/document.dart';
import 'package:digi_sanchika/models/folder.dart';
import 'package:digi_sanchika/services/my_documents_service.dart';
import 'package:digi_sanchika/services/document_library_service.dart';
import 'package:digi_sanchika/services/shares_service.dart';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
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

  // Upload type: null = none selected, 'files' | 'folder' | 'zip'
  String? _selectedUploadType;

  String _selectedFolder = '';
  String _selectedClassification = 'General';
  bool _classificationOpen = false;
  bool _allowDownload = true;
  String _selectedSharingType = 'Public';
  final List<PlatformFile> _uploadedFiles = [];
  // Local file path -> folder path (relative to the destination) for files
  // that came from a folder or ZIP pick, so the hierarchy can be recreated.
  final Map<String, String> _fileRelDirs = {};
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

  /// Creates a folder inside the current destination (or at root) from the
  /// picker sheet, then makes it the destination.
  Future<bool> _createFolderFromPicker(BuildContext sheetContext) async {
    final controller = TextEditingController();
    final parentName = _selectedFolderId == null
        ? 'Root'
        : (_selectedFolderName ?? 'selected folder');
    final name = await showDialog<String>(
      context: sheetContext,
      builder: (ctx) => AlertDialog(
        title: const Text('New folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: 'Folder name',
            helperText: 'Created in $parentName',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return false;

    final result = await MyDocumentsService.createFolder(
      folderName: name,
      parentFolderId: _selectedFolderId,
    );
    if (!mounted) return false;
    if (result['success'] != true) {
      _showErrorSnackBar(
        (result['error'] ?? 'Failed to create folder').toString(),
      );
      return false;
    }
    final folder = result['folder'] as Folder;
    await _loadFolders();
    if (!mounted) return false;
    setState(() {
      _selectedFolderId = folder.id;
      _selectedFolderName = folder.name;
    });
    return true;
  }

  // NEW STATE VARIABLES FOR MODAL (add these to your state class)
  List<FolderTreeNode> _filteredFolders = [];
  Map<String, bool> _expandedFolders = {}; // Tracks which folders are expanded
  final Map<String, bool> _loadingFolderChildren =
      {}; // Lazy-load child folders
  String _searchQuery = '';

  // NEW METHOD: Show folder selector in a modal bottom sheet
  Future<void> _showFolderSelector(BuildContext context) async {
    final searchController = TextEditingController();

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
                                        color: UiColors.primaryActive,
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
                                tooltip: 'New folder',
                                icon: const Icon(
                                  Icons.create_new_folder_outlined,
                                  color: UiColors.primary,
                                ),
                                onPressed: () async {
                                  final created =
                                      await _createFolderFromPicker(context);
                                  if (created && context.mounted) {
                                    Navigator.pop(context);
                                  }
                                },
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

                    // Search bar (same pill as the rest of the app)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        r.p(16),
                        r.p(4),
                        r.p(16),
                        r.p(10),
                      ),
                      child: PillSearchField(
                        controller: searchController,
                        hint: 'Search folders',
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
                        onClear: () {
                          searchController.clear();
                          setModalState(() {
                            _searchQuery = '';
                            _filteredFolders = List.from(_folderTree);
                          });
                        },
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
                            width: r.p(42),
                            height: r.p(42),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF3FF),
                              borderRadius: BorderRadius.circular(r.p(13)),
                            ),
                            child: FolderIllustration(size: r.p(30)),
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
                              // Same blue as the folder artwork.
                              backgroundColor: UiColors.primaryActive,
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
    searchController.dispose();
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
          ? UiColors.primaryTint
          : (isExpanded ? Colors.grey.withValues(alpha: 0.06) : baseBg);
      final borderColor = isSelected
          ? UiColors.primary.withAlpha(110)
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
                    // Tapping the selected folder again goes back to Root.
                    setState(() {
                      _selectedFolder = isSelected ? '' : node.name;
                      _selectedFolderName = isSelected ? null : node.name;
                      _selectedFolderId = isSelected ? null : node.id;
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
                        // Same folder artwork as the folder cards.
                        Container(
                          width: r.p(38),
                          height: r.p(38),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF3FF),
                            borderRadius: BorderRadius.circular(r.p(12)),
                          ),
                          child: FolderIllustration(size: r.p(28)),
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
                                      ? UiColors.primaryActive
                                      : Colors.grey.shade900,
                                ),
                              ),
                              SizedBox(height: r.p(2)),
                              Text(
                                () {
                                  if (isLoadingChildren) {
                                    return 'Loading subfolders…';
                                  }
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
                                      ? UiColors.primaryActive
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
                              _selectedFolder = isSelected ? '' : node.name;
                              _selectedFolderName =
                                  isSelected ? null : node.name;
                              _selectedFolderId = isSelected ? null : node.id;
                            });
                            setModalState(() {});
                          },
                          child: Icon(
                            isSelected
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_off_rounded,
                            color: isSelected
                                ? UiColors.primary
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
        // Folder / ZIP picks: recreate the directory tree, then upload each
        // file into its own folder instead of flattening everything.
        final hierarchy = await _resolveHierarchy(files);
        if (hierarchy.isNotEmpty) {
          uploadResult = await _uploadGrouped(
            files: files,
            hierarchy: hierarchy,
            defaultFolderId: folderId,
            keywords: keywords,
            remarks: remarks,
            docClass: apiClassification,
          );
        } else if (_uploadedFiles.length == 1) {
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
    if (employeeId.isNotEmpty && email.isNotEmpty) {
      return '$employeeId • $email';
    }
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
      _fileRelDirs.clear();
      _keywordsController.clear();
      _remarksController.clear();
      _selectedClassification = 'General';
      _classificationOpen = false;
      _allowDownload = true;
      _selectedSharingType = 'Public';

      // Reset folder selection
      _selectedFolder = '';
      _selectedFolderName = null;
      _selectedFolderId = null;
    });
  }

  // ============ FILE PICKER METHODS ============
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

  // ── Folder / ZIP picking (hierarchy-preserving) ─────────────────────────────
  static const _maxFileBytes = 500 * 1024 * 1024;

  String _baseName(String path) =>
      path.split(RegExp(r'[\\/]')).where((e) => e.isNotEmpty).last;

  bool _isJunkEntry(String rel) {
    for (final seg in rel.split('/')) {
      if (seg == '__MACOSX' ||
          seg == '.DS_Store' ||
          seg == 'Thumbs.db' ||
          seg == 'desktop.ini') {
        return true;
      }
    }
    return false;
  }

  /// Adds [entries] (file + path relative to the picked root) to the upload
  /// list and remembers each file's folder so it can be recreated on submit.
  Future<({int added, int skipped})> _registerHierarchicalFiles(
    String rootName,
    List<({File file, String rel})> entries,
  ) async {
    var added = 0;
    var skipped = 0;
    for (final e in entries) {
      if (_uploadedFiles.any((f) => f.path == e.file.path)) continue;
      final parts = e.rel.split('/');
      final size = await e.file.length();
      if (size > _maxFileBytes) {
        skipped++;
        continue;
      }
      final dir = [rootName, ...parts.sublist(0, parts.length - 1)].join('/');
      _uploadedFiles.add(
        PlatformFile(path: e.file.path, name: parts.last, size: size),
      );
      _fileRelDirs[e.file.path] = dir;
      added++;
    }
    if (mounted) setState(() {});
    return (added: added, skipped: skipped);
  }

  void _toast(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  Future<void> _pickFolder() async {
    setState(() => _isLoading = true);
    try {
      final dirPath = await FilePicker.platform.getDirectoryPath();
      if (dirPath == null) return;

      final rootDir = Directory(dirPath);
      final rootName = _baseName(dirPath);

      final entries = <({File file, String rel})>[];
      for (final e in rootDir.listSync(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        final rel = e.path
            .substring(rootDir.path.length)
            .replaceAll('\\', '/')
            .replaceFirst(RegExp(r'^/+'), '');
        if (rel.isEmpty || _isJunkEntry(rel)) continue;
        entries.add((file: e, rel: rel));
      }

      if (entries.isEmpty) {
        _toast('No files found in selected folder', Colors.orange);
        return;
      }

      final res = await _registerHierarchicalFiles(rootName, entries);
      if (res.added > 0) {
        _toast(
          'Added ${res.added} file(s) from "$rootName"'
          '${res.skipped > 0 ? ' (${res.skipped} over 500MB skipped)' : ''}',
          Colors.green,
        );
      }
    } catch (e) {
      _toast('Folder pick error: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickZip() async {
    setState(() => _isLoading = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final zipPath = result.files.single.path;
      if (zipPath == null) {
        _toast('Could not read the selected ZIP file', Colors.red);
        return;
      }

      final zipName = _baseName(
        zipPath,
      ).replaceAll(RegExp(r'\.zip$', caseSensitive: false), '');
      final archive = ZipDecoder().decodeBytes(
        await File(zipPath).readAsBytes(),
      );

      final tmp = await getTemporaryDirectory();
      final outDir = Directory(
        '${tmp.path}${Platform.pathSeparator}zip_${DateTime.now().millisecondsSinceEpoch}',
      );
      await outDir.create(recursive: true);

      final entries = <({File file, String rel})>[];
      for (final af in archive) {
        if (!af.isFile) continue;
        final rel = af.name
            .replaceAll('\\', '/')
            .replaceFirst(RegExp(r'^/+'), '');
        // Skip junk and guard against path traversal ("zip-slip").
        if (rel.isEmpty || rel.split('/').contains('..') || _isJunkEntry(rel)) {
          continue;
        }
        final out = File('${outDir.path}/$rel');
        await out.parent.create(recursive: true);
        await out.writeAsBytes(af.content as List<int>);
        entries.add((file: out, rel: rel));
      }

      if (entries.isEmpty) {
        _toast('The ZIP archive contains no usable files', Colors.orange);
        return;
      }

      final res = await _registerHierarchicalFiles(zipName, entries);
      _toast(
        'Extracted ${res.added} file(s) from "$zipName.zip"'
        '${res.skipped > 0 ? ' (${res.skipped} over 500MB skipped)' : ''}',
        Colors.green,
      );
    } catch (e) {
      _toast('Could not read ZIP: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Creates the folder tree for folder/ZIP picks under the chosen
  /// destination and returns local file path -> destination folder id.
  /// Files whose folder could not be created are left out (they fall back to
  /// the destination folder).
  Future<Map<String, String>> _resolveHierarchy(List<File> files) async {
    final dirs = <String>{};
    for (final f in files) {
      final d = _fileRelDirs[f.path];
      if (d == null) continue;
      final parts = d.split('/');
      for (var i = 0; i < parts.length; i++) {
        dirs.add(parts.sublist(0, i + 1).join('/'));
      }
    }
    if (dirs.isEmpty) return {};

    final ordered = dirs.toList()
      ..sort((a, b) {
        final c = a.split('/').length.compareTo(b.split('/').length);
        return c != 0 ? c : a.compareTo(b);
      });
    final payload = ordered
        .map(
          (d) => {
            'name': d.split('/').last,
            'path': d,
            'parentId': _selectedFolderId,
          },
        )
        .toList();

    final result = await FolderOperationsService().bulkCreateFolders(payload);
    final pathToId = <String, String>{};
    if (result['success'] == true) {
      final data = result['data'];
      final created = data is Map ? (data['folders'] ?? data['data']) : data;
      if (created is List) {
        for (final f in created) {
          if (f is! Map) continue;
          final id = f['id']?.toString() ?? '';
          final path = f['path']?.toString() ?? '';
          if (id.isNotEmpty && path.isNotEmpty) pathToId[path] = id;
        }
        // Backend did not echo paths: assume it answered in request order.
        if (pathToId.length < ordered.length &&
            created.length == ordered.length) {
          for (var i = 0; i < created.length; i++) {
            final f = created[i];
            final id = f is Map ? f['id']?.toString() ?? '' : '';
            if (id.isNotEmpty) pathToId.putIfAbsent(ordered[i], () => id);
          }
        }
      }
    }

    final out = <String, String>{};
    var missing = 0;
    for (final f in files) {
      final d = _fileRelDirs[f.path];
      if (d == null) continue;
      final id = pathToId[d];
      if (id != null) {
        out[f.path] = id;
      } else {
        missing++;
      }
    }
    if (missing > 0) {
      _toast(
        'Could not create some folders - $missing file(s) will go to the '
        'destination folder instead.',
        Colors.orange,
      );
    }
    return out;
  }

  /// Uploads [files] one folder at a time and merges the per-file results.
  Future<Map<String, dynamic>> _uploadGrouped({
    required List<File> files,
    required Map<String, String> hierarchy,
    required String defaultFolderId,
    required String keywords,
    required String remarks,
    required String docClass,
  }) async {
    final groups = <String, List<File>>{};
    for (final f in files) {
      groups
          .putIfAbsent(hierarchy[f.path] ?? defaultFolderId, () => [])
          .add(f);
    }

    final allResults = <Map<String, dynamic>>[];
    var requiresLogin = false;
    String? message;
    dynamic status;
    dynamic error;

    for (final entry in groups.entries) {
      final group = entry.value;
      final res = group.length == 1
          ? await UploadService.uploadSingleFile(
              file: group.first,
              keywords: keywords,
              remarks: remarks,
              docClass: docClass,
              allowDownload: _allowDownload,
              folderId: entry.key,
              sharing: 'private',
              specificUsers: '[]',
            )
          : await UploadService.uploadMultipleFiles(
              files: group,
              keywords: keywords,
              remarks: remarks,
              docClass: docClass,
              allowDownload: _allowDownload,
              folderId: entry.key,
              sharing: 'private',
              specificUsers: '[]',
            );

      if (res['requiresLogin'] == true) requiresLogin = true;
      final ok = res['success'] == true;
      final rawResults = res['file_results'];
      if (rawResults is List && rawResults.isNotEmpty) {
        for (final m in rawResults.whereType<Map>()) {
          allResults.add(Map<String, dynamic>.from(m));
        }
      } else {
        for (final f in group) {
          allResults.add({
            'fileName': _baseName(f.path),
            'success': ok,
            'error': res['message'] ?? 'Upload failed',
            if (res['documentId'] != null) 'documentId': res['documentId'],
          });
        }
      }
      if (!ok) {
        message = res['message']?.toString();
        status = res['statusCode'];
        error = res['error'];
      }
    }

    final anyOk = allResults.any((r) => r['success'] == true);
    return {
      'success':
          allResults.isNotEmpty && allResults.every((r) => r['success'] == true),
      'file_results': allResults,
      'message': message ?? (anyOk ? 'Uploaded' : 'Upload failed'),
      'statusCode': status,
      'error': error,
      'requiresLogin': requiresLogin && !anyOk,
    };
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

  void _onSharingChanged(String value) {
    setState(() {
      _selectedSharingType = value;
      if (value == 'Specific Users') {
        _shareWithSpecificUsers = true;
      } else {
        _shareWithSpecificUsers = false;
        _specificUserIds.clear();
      }
    });

    if (value == 'Specific Users') {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
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

  // ============ BUILD METHOD ============
  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final layout = AppLayout.of(context);
    return Scaffold(
      backgroundColor: UiColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: UiColors.ink),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Text(
          'Upload Documents',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: UiColors.ink,
          ),
        ),
        backgroundColor: UiColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      bottomNavigationBar: _buildSubmitBar(r),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          layout.gutter,
          r.p(8),
          layout.gutter,
          r.p(24),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: layout.maxContentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildUploadTypeCard(r),
                SizedBox(height: r.p(14)),
                _buildDropzone(r),
                SizedBox(height: r.p(24)),

                _sectionLabel('Classification', r, required: true),
                SizedBox(height: r.p(10)),
                _buildClassificationField(),
                SizedBox(height: r.p(24)),

                _sectionLabel('Document Visibility', r, required: true),
                SizedBox(height: r.p(10)),
                _visibilityCard(
                  r: r,
                  value: 'Private',
                  icon: Icons.lock_outline_rounded,
                  title: 'Private',
                  subtitle: 'Only you can access this document',
                ),
                _visibilityCard(
                  r: r,
                  value: 'Public',
                  icon: Icons.public_rounded,
                  title: 'Public',
                  subtitle:
                      'Listed in the Document Library under its public-access rules',
                ),
                _visibilityCard(
                  r: r,
                  value: 'Specific Users',
                  icon: Icons.group_outlined,
                  title: 'Specific Users',
                  subtitle: _specificUserIds.isEmpty
                      ? 'Only the users you choose can access it'
                      : '${_specificUserIds.length} user(s) selected - tap to change',
                ),
                SizedBox(height: r.p(12)),

                _sectionLabel('Destination Folder', r, required: true),
                SizedBox(height: r.p(10)),
                _buildDestinationCard(r),
                SizedBox(height: r.p(24)),

                _sectionLabel('Additional Details', r),
                SizedBox(height: r.p(10)),
                TextField(
                  controller: _keywordsController,
                  decoration: _fieldDecoration(
                    hint: 'Keywords (separated by commas)',
                    icon: Icons.label_important_outline,
                  ),
                ),
                SizedBox(height: r.p(12)),
                TextField(
                  controller: _remarksController,
                  maxLines: 2,
                  decoration: _fieldDecoration(
                    hint: 'Remarks or description',
                    icon: Icons.description_outlined,
                    alignHint: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Small building blocks ──────────────────────────────────────────────────
  Widget _sectionLabel(String text, ResponsiveHelper r, {bool required = false}) {
    return Text.rich(
      TextSpan(
        text: text,
        children: [
          if (required)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: Color(0xFFE11D48)),
            ),
        ],
      ),
      style: TextStyle(
        fontSize: r.sp(18),
        fontWeight: FontWeight.w600,
        color: UiColors.ink,
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    bool alignHint = false,
  }) {
    OutlineInputBorder border([Color c = UiColors.border]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: c),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: UiColors.textMuted),
      prefixIcon: Icon(icon, color: UiColors.primary),
      filled: true,
      fillColor: Colors.white,
      alignLabelWithHint: alignHint,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: border(),
      enabledBorder: border(),
      focusedBorder: border(UiColors.primary),
    );
  }

  Widget _card({required Widget child, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: UiColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  // ── "What do you want to upload?" ──────────────────────────────────────────
  Widget _buildUploadTypeCard(ResponsiveHelper r) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What do you want to upload?',
            style: TextStyle(
              fontSize: r.sp(17),
              fontWeight: FontWeight.w600,
              color: UiColors.ink,
            ),
          ),
          SizedBox(height: r.p(14)),
          Row(
            children: [
              _buildUploadTypeOption(
                r: r,
                type: 'files',
                icon: Icons.file_copy_outlined,
                label: 'Files',
                caption: 'One or many',
              ),
              SizedBox(width: r.p(10)),
              _buildUploadTypeOption(
                r: r,
                type: 'folder',
                icon: Icons.drive_folder_upload_outlined,
                label: 'Folder',
                caption: 'Keeps subfolders',
              ),
              SizedBox(width: r.p(10)),
              _buildUploadTypeOption(
                r: r,
                type: 'zip',
                icon: Icons.folder_zip_outlined,
                label: 'ZIP',
                caption: 'Auto-extracted',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUploadTypeOption({
    required ResponsiveHelper r,
    required String type,
    required IconData icon,
    required String label,
    required String caption,
  }) {
    final isSelected = _selectedUploadType == type;
    return Expanded(
      child: GestureDetector(
        onTap: _isLoading
            ? null
            : () {
                setState(() {
                  _selectedUploadType = type;
                  // Clear previously picked files when type changes
                  _uploadedFiles.clear();
                  _fileRelDirs.clear();
                });
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
            vertical: r.p(14),
            horizontal: r.p(8),
          ),
          decoration: BoxDecoration(
            color: isSelected ? UiColors.primaryTint : const Color(0xFFF8FAFF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected ? UiColors.primary : UiColors.border,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: r.p(44),
                height: r.p(44),
                decoration: BoxDecoration(
                  color: isSelected
                      ? UiColors.primary
                      : UiColors.primary.withAlpha(22),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  size: r.sp(24),
                  color: isSelected ? Colors.white : UiColors.primary,
                ),
              ),
              SizedBox(height: r.p(8)),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: r.sp(14),
                  fontWeight: FontWeight.w600,
                  color: UiColors.ink,
                ),
              ),
              SizedBox(height: r.p(2)),
              Text(
                caption,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: r.sp(11.5),
                  color: UiColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Selection / drop zone ──────────────────────────────────────────────────
  Future<void> _onDropzoneTap() async {
    if (_isLoading) return;
    if (_selectedUploadType == null) {
      _toast('Choose what you want to upload first', Colors.orange);
      return;
    }
    await _triggerFilePicker();
  }

  Widget _buildDropzone(ResponsiveHelper r) {
    final hasFiles = _uploadedFiles.isNotEmpty;
    return _card(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: _onDropzoneTap,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: r.p(16),
                vertical: r.p(22),
              ),
              child: Column(
                children: [
                  _isLoading
                      ? SizedBox(
                          width: r.p(36),
                          height: r.p(36),
                          child: const CircularProgressIndicator(strokeWidth: 3),
                        )
                      : Icon(
                          Icons.cloud_upload_outlined,
                          size: r.sp(44),
                          color: const Color(0xFF475569),
                        ),
                  SizedBox(height: r.p(10)),
                  Text(
                    hasFiles
                        ? '${_uploadedFiles.length} file(s) selected'
                        : 'Nothing selected yet',
                    style: TextStyle(
                      fontSize: r.sp(17),
                      fontWeight: FontWeight.w600,
                      color: UiColors.ink,
                    ),
                  ),
                  SizedBox(height: r.p(6)),
                  Text(
                    hasFiles
                        ? 'Tap here to choose again'
                        : 'PDF, Word, Excel, PowerPoint, images, audio and video.\nUp to 500 MB per file.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: r.sp(13),
                      height: 1.4,
                      color: UiColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (hasFiles) ...[
            const Divider(height: 1, color: UiColors.border),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: r.hp(0.32)),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.symmetric(vertical: r.p(6)),
                itemCount: _uploadedFiles.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 16, endIndent: 16),
                itemBuilder: (context, i) {
                  final file = _uploadedFiles[i];
                  final dir = _fileRelDirs[file.path];
                  return ListTile(
                    dense: true,
                    leading: FileTypeIcon.orElse(
                      file.name,
                      30,
                      Icon(
                        _getFileIcon(file.name),
                        color: _getFileColor(file.name),
                      ),
                    ),
                    title: Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${file.extension?.toUpperCase() ?? _baseName(file.name).split('.').last.toUpperCase()}'
                      ' \u2022 ${_getFileSizeString(file.size)}'
                      '${dir != null ? ' \u2022 $dir' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      color: Colors.red,
                      onPressed: () => setState(() {
                        _fileRelDirs.remove(file.path);
                        _uploadedFiles.remove(file);
                      }),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Classification (inline expanding list) ────────────────────────────────
  static const _classificationOptions = <({String value, String hint, Color color})>[
    (value: 'General', hint: 'Everyday document, no special handling', color: Color(0xFF16A34A)),
    (value: 'Unclassified', hint: 'No sensitivity rating assigned', color: Color(0xFF64748B)),
    (value: 'Internal Use Only', hint: 'Standard business document', color: Color(0xFF2563EB)),
    (value: 'Corporate Confidential', hint: 'Sensitive, share only inside the company', color: Color(0xFFB45309)),
    (value: 'Restricted', hint: 'Limited audience, handle with care', color: Color(0xFFEA580C)),
    (value: 'Confidential', hint: 'Important, handle with priority', color: Color(0xFF7C3AED)),
    (value: 'Secret', hint: 'Business critical, restricted handling', color: Color(0xFFE11D48)),
  ];

  Widget _buildClassificationField() {
    final open = _classificationOpen;
    final current = _classificationOptions.firstWhere(
      (o) => o.value == _selectedClassification,
      orElse: () => _classificationOptions.first,
    );
    final hasValue = _selectedClassification.isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: open ? UiColors.primary : UiColors.border,
          width: open ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => setState(() => _classificationOpen = !open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
              child: Row(
                children: [
                  const Icon(Icons.label_outline, color: UiColors.primary),
                  const SizedBox(width: 14),
                  if (hasValue) ...[
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: current.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      hasValue ? current.value : 'Select a classification',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
                        color: hasValue ? UiColors.ink : UiColors.textMuted,
                      ),
                    ),
                  ),
                  Icon(
                    open
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: UiColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: open
                ? Column(
                    children: [
                      const Divider(height: 1, color: UiColors.border),
                      for (final o in _classificationOptions)
                        InkWell(
                          onTap: () => setState(() {
                            _selectedClassification = o.value;
                            _classificationOpen = false;
                          }),
                          child: Container(
                            color: o.value == _selectedClassification
                                ? UiColors.primaryTint
                                : null,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: o.color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 18),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        o.value,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: UiColors.ink,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        o.hint,
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          color: UiColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (o.value == _selectedClassification)
                                  const Icon(
                                    Icons.check_rounded,
                                    color: UiColors.primary,
                                    size: 20,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 6),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  // ── Visibility radio cards ─────────────────────────────────────────────────
  Widget _visibilityCard({
    required ResponsiveHelper r,
    required String value,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = _selectedSharingType == value;
    return Padding(
      padding: EdgeInsets.only(bottom: r.p(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          if (selected && value == 'Specific Users') {
            _pickSpecificUsers();
          } else if (!selected) {
            _onSharingChanged(value);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: EdgeInsets.all(r.p(14)),
          decoration: BoxDecoration(
            color: selected ? UiColors.primaryTint : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? UiColors.primary : UiColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: r.p(48),
                height: r.p(48),
                decoration: BoxDecoration(
                  color: selected
                      ? UiColors.primary
                      : UiColors.primary.withAlpha(22),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: selected ? Colors.white : UiColors.primary,
                ),
              ),
              SizedBox(width: r.p(14)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: r.sp(17),
                        fontWeight: FontWeight.w600,
                        color: UiColors.ink,
                      ),
                    ),
                    SizedBox(height: r.p(2)),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: r.sp(13),
                        color: UiColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: r.p(8)),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: r.sp(28),
                color: selected ? UiColors.primary : const Color(0xFF64748B),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Destination folder ─────────────────────────────────────────────────────
  /// One tappable row: opens the folder picker (which can also create a
  /// folder). The subtitle shows where the upload will go.
  Widget _buildDestinationCard(ResponsiveHelper r) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: _foldersLoading ? null : () => _showFolderSelector(context),
        child: _card(
          padding: EdgeInsets.symmetric(
            horizontal: r.p(16),
            vertical: r.p(14),
          ),
          child: Row(
            children: [
              Container(
                width: r.p(48),
                height: r.p(48),
                decoration: BoxDecoration(
                  color: UiColors.primary.withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.drive_file_move_outline,
                  color: UiColors.primary,
                  size: r.sp(24),
                ),
              ),
              SizedBox(width: r.p(14)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select Destination Folder',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: r.sp(16),
                        fontWeight: FontWeight.w700,
                        color: UiColors.ink,
                      ),
                    ),
                    SizedBox(height: r.p(2)),
                    Text(
                      _selectedFolderId == null
                          ? 'Root'
                          : (_selectedFolderName ?? 'Selected folder'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: r.sp(14),
                        color: UiColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              _foldersLoading
                  ? SizedBox(
                      width: r.p(20),
                      height: r.p(20),
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.chevron_right_rounded,
                      color: UiColors.muted,
                    ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Submit bar ─────────────────────────────────────────────────────────────
  Widget _buildSubmitBar(ResponsiveHelper r) {
    return Container(
      color: UiColors.background,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(r.p(16), r.p(8), r.p(16), r.p(12)),
          child: SizedBox(
            width: double.infinity,
            height: r.p(56),
            child: ElevatedButton.icon(
              onPressed: (_isLoading || _foldersLoading)
                  ? null
                  : _uploadDocument,
              icon: _isLoading
                  ? const SizedBox.shrink()
                  : Icon(Icons.cloud_upload_outlined, size: r.sp(24)),
              label: _isLoading
                  ? SizedBox(
                      width: r.p(22),
                      height: r.p(22),
                      child: const CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      'Submit Document',
                      style: TextStyle(
                        fontSize: r.sp(18),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
              style: ElevatedButton.styleFrom(
                backgroundColor: UiColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: UiColors.primary.withAlpha(150),
                disabledForegroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                shadowColor: UiColors.primary.withValues(alpha: 0.4),
                elevation: 6,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Dispatch to the right picker ──────────────────────────────────────────
  Future<void> _triggerFilePicker() async {
    switch (_selectedUploadType) {
      case 'files':
        // Multi-select picker; picking a single file works the same way.
        await _pickMultipleFiles();
        break;
      case 'folder':
        await _pickFolder();
        break;
      case 'zip':
        await _pickZip();
        break;
    }
  }
}

// ── Dotted browse tile widget ─────────────────────────────────────────────────
class DottedBrowseTile extends StatelessWidget {
  final ResponsiveHelper r;
  final bool isLoading;

  const DottedBrowseTile({super.key, required this.r, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: r.p(28)),
      decoration: BoxDecoration(
        color: UiColors.primaryTint,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: UiColors.brightBlue,
          width: 1.5,
          // Dashed effect via custom painter below
        ),
      ),
      child: isLoading
          ? Center(
              child: SizedBox(
                width: r.p(24),
                height: r.p(24),
                child: const CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: r.p(48),
                  height: r.p(48),
                  decoration: BoxDecoration(
                    color: UiColors.iceBlue,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.upload_outlined,
                    size: r.sp(26),
                    color: UiColors.primary,
                  ),
                ),
                SizedBox(height: r.p(12)),
                Text(
                  'Tap to browse files',
                  style: TextStyle(
                    fontSize: r.sp(15),
                    fontWeight: FontWeight.w600,
                    color: UiColors.primaryActive,
                  ),
                ),
                SizedBox(height: r.p(4)),
                Text(
                  'PDF, DOCX, XLSX, PPTX up to 50 MB',
                  style: TextStyle(
                    fontSize: r.sp(12),
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
    );
  }
}