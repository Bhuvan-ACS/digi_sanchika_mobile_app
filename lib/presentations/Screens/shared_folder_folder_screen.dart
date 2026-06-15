import 'dart:async';

import 'package:digi_sanchika/local_storage.dart';
import 'package:digi_sanchika/models/app_view_mode.dart';
import 'package:digi_sanchika/models/document.dart';
import 'package:digi_sanchika/models/shared_folder.dart';
import 'package:digi_sanchika/presentations/Screens/shared_folder_screen.dart';
import 'package:digi_sanchika/services/folder_service.dart';
import 'package:digi_sanchika/services/shared_browse_service.dart';
import 'package:digi_sanchika/services/shared_documents_service.dart';
import 'package:digi_sanchika/services/shared_folders_service.dart';
import 'package:digi_sanchika/utils/responsive_helper.dart';
import 'package:digi_sanchika/widgets/view_mode_popup_button.dart';
import 'package:flutter/material.dart';

class SharedFolderFolderScreen extends StatefulWidget {
  const SharedFolderFolderScreen({super.key});

  @override
  State<SharedFolderFolderScreen> createState() => _SharedFolderFolderScreenState();
}

class _SharedFolderFolderScreenState extends State<SharedFolderFolderScreen> {
  
  List<Document> _sharedDocuments = [];

List<SharedFolder> _filteredFolders = [];
  List<SharedFolder> _sharedFolders = [];
  final SharedDocumentsService _sharedService = SharedDocumentsService();
  final SharedFoldersService _foldersService = SharedFoldersService();
  final TextEditingController _searchController = TextEditingController();
  String _selectedFileType = 'All';
  

  AppViewMode _currentViewMode = AppViewMode.list;


   Future<void> _hydrateSharedFolderCounts(List<SharedFolder> folders) async {
    if (folders.isEmpty) return;

    try {
      final futures = folders.map((f) async {
        final result = await SharedBrowseService.getSharedFolderContents(
          folderId: f.id,
        );
        if (result['success'] == true) {
          final docs = (result['documents'] as List?) ?? const [];
          final subs = (result['folders'] as List?) ?? const [];
          return MapEntry<String, int>(f.id, docs.length + subs.length);
        }
        return MapEntry<String, int>(f.id, -1);
      }).toList();

      final entries = await Future.wait(futures);
      if (!mounted) return;

      final countMap = <String, int>{};
      for (final e in entries) {
        if (e.value >= 0) countMap[e.key] = e.value;
      }

      if (countMap.isEmpty) return;

      setState(() {
        _sharedFolders = _sharedFolders
            .map(
              (f) => countMap.containsKey(f.id)
                  ? SharedFolder(
                      id: f.id,
                      name: f.name,
                      owner: f.owner,
                      createdAt: f.createdAt,
                      expiresAt: f.expiresAt,
                      itemCount: countMap[f.id]!,
                    )
                  : f,
            )
            .toList();
      });
    } catch (_) {
      // Non-fatal: counts are best-effort.
    }
  }

   @override
  void initState() {
    super.initState();
    _loadSharedData();
  }

    void _clearExpandedStates() {
    _expandedStates.clear();
  }

  Map<String, bool> _expandedStates = {};

  bool _isLoading = true;
  bool _hasError = false;
  bool _isDownloading = false;
  String _errorMessage = '';
  
  int _totalDocuments = 0;
  int _totalFolders = 0;
    List<String> _availableFileTypes = [
    'All',
  ]; // Will be populated from documents



    Future<void> _loadSharedData() async {
    if (!mounted) return;

    _clearExpandedStates();

    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = '';
    });

    try {
      // Check if user is logged in
      final isLoggedIn = await _sharedService.isLoggedIn();
      if (!isLoggedIn) {
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorMessage = 'Please login to view shared documents';
            _isLoading = false;
          });
        }
        return;
      }

      // Check internet connection
      if (!_sharedService.isConnected) {
        // Load from local storage
        _loadFromLocalStorage();
        return;
      }
final response = await _sharedService.fetchSharedDocuments();
final documents = response.documents;

