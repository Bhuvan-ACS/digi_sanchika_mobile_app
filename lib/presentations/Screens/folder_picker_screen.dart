// lib/presentations/screens/folder_picker_screen.dart

import 'package:flutter/material.dart';
import 'package:digi_sanchika/models/folder_tree_node.dart';
import 'package:digi_sanchika/services/folder_tree_service.dart';
import 'package:digi_sanchika/widgets/folder_tree_widget.dart';
import 'package:digi_sanchika/widgets/breadcrumb_widget.dart';
import 'package:digi_sanchika/widgets/dismiss_keyboard.dart';

class FolderPickerScreen extends StatefulWidget {
  final String? currentFolderId;
  final String title;

  const FolderPickerScreen({
    super.key,
    this.currentFolderId,
    this.title = 'Select Folder',
  });

  @override
  State<FolderPickerScreen> createState() => _FolderPickerScreenState();
}

class _FolderPickerScreenState extends State<FolderPickerScreen> {
  final FolderTreeService _treeService = FolderTreeService();
  
  List<FolderTreeNode> _rootFolders = [];
  FolderTreeNode? _selectedFolder;
  List<FolderTreeNode> _breadcrumbPath = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  List<FolderTreeNode> _filteredFolders = [];

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFolders() async {
    setState(() => _isLoading = true);

    try {
      final tree = await _treeService.fetchFolderTree();
      
      setState(() {
        _rootFolders = tree;
        _filteredFolders = tree;
        
        // Pre-select current folder if provided
        if (widget.currentFolderId != null) {
          _selectedFolder = _treeService.findNodeById(widget.currentFolderId!);
          if (_selectedFolder != null) {
            _breadcrumbPath = _selectedFolder!.getPath(_rootFolders);
          }
        }
        
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackBar('Failed to load folders: $e');
    }
  }

  void _onSearch(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredFolders = _rootFolders;
      });
      return;
    }

    final results = _treeService.searchFolders(query);
    setState(() {
      _filteredFolders = results;
    });
  }

  void _onFolderSelect(FolderTreeNode folder) {
    setState(() {
      _selectedFolder = folder;
      _breadcrumbPath = folder.getPath(_rootFolders);
    });
  }

  void _navigateToBreadcrumb(FolderTreeNode? folder) {
    setState(() {
      _selectedFolder = folder;
      if (folder != null) {
        _breadcrumbPath = folder.getPath(_rootFolders);
      } else {
        _breadcrumbPath = [];
      }
    });
  }

  void _confirmSelection() {
    Navigator.of(context).pop(_selectedFolder);
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color.fromARGB(255, 43, 65, 189),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: _selectedFolder != null ? _confirmSelection : null,
            child: Text(
              'SELECT',
              style: TextStyle(
                color: _selectedFolder != null ? Colors.white : Colors.white54,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: DismissKeyboard(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
              children: [
                // Search bar
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearch,
                    decoration: InputDecoration(
                      hintText: 'Search folders...',
                      prefixIcon: const Icon(Icons.search, color: Colors.indigo),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                _onSearch('');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.indigo, width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),

                // Breadcrumb (if folder selected)
                if (_selectedFolder != null && _searchController.text.isEmpty)
                  BreadcrumbWidget(
                    path: _breadcrumbPath,
                    onFolderTap: _navigateToBreadcrumb,
                    backgroundColor: Colors.blue.shade50,
                    activeColor: Colors.indigo,
                  ),

                // Current selection indicator
                if (_selectedFolder != null)
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.indigo.shade200, width: 2),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.indigo.shade700),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Selected Folder',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.indigo.shade600,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _selectedFolder!.name,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.indigo.shade900,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.clear),
                          color: Colors.indigo.shade700,
                          onPressed: () {
                            setState(() {
                              _selectedFolder = null;
                              _breadcrumbPath = [];
                            });
                          },
                        ),
                      ],
                    ),
                  ),

                // Folder list
                Expanded(
                  child: _filteredFolders.isEmpty
                      ? _buildEmptyState()
                      : CompactFolderTreeWidget(
                          rootNodes: _filteredFolders,
                          onFolderSelect: _onFolderSelect,
                          selectedFolder: _selectedFolder,
                        ),
                ),

                // Bottom action bar
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Select Root button
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _selectedFolder = null;
                              _breadcrumbPath = [];
                            });
                          },
                          icon: const Icon(Icons.home),
                          label: const Text('Select Root'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.indigo,
                            side: const BorderSide(color: Colors.indigo),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      
                      const SizedBox(width: 12),
                      
                      // Confirm button
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _confirmSelection,
                          icon: const Icon(Icons.check),
                          label: Text(
                            _selectedFolder == null 
                                ? 'Use Root Folder' 
                                : 'Use This Folder',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 2,
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
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _searchController.text.isNotEmpty
                ? Icons.search_off
                : Icons.folder_off,
            size: 64,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            _searchController.text.isNotEmpty
                ? 'No folders found'
                : 'No folders available',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchController.text.isNotEmpty
                ? 'Try a different search term'
                : 'Create your first folder to get started',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
}
