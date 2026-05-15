// lib/presentations/screens/folder_manager_screen.dart

import 'package:flutter/material.dart';
import 'package:digi_sanchika/widgets/dismiss_keyboard.dart';
import 'package:digi_sanchika/models/folder_tree_node.dart';
import 'package:digi_sanchika/services/folder_tree_service.dart';
import 'package:digi_sanchika/services/folder_operations_service.dart';
import 'package:digi_sanchika/widgets/folder_tree_widget.dart';
import 'package:digi_sanchika/widgets/breadcrumb_widget.dart';
import 'package:digi_sanchika/utils/app_theme.dart';

class FolderManagerScreen extends StatefulWidget {
  final String? userName;

  const FolderManagerScreen({super.key, this.userName});

  @override
  State<FolderManagerScreen> createState() => _FolderManagerScreenState();
}

class _FolderManagerScreenState extends State<FolderManagerScreen> {
  final FolderTreeService _treeService = FolderTreeService();
  final FolderOperationsService _opsService = FolderOperationsService();
  final TextEditingController _folderNameController = TextEditingController();

  List<FolderTreeNode> _rootFolders = [];
  FolderTreeNode? _currentFolder;
  List<FolderTreeNode> _breadcrumbPath = [];
  bool _isLoading = true;
  bool _isGridView = false;
  bool _didChange = false; // Used to notify previous screen to refresh.
  // ignore: unused_field
  final String _searchQuery = '';
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();
  final TextEditingController _searchController = TextEditingController();
  String _folderSearch = '';

  @override
  void initState() {
    super.initState();
    _loadFolderTree();
  }