final folders = await _foldersService.fetchSharedFolders();

      if (!mounted) return;

      // Extract unique file types from documents
      final fileTypes = documents
          .map((doc) => doc.type.toUpperCase())
          .toSet()
          .toList();
      fileTypes.sort();

   setState(() {
  _sharedDocuments = documents;
  _sharedFolders = folders;
  _filteredFolders = List.from(folders);

  _totalDocuments = documents.length;
  _totalFolders = folders.length;
  _availableFileTypes = ['All', ...fileTypes];
  _isLoading = false;
});

      // Best-effort: fetch per-folder item counts for better UX.
      unawaited(_hydrateSharedFolderCounts(folders));

      // Save to local storage for offline access
      await _saveToLocalStorage();
    } catch (e) {
      if (!mounted) return;

      debugPrint('Error loading shared data: $e');

      // Try to load from local storage as fallback
      _loadFromLocalStorage();
    }
  }

   Future<void> _loadFromLocalStorage() async {
    try {
      final localDocs = await LocalStorageService.loadSharedDocuments();

      // Extract file types from local docs too
      final fileTypes = localDocs
          .map((doc) => doc.type.toUpperCase())
          .toSet()
          .toList();
      fileTypes.sort();

      if (mounted) {
        setState(() {
          _sharedDocuments = localDocs;
          _totalDocuments = localDocs.length;
          _totalFolders = 0;
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

  Future<void> _saveToLocalStorage() async {
    if (_sharedDocuments.isNotEmpty) {
      try {
        await LocalStorageService.saveSharedDocuments(_sharedDocuments);
        debugPrint(
          '✅ Saved ${_sharedDocuments.length} documents to local storage',
        );
      } catch (e) {
        debugPrint('❌ Error saving to local storage: $e');
      }
    }
  }

  void _filterFolders(String query) {
  final search = query.trim().toLowerCase();

  setState(() {
    if (search.isEmpty) {
      _filteredFolders = List.from(_sharedFolders);
    } else {
      _filteredFolders = _sharedFolders.where((folder) {
        return folder.name.toLowerCase().contains(search) ||
            folder.owner.toLowerCase().contains(search) ||
            folder.createdAt.toLowerCase().contains(search);
      }).toList();
    }
  });
}

 
  /// Clear search and reset filter
void _clearSearch() {
  _searchController.clear();

  setState(() {
    _filteredFolders = List.from(_sharedFolders);
  });
}

    Widget _buildLayoutSelector() {
    return ViewModePopupButton(
      value: _currentViewMode,
      onSelected: (mode) => setState(() => _currentViewMode = mode),
    );
  }
 


  @override
  Widget build(BuildContext context) {
    final r = context.r;

    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
             Row(
                  children: [
                    Expanded(
                      child: Container(
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(r.p(12)),
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
    onChanged: _filterFolders,
    decoration: InputDecoration(
      hintText: 'Search folders...',
      prefixIcon: const Icon(
        Icons.search,
        color: Colors.indigo,
      ),
      suffixIcon: _searchController.text.isNotEmpty
          ? IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _clearSearch,
            )
          : null,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(r.p(12)),
        borderSide: BorderSide.none,
      ),
    ),
  ),
)
                    ),
                    SizedBox(width: r.p(10)),
                    // File Type Filter
                    // _buildFileTypeFilter(),
                    // SizedBox(width: r.p(8)),
                    // Layout Selector
                    _buildLayoutSelector(),
                 
                  ],
                ),
           if (_isLoading)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      color: Colors.indigo,
                      strokeWidth: 2,
                    ),
                    SizedBox(height: r.p(16)),
                    Text(
                      'Loading shared documents...',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: r.p(10)),
                    if (_sharedFolders.isNotEmpty)
                      Text(
                        '${_sharedFolders.length} folder${_sharedFolders.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: r.sp(13),
                        ),
                      ),
            SizedBox(height: r.p(10)),

        Expanded(
  child:  ListView.builder(
          itemCount: _filteredFolders.length,
          itemBuilder: (context, index) {
            final folder = _filteredFolders[index];

            return Card(
              margin: EdgeInsets.symmetric(
                vertical: r.p(4),
              ),
              child: ListTile(
                leading: const Icon(
                  Icons.folder,
                  color: Colors.amber,
                ),
                title: Text(
                  folder.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text('Owner: ${folder.owner}'),
                    Text('Created: ${folder.createdAt}'),
                    if (folder.itemCount >= 0)
                      Text(
                        '${folder.itemCount} item${folder.itemCount == 1 ? '' : 's'}',
                      ),
                      Text("Expires in: ${_getExpiryText(folder.expiresAt)}"),
                  ],
                ),
                trailing: const Icon(
                  Icons.arrow_forward_ios,
                  size: 18,
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          SharedFolderScreen(
                        folderId: folder.id,
                        folderName: folder.name,
                        userName: folder.owner,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
)
        ],
      ),
    );
  }

   void _openSharedFolder(SharedFolder folder) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SharedFolderScreen(
          folderId: folder.id,
          folderName: folder.name,
          userName: folder.owner,
        ),
      ),
    );
  }

  String _getExpiryText(String? expiryDate) {
  if (expiryDate == null ||
      expiryDate.isEmpty ||
      expiryDate == 'No Expiry') {
    return 'No Expiry';
  }

  try {
    final expiry = DateTime.parse(expiryDate);

    // Handle permanent shares (9999 date)
    if (expiry.year >= 9999) {
      return 'No Expiry';
    }

    final now = DateTime.now();

    // Remove time portion
    final today = DateTime(now.year, now.month, now.day);
    final expiryDay =
        DateTime(expiry.year, expiry.month, expiry.day);

    final difference =
        expiryDay.difference(today).inDays;

    if (difference < 0) {
      return 'Expired';
    } else if (difference == 0) {
      return 'Today';
    } else if (difference == 1) {
      return 'Tomorrow';
    } else {
      return 'In $difference days';
    }
  } catch (e) {
    return 'No Expiry';
  }
}

}