  @override
  void dispose() {
    _folderNameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<FolderTreeNode> _filterFoldersForGrid(List<FolderTreeNode> input) {
    final q = _folderSearch.trim().toLowerCase();
    if (q.isEmpty) return input;
    return input
        .where((n) => n.name.toLowerCase().contains(q))
        .toList(growable: false);
  }

  Future<void> _loadFolderTree({bool showLoading = true}) async {
    if (showLoading) {
      setState(() => _isLoading = true);
    }

    try {
      final tree = await _treeService.fetchFolderTree(forceRefresh: true);

      setState(() {
        _rootFolders = tree;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackBar('Failed to load folders: $e');
    }
  }

  Future<void> _navigateToFolder(FolderTreeNode? folder) async {
    if (folder == null) {
      setState(() {
        _currentFolder = null;
        _treeService.navigateToRoot();
        _breadcrumbPath = [];
      });
      return;
    }

    // Make sure the tapped folder expands so its children are visible in list view.
    setState(() {
      _currentFolder = folder;
      folder.isExpanded = true;
      _treeService.navigateToFolder(folder);
      _breadcrumbPath = folder.getPath(_rootFolders);
      _isLoading = true;
    });

    // `/folders` often returns only root folders. Load direct children via `/documents?folderId=...`.
    final children = await _treeService.fetchChildFolders(parent: folder);

    if (!mounted) return;
    setState(() {
      folder.children
        ..clear()
        ..addAll(children);
      _isLoading = false;
    });
  }

  Future<void> _createFolder([FolderTreeNode? parent]) async {
    _folderNameController.clear();

    final result = await showDialog<String>(
      context: context,
      builder: (context) => _buildCreateFolderDialog(parent),
    );

    if (result != null && result.isNotEmpty) {
      setState(() => _isLoading = true);

      final createResult = await _opsService.createFolder(
        name: result,
        parentId: parent?.id,
      );

      if (createResult['success'] == true) {
        _didChange = true;
        _showSuccessSnackBar('Folder "${result}" created successfully');
        await _loadFolderTree(showLoading: false);
      } else {
        _showErrorSnackBar(createResult['error'] ?? 'Failed to create folder');
      }

      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteFolder(FolderTreeNode node) async {
    final confirmed = await _showDeleteConfirmation(node);

    if (confirmed == true) {
      setState(() => _isLoading = true);

      final result = await _opsService.deleteFolder(node.id);

      if (result['success'] == true) {
        _didChange = true;
        _showSuccessSnackBar('Folder "${node.name}" deleted successfully');

        // Navigate to parent if current folder was deleted
        if (_currentFolder?.id == node.id) {
          _navigateToFolder(null);
        }

        await _loadFolderTree(showLoading: false);
      } else {
        _showErrorSnackBar(result['error'] ?? 'Failed to delete folder');
      }

      setState(() => _isLoading = false);
    }
  }

  Widget _buildCreateFolderDialog(FolderTreeNode? parent) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2B41BD), Color(0xFF3D56D5)],
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2B41BD).withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.create_new_folder_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Create New Folder',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A237E),
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (parent != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE8E8E8)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_rounded,
                    size: 18,
                    color: Colors.amber.shade700,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Parent: ${parent.name}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF424242),
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _folderNameController,
            autofocus: true,
            style: const TextStyle(fontSize: 15, color: Color(0xFF1A237E)),
            decoration: InputDecoration(
              labelText: 'Folder Name',
              labelStyle: const TextStyle(
                color: Color(0xFF666666),
                fontWeight: FontWeight.w500,
              ),
              hintText: 'Enter folder name',
              hintStyle: const TextStyle(color: Color(0xFF999999)),
              prefixIcon: const Icon(
                Icons.folder_outlined,
                color: Color(0xFF2B41BD),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFF2B41BD),
                  width: 2,
                ),
              ),
              filled: true,
              fillColor: const Color(0xFFFAFAFA),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) {
                Navigator.of(context).pop(value.trim());
              }
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Invalid characters: < > : " / \\ | ? *',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade500,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF666666),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
            backgroundColor: Colors.white,
          ),
          child: const Text(
            'Cancel',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        ElevatedButton.icon(
          onPressed: () {
            final name = _folderNameController.text.trim();
            if (name.isNotEmpty) {
              Navigator.of(context).pop(name);
            }
          },
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text(
            'Create Folder',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2B41BD),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            elevation: 2,
            shadowColor: const Color(0xFF2B41BD).withOpacity(0.3),
          ),
        ),
      ],
    );
  }

  Future<bool?> _showDeleteConfirmation(FolderTreeNode node) {
    final hasChildren = node.children.isNotEmpty;

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFD32F2F), Color(0xFFF44336)],
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.delete_forever_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Delete Folder?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A237E),
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete "${node.name}"?',
              style: const TextStyle(fontSize: 15, color: Color(0xFF424242)),
            ),
            if (hasChildren) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFE0B2)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange.shade700,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This folder contains ${node.children.length} subfolder(s). All contents will be permanently deleted.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.orange.shade900,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'This action cannot be undone.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF666666),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: Color(0xFFE0E0E0)),
              ),
              backgroundColor: Colors.white,
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 2,
              shadowColor: Colors.red.withOpacity(0.3),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.delete_rounded, size: 20),
                SizedBox(width: 8),
                Text('Delete', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: Colors.green,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Success',
                    style: TextStyle(
                      color: Colors.green.shade50,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(message, style: const TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                color: Colors.red,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Error',
                    style: TextStyle(
                      color: Colors.red.shade50,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(message, style: const TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _handleRefresh() async {
    await _loadFolderTree(showLoading: false);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pop(_didChange);
        return false;
      },
      child: DismissKeyboard(child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          titleSpacing: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).pop(_didChange),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Folders',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
              Text(
                _breadcrumbPath.isEmpty ? 'All folders' : _breadcrumbPath.last.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          actions: [
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(28),
                borderRadius: BorderRadius.circular(10),
              ),
              child: IconButton(
                icon: Icon(
                  _isGridView
                      ? Icons.view_list_rounded
                      : Icons.grid_view_rounded,
                ),
                tooltip: _isGridView ? 'List view' : 'Grid view',
                onPressed: () => setState(() => _isGridView = !_isGridView),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(28),
                borderRadius: BorderRadius.circular(10),
              ),
              child: IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh',
                onPressed: () => _loadFolderTree(),
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'create_here',
                  child: Row(
                    children: [
                      Icon(Icons.create_new_folder_rounded,
                          color: AppColors.primary),
                      SizedBox(width: 12),
                      Text('New folder here',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'create_root',
                  child: Row(
                    children: [
                      Icon(Icons.add_rounded, color: AppColors.primary),
                      SizedBox(width: 12),
                      Text('New root folder',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'expand',
                  child: Row(
                    children: [
                      Icon(Icons.unfold_more_rounded,
                          color: Colors.grey.shade800),
                      const SizedBox(width: 12),
                      const Text('Expand all',
                          style: TextStyle(fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'collapse',
                  child: Row(
                    children: [
                      Icon(Icons.unfold_less_rounded,
                          color: Colors.grey.shade800),
                      const SizedBox(width: 12),
                      const Text('Collapse all',
                          style: TextStyle(fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ],
              onSelected: (value) async {
                if (value == 'expand') {
                  setState(() => _treeService.expandAll());
                } else if (value == 'collapse') {
                  setState(() => _treeService.collapseAll());
                } else if (value == 'create_here') {
                  await _createFolder(_currentFolder);
                } else if (value == 'create_root') {
                  await _createFolder(null);
                }
              },
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(14),
            child: Container(
              height: 14,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.primary,
                    const Color(0xFF1F2D8F),
                  ],
                ),
              ),
              child: const SizedBox.shrink(),
                /* controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search folders…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _folderSearch.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          onPressed: () {
                            setState(() {
                              _folderSearch = '';
                              _searchController.clear();
                            });
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.withAlpha(30)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.withAlpha(30)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        const BorderSide(color: Colors.white, width: 2),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                onChanged: (v) => setState(() => _folderSearch = v),
              ), */
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _isLoading ? null : () => _createFolder(_currentFolder),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.create_new_folder_rounded),
          label: Text(_currentFolder == null ? 'New folder' : 'New subfolder'),
        ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 50,
                    height: 50,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation(Color(0xFF2B41BD)),
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Loading folders...',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          : _rootFolders.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.folder_off_rounded,
                    size: 80,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No folders found',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF666666),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Create your first folder to get started',
                    style: TextStyle(fontSize: 14, color: Color(0xFF999999)),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => _createFolder(null),
                    icon: const Icon(Icons.create_new_folder_rounded),
                    label: const Text('Create First Folder'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2B41BD),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : GestureDetector(
              onTap: () {
                // When user taps on empty space, navigate to root
                if (_currentFolder != null) {
                  _navigateToFolder(null);
                }
              },
              child: RefreshIndicator(
                key: _refreshIndicatorKey,
                onRefresh: _handleRefresh,
                color: const Color(0xFF2B41BD),
                backgroundColor: Colors.white,
                displacement: 40,
                strokeWidth: 3,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    children: [
                      // Debug info (remove in production)
                      // if (_rootFolders.isNotEmpty)
                      //   Container(
                      //     color: Colors.yellow.withOpacity(0.1),
                      //     padding: const EdgeInsets.all(8),
                      //     child: Row(
                      //       children: [
                      //         Icon(
                      //           Icons.info,
                      //           color: Colors.amber.shade700,
                      //           size: 16,
                      //         ),
                      //         const SizedBox(width: 8),
                      //         Expanded(
                      //           child: Text(
                      //             'Debug: ${_rootFolders.length} root folder(s) loaded',
                      //             style: TextStyle(
                      //               fontSize: 12,
                      //               color: Colors.amber.shade900,
                      //             ),
                      //           ),
                      //         ),
                      //       ],
                      //     ),
                      //   ),

                      // Breadcrumb with improved design
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: BreadcrumbWidget(
                          path: _breadcrumbPath,
                          onFolderTap: (folder) {
                            _navigateToFolder(folder);
                          },
                        ),
                      ),

                      // Quick search
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: TextField(
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: 'Search folders…',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _folderSearch.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear',
                                    onPressed: () {
                                      setState(() {
                                        _folderSearch = '';
                                        _searchController.clear();
                                      });
                                    },
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                            filled: true,
                            fillColor: const Color(0xFFF5F6FB),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: Colors.grey.withAlpha(35)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: Colors.grey.withAlpha(35)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: Color(0xFF2B41BD),
                                width: 2,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                          onChanged: (v) => setState(() => _folderSearch = v),
                        ),
                      ),

                      // Statistics card with enhanced shadow
                      _buildStatisticsCard(),

                      // Folder tree/grid
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        constraints: BoxConstraints(
                          minHeight: MediaQuery.of(context).size.height - 250,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(20),
                            topRight: Radius.circular(20),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 20,
                              offset: const Offset(0, -4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(20),
                            topRight: Radius.circular(20),
                          ),
                          child: _isGridView
                              ? FolderGridWidget(
                                  folders: _filterFoldersForGrid(
                                    _currentFolder?.children ?? _rootFolders,
                                  ),
                                  onFolderTap: (node) {
                                    _navigateToFolder(node);
                                  },
                                  onFolderLongPress: (node) =>
                                      _showFolderContextMenu(node),
                                  selectedFolder: _currentFolder,
                                )
                              : (_folderSearch.trim().isNotEmpty &&
                                      _treeService
                                          .searchFolders(_folderSearch.trim())
                                          .isEmpty)
                                  ? _buildSearchEmptyState()
                                  : FolderTreeWidget(
                                      rootNodes: _folderSearch.trim().isEmpty
                                          ? _rootFolders
                                          : _treeService.searchFolders(
                                              _folderSearch.trim(),
                                            ),
                                      onFolderTap: (node) {
                                        _navigateToFolder(node);
                                      },
                                      onFolderLongPress: _showFolderContextMenu,
                                      onCreateSubfolder: _createFolder,
                                      onDeleteFolder: _deleteFolder,
                                      selectedFolder: _currentFolder,
                                    ),
                        ),
                      ),
                      const SizedBox(height: 80), // Space for FAB
                    ],
                  ),
                ),
              ),
            ),
      ),
    ));
  }

  Widget _buildSearchEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF2B41BD).withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.search_off_rounded,
                color: Color(0xFF2B41BD),
                size: 34,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'No matching folders',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A237E),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Try a different search term.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticsCard() {
    final stats = _treeService.getStatistics();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2B41BD).withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFF5F5F7)],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildEnterpriseStatItem(
            icon: Icons.folder_special_rounded,
            label: 'Total Folders',
            value: stats['total'].toString(),
            color: const Color(0xFF2B41BD),
            gradient: const LinearGradient(
              colors: [Color(0xFF2B41BD), Color(0xFF3D56D5)],
            ),
          ),
          _buildEnterpriseStatItem(
            icon: Icons.folder_open_rounded,
            label: 'Root Folders',
            value: stats['root'].toString(),
            color: const Color(0xFFFF9800),
            gradient: const LinearGradient(
              colors: [Color(0xFFFF9800), Color(0xFFFFB74D)],
            ),
          ),
          _buildEnterpriseStatItem(
            icon: Icons.layers_rounded,
            label: 'Max Depth',
            value: stats['max_depth'].toString(),
            color: const Color(0xFF4CAF50),
            gradient: const LinearGradient(
              colors: [Color(0xFF4CAF50), Color(0xFF81C784)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnterpriseStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required Gradient gradient,
  }) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon with gradient background
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Center(child: Icon(icon, color: Colors.white, size: 20)),
            ),
            const SizedBox(height: 12),
            // Value with animated number
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                value,
                key: ValueKey(value),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A237E),
                  letterSpacing: -0.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 4),
            // Label
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _showFolderContextMenu(FolderTreeNode node) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Colors.white,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              node.name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A237E),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              '${node.children.length} subfolder(s)',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            _buildContextMenuButton(
              icon: Icons.create_new_folder_rounded,
              label: 'Create Subfolder',
              color: const Color(0xFF2B41BD),
              onTap: () {
                Navigator.pop(context);
                _createFolder(node);
              },
            ),
            const SizedBox(height: 12),
            _buildContextMenuButton(
              icon: Icons.edit_rounded,
              label: 'Rename (coming soon)',
              color: Colors.blueGrey.shade400,
              enabled: false,
              onTap: () {},
            ),
            const SizedBox(height: 12),
            _buildContextMenuButton(
              icon: Icons.delete_rounded,
              label: 'Delete Folder',
              color: Colors.red.shade700,
              onTap: () {
                Navigator.pop(context);
                _deleteFolder(node);
              },
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF666666),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: Color(0xFFE0E0E0)),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContextMenuButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return Material(
      color: Colors.transparent,

      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: enabled
                ? color.withOpacity(0.05)
                : Colors.grey.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: enabled ? color.withOpacity(0.1) : Colors.grey.shade200,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: enabled ? color : Colors.grey.shade500, size: 22),
              const SizedBox(width: 16),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: enabled ? color : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _renameFolder(FolderTreeNode node) async {
    // Implement rename functionality
    _showSuccessSnackBar('Rename functionality coming soon');
  }
}
