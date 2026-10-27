import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:digi_sanchika/presentations/Screens/shared_folder_screen.dart';
import 'package:digi_sanchika/widgets/file_type_icon.dart';
import 'package:digi_sanchika/widgets/folder_illustration.dart';
import 'package:digi_sanchika/widgets/folder_tile.dart';
import 'package:digi_sanchika/utils/app_fonts.dart';
import 'package:digi_sanchika/widgets/favorite_menu.dart';
import 'package:digi_sanchika/widgets/section_panel.dart';
import 'package:flutter/material.dart';
import 'package:digi_sanchika/utils/responsive_helper.dart';
import 'package:digi_sanchika/models/document.dart';
import 'package:digi_sanchika/services/shared_documents_service.dart';
import 'package:digi_sanchika/local_storage.dart';
import 'package:digi_sanchika/models/shared_folder.dart';
import 'package:digi_sanchika/services/api_service.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:digi_sanchika/services/document_opener_service.dart';
import 'package:digi_sanchika/widgets/dismiss_keyboard.dart';
import 'package:digi_sanchika/services/shared_folders_service.dart';
import 'package:digi_sanchika/services/download_requests_service.dart';
import 'package:digi_sanchika/widgets/share_access_sheet.dart';
import 'package:digi_sanchika/services/download_access_service.dart';
import 'package:digi_sanchika/services/folder_download_service.dart';
import 'package:digi_sanchika/services/shared_browse_service.dart';
import 'package:digi_sanchika/models/app_view_mode.dart';
import 'package:digi_sanchika/widgets/layout_capsule.dart';
import 'package:digi_sanchika/widgets/home_components.dart';
import 'package:digi_sanchika/widgets/ai_sparkle_button.dart';
import 'package:digi_sanchika/widgets/share_empty_illustration.dart';
import 'package:digi_sanchika/services/my_documents_service.dart';
import 'package:digi_sanchika/widgets/download_feedback.dart';
import 'package:digi_sanchika/widgets/version_history_dialog.dart';
import 'package:digi_sanchika/widgets/responsive_page.dart';
import 'package:digi_sanchika/widgets/responsive_document_gallery.dart';

class SharedMeScreen extends StatefulWidget {
  const SharedMeScreen({super.key});

  @override
  State<SharedMeScreen> createState() => _SharedMeScreenState();
}

class _SharedMeScreenState extends State<SharedMeScreen> {
  // Services
  final SharedDocumentsService _sharedService = SharedDocumentsService();
  final SharedFoldersService _sharedFoldersService = SharedFoldersService();
  final DocumentOpenerService _documentOpener = DocumentOpenerService();

  // Controllers
  final TextEditingController _searchController = TextEditingController();

  // State variables
  List<Document> _sharedDocuments = [];
  List<Document> _filteredDocuments = [];
  bool _aiSearching = false;
  List<SharedFolder> _sharedFolders = [];
  List<SharedFolder> _filteredFolders = [];
  bool _isLoading = true;
  bool _hasError = false;
  bool _isDownloading = false;
  String _errorMessage = '';

  // Layout mode and file type filter variables
  AppViewMode _currentViewMode = AppViewMode.list;
  String _selectedFileType = 'All';
  List<String> availableFileTypes = ['All'];

  // Collapsible states for document cards
  final Map<String, bool> _expandedStates = {};

  void _clearExpandedStates() {
    _expandedStates.clear();
  }

  // Stats
  int totalDocuments = 0;
  int totalFolders = 0;

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
        _filteredFolders = List.from(_sharedFolders);
      });
    } catch (_) {
      // Non-fatal: counts are best-effort.
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSharedData();
    print("shared data $_filteredDocuments");
    _sharedFoldersService
        .fetchSharedFolders()
        .then((folders) {
          print('Fetched ${folders.length} shared folders:');
          for (final folder in folders) {
            print(
              'Id: ${folder.id}, Name: ${folder.name}, Owner: ${folder.owner}, CreatedAt: ${folder.createdAt}, ExpiresAt: ${folder.expiresAt}, ItemCount: ${folder.itemCount}',
            );
          }
        })
        .catchError((e) {
          print('Error fetching shared folders: $e');
        });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Load shared documents and folders
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
        _loadFromLocalStorage();
        return;
      }

      // Load from backend
      final response = await _sharedService.fetchSharedDocuments();
      final List<Document> documents = response.documents;
      final List<SharedFolder> folders = response.folders;

      if (!mounted) return;

      // Extract unique file types from documents
      final fileTypes = documents
          .map((doc) => doc.type.toUpperCase())
          .toSet()
          .toList();
      fileTypes.sort();

      setState(() {
        _sharedDocuments = documents;
        _filteredDocuments = documents;
        _sharedFolders = folders;
        _filteredFolders = List.from(folders);
        totalDocuments = documents.length;
        totalFolders = folders.length;
        availableFileTypes = ['All', ...fileTypes];
        _isLoading = false;
      });

      print('Folders count: ${folders.length}');
      for (final folder in _sharedFolders) {
        print(
          'Id: ${folder.id}, '
          'Name: ${folder.name}, '
          'Owner: ${folder.owner}, '
          'CreatedAt: ${folder.createdAt}, '
          'ExpiresAt: ${folder.expiresAt}, '
          'ItemCount: ${folder.itemCount}',
        );
      }

      // Best-effort: fetch per-folder item counts.
      unawaited(_hydrateSharedFolderCounts(folders));

      // Save to local storage for offline access
      await _saveToLocalStorage();
    } catch (e) {
      if (!mounted) return;
      debugPrint('Error loading shared data: $e');
      _loadFromLocalStorage();
    }
  }

  /// Load data from local storage
  Future<void> _loadFromLocalStorage() async {
    try {
      final localDocs = await LocalStorageService.loadSharedDocuments();

      final fileTypes = localDocs
          .map((doc) => doc.type.toUpperCase())
          .toSet()
          .toList();
      fileTypes.sort();

      if (mounted) {
        setState(() {
          _sharedDocuments = localDocs;
          _filteredDocuments = localDocs;
          totalDocuments = localDocs.length;
          totalFolders = 0;
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

  /// Filter documents AND folders based on search query and file type
  void _filterDocuments({String? searchQuery, String? fileType}) {
    final query = searchQuery ?? _searchController.text;
    final type = fileType ?? _selectedFileType;

    setState(() {
      // --- Filter files ---
      _filteredDocuments = _sharedDocuments.where((doc) {
        final fileTypeMatch = type == 'All' || doc.type.toUpperCase() == type;
        if (query.isEmpty) return fileTypeMatch;
        final lowercaseQuery = query.toLowerCase();
        return fileTypeMatch &&
            (doc.name.toLowerCase().contains(lowercaseQuery) ||
                (doc.owner.isNotEmpty &&
                    doc.owner.toLowerCase().contains(lowercaseQuery)) ||
                ((doc.sharedViaGroupName ?? '').toLowerCase().contains(
                  lowercaseQuery,
                )) ||
                ((doc.sharedByName ?? '').toLowerCase().contains(
                  lowercaseQuery,
                )) ||
                (doc.keyword.isNotEmpty &&
                    doc.keyword.toLowerCase().contains(lowercaseQuery)) ||
                doc.type.toLowerCase().contains(lowercaseQuery) ||
                (doc.classification.isNotEmpty &&
                    doc.classification.toLowerCase().contains(
                      lowercaseQuery,
                    )) ||
                (doc.details.isNotEmpty &&
                    doc.details.toLowerCase().contains(lowercaseQuery)) ||
                (doc.folder.isNotEmpty &&
                    doc.folder.toLowerCase().contains(lowercaseQuery)));
      }).toList();

      // --- Filter folders ---
      if (query.isEmpty) {
        _filteredFolders = List.from(_sharedFolders);
      } else {
        final lowercaseQuery = query.toLowerCase();
        _filteredFolders = _sharedFolders.where((folder) {
          return folder.name.toLowerCase().contains(lowercaseQuery) ||
              folder.owner.toLowerCase().contains(lowercaseQuery);
        }).toList();
      }
    });
  }

  /// AI assistant search over documents shared with me
  /// (POST /search/semantic, scope `shared`). Results keep server relevance
  /// order; folders still match by name.
  Future<void> _runAiSearch(String query) async {
    setState(() => _aiSearching = true);
    final result = await MyDocumentsService.semanticSearch(
      query: query,
      scope: 'shared',
      limit: 50,
    );
    if (!mounted) return;
    setState(() => _aiSearching = false);
    final results = result['results'];
    if (result['success'] != true || results is! List) {
      _filterDocuments(searchQuery: query);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result['error'] ?? 'AI search failed'}. Showing name matches.',
          ),
        ),
      );
      return;
    }
    final ids = results.map((r) => r['documentId'].toString()).toList();
    final type = _selectedFileType;
    final lowercaseQuery = query.toLowerCase();
    setState(() {
      _filteredDocuments =
          _sharedDocuments
              .where(
                (doc) =>
                    ids.contains(doc.id) &&
                    (type == 'All' || doc.type.toUpperCase() == type),
              )
              .toList()
            ..sort((a, b) => ids.indexOf(a.id).compareTo(ids.indexOf(b.id)));
      _filteredFolders = _sharedFolders
          .where(
            (folder) =>
                folder.name.toLowerCase().contains(lowercaseQuery) ||
                folder.owner.toLowerCase().contains(lowercaseQuery),
          )
          .toList();
    });
  }

  /// Clear search and reset filter
  void _clearSearch() {
    _searchController.clear();
    _selectedFileType = 'All';
    _filterDocuments(searchQuery: '', fileType: 'All');
  }

  /// Get file icon based on type
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
        return Icons.table_chart;
      default:
        return Icons.insert_drive_file;
    }
  }

  /// Get file color based on type
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
        return Colors.green.shade700;
      default:
        return Colors.indigo;
    }
  }

  // ============ DOWNLOAD HELPER METHODS ============

  Future<Directory> getDownloadDirectory() async {
    if (Platform.isAndroid) {
      return await getApplicationDocumentsDirectory();
    } else if (Platform.isIOS) {
      return await getApplicationDocumentsDirectory();
    }
    return Directory.current;
  }

  Future<void> _downloadDocument(Document document) async {
    if (!ApiService.isConnected) {
      _showSnackBar('Cannot download while offline', Colors.orange);
      return;
    }

    setState(() {
      _isDownloading = true;
    });

    try {
      debugPrint(
        ' Starting download for document: ${document.id} - ${document.name}',
      );
      final result = await DownloadAccessService.downloadBytesWithAccess(
        documentId: document.id,
      );

      if (result['requiresApproval'] == true) {
        final reqService = DownloadRequestsService();
        final reqResult = await reqService.createRequest(
          documentId: document.id,
          reason: 'Need offline copy',
        );
        _showSnackBar(
          reqResult['success'] == true
              ? 'Download request sent for approval'
              : (reqResult['message'] ?? 'Download request failed'),
          reqResult['success'] == true ? Colors.orange : Colors.red,
        );
        return;
      }

      debugPrint('Download result keys: ${result.keys}');
      debugPrint('Success: ${result['success']}');
      debugPrint('Has fileData: ${result.containsKey('fileData')}');

      if (result['success'] == true) {
        if (!result.containsKey('fileData')) {
          if (result.containsKey('bytes')) {
            result['fileData'] = result['bytes'];
          } else {
            debugPrint('fileData key missing in response');
            throw Exception('Server did not return file data');
          }
        }
        final fileData = result['fileData'];

        if (fileData == null) {
          debugPrint('fileData is null');
          throw Exception('Server returned null file data');
        }

        List<int> bytesToSave;

        if (fileData is List<int>) {
          bytesToSave = fileData;
        } else if (fileData is List<dynamic>) {
          bytesToSave = fileData.cast<int>();
        } else if (fileData is String) {
          bytesToSave = utf8.encode(fileData);
        } else {
          debugPrint(
            '❌ fileData is not List<int>, it is: ${fileData.runtimeType}',
          );
          throw Exception(
            'Invalid file data format. Expected List<int>, got ${fileData.runtimeType}',
          );
        }

        if (bytesToSave.isEmpty) {
          throw Exception('Downloaded file data is empty (0 bytes)');
        }

        debugPrint('✅ Received ${bytesToSave.length} bytes of file data');

        final directory = await getDownloadDirectory();

        String filename = result['filename']?.toString() ?? document.name;

        if (RegExp(r'^\d+$').hasMatch(filename) && document.name.isNotEmpty) {
          filename = document.name;
        }

        final docName = document.name;
        if (docName.isNotEmpty) {
          final extension = path.extension(docName);
          if (!filename.toLowerCase().endsWith(extension.toLowerCase()) &&
              extension.isNotEmpty) {
            final nameWithoutExt = path.withoutExtension(filename);
            filename = '$nameWithoutExt$extension';
          }
        }

        if (document.type.toLowerCase() == 'py' &&
            !filename.toLowerCase().endsWith('.py')) {
          filename = '$filename.py';
        }

        if (document.type.toLowerCase() == 'pdf' &&
            !filename.toLowerCase().endsWith('.pdf')) {
          filename = '$filename.pdf';
        }

        final filePath = '${directory.path}/$filename';
        debugPrint('Saving to: $filePath');

        final file = File(filePath);
        await file.writeAsBytes(bytesToSave);

        if (await file.exists()) {
          final fileSize = await file.length();
          debugPrint('File saved: ${fileSize} bytes');

          if (document.size == '0' ||
              document.size == '0 KB' ||
              document.size == '0 B') {
            final docIndex = _sharedDocuments.indexWhere(
              (d) => d.id == document.id,
            );
            if (docIndex != -1) {
              setState(() {
                _sharedDocuments[docIndex] = document.copyWith(
                  size: fileSize.toString(),
                );
                _filteredDocuments = List.from(_sharedDocuments);
              });
            }
          }

          final fileExtension = filename.toLowerCase().split('.').last;
          if (fileExtension == 'py' || document.type.toLowerCase() == 'py') {
            _showSnackBar('Downloaded: $filename', Colors.green);
            _showFileContent(bytesToSave, filename);
            return;
          }

          await DownloadFeedback.showDownloadedDialog(
            context,
            filename: filename,
            filePath: filePath,
          );
          return;
        } else {
          throw Exception('Failed to save file to disk');
        }
      } else {
        final errorMsg =
            result['error'] ?? result['message'] ?? 'Download failed';
        debugPrint('Download failed from service: $errorMsg');
        throw Exception(errorMsg);
      }
    } catch (e) {
      debugPrint('Download error: $e');
      _showSnackBar('Download failed: ${e.toString()}', Colors.red);
    } finally {
      setState(() {
        _isDownloading = false;
      });
    }
  }

  void _showFileContent(List<int> fileBytes, String filename) {
    try {
      final content = utf8.decode(fileBytes);

      showDialog(
        context: context,
        builder: (context) {
          final r = context.r;
          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  _getFileIcon('py'),
                  size: r.sp(24),
                  color: _getFileColor('py'),
                ),
                SizedBox(width: r.p(12)),
                Expanded(
                  child: Text(filename, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: MediaQuery.of(context).size.height * 0.6,
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.only(bottom: r.p(16)),
                    child: Row(
                      children: [
                        Icon(Icons.code, size: r.sp(16), color: Colors.blue),
                        SizedBox(width: r.p(8)),
                        Expanded(
                          child: Text(
                            'Python file (${fileBytes.length} bytes)',
                            style: TextStyle(
                              fontSize: r.sp(12),
                              color: Colors.blue,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.all(r.p(12)),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(r.p(8)),
                        border: Border.all(
                          color: const Color.fromRGBO(224, 224, 224, 1),
                        ),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          content,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: r.sp(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: content));
                  _showSnackBar('Code copied to clipboard', Colors.green);
                  Navigator.pop(context);
                },
                icon: Icon(Icons.copy, size: r.sp(18)),
                label: const Text('Copy'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      debugPrint('Error showing file content: $e');
      _showSnackBar('Cannot display file content', Colors.red);
    }
  }

  void _handleDocumentDoubleTap(Document document) {
    _documentOpener.openPreviewDialog(context: context, document: document);
  }

  Future<void> _showDocumentActions(
    Document document,
    BuildContext anchorContext,
  ) async {
    final action = await showMenu<String>(
      context: anchorContext,
      position: _menuPosition(anchorContext),
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
      await _showShareDialog(document);
    } else if (action == favoriteMenuValue) {
      await toggleFavoriteWithFeedback(context, document.id);
    }
  }

  RelativeRect _menuPosition(BuildContext anchorContext) {
    final button = anchorContext.findRenderObject() as RenderBox;
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
    final rect =
        button.localToGlobal(Offset.zero, ancestor: overlay) & button.size;
    return RelativeRect.fromRect(rect, Offset.zero & overlay.size);
  }

  RelativeRect _menuPositionBelow(BuildContext anchorContext) {
    final button = anchorContext.findRenderObject() as RenderBox;
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
    final rect =
        button.localToGlobal(Offset.zero, ancestor: overlay) & button.size;
    final bottomGap = overlay.size.height - rect.bottom - 4;
    return RelativeRect.fromLTRB(
      rect.left,
      rect.bottom + 4,
      overlay.size.width - rect.right,
      bottomGap < 0 ? 0 : bottomGap,
    );
  }

  void _showDocumentActionsBottomSheet(Document document) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(context.r.p(16)),
        ),
      ),
      builder: (context) {
        final r = context.r;
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: r.p(8)),
                Container(
                  width: r.p(40),
                  height: r.p(4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(r.p(2)),
                  ),
                ),
                SizedBox(height: r.p(12)),
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
                  leading: const Icon(Icons.download, color: Colors.green),
                  title: Text(
                    document.allowDownload ? 'Download' : 'Request Download',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _downloadDocument(document);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.history, color: Colors.blueGrey),
                  title: const Text('Version History'),
                  onTap: () {
                    Navigator.pop(context);
                    VersionHistoryDialog.show(context, document: document);
                  },
                ),
                SizedBox(height: r.p(8)),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showShareDialog(Document document) async {
    if (!ApiService.isConnected) {
      _showSnackBar('Cannot share while offline', Colors.orange);
      return;
    }

    await ShareAccessSheet.showForDocument(
      context: context,
      documentId: document.id,
      documentName: document.name,
    );
  }

  Future<void> _showDocumentDetails(Document document) async {
    _showSnackBar('Loading document details...', Colors.blue);

    final result = await _sharedService.getDocumentDetails(document.id);

    if (result['success'] == true && result['data'] != null) {
      final data = result['data'] as Map<String, dynamic>;

      showDialog(
        context: context,
        builder: (context) {
          final r = context.r;
          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  _getFileIcon(document.type),
                  size: r.sp(24),
                  color: _getFileColor(document.type),
                ),
                SizedBox(width: r.p(12)),
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
                    r: r,
                  ),
                  _buildDetailRow(
                    'File Type',
                    document.type.toUpperCase(),
                    r: r,
                  ),
                  _buildDetailRow(
                    'Size',
                    '${data['file_size']?.toString() ?? '0'} bytes',
                    r: r,
                  ),
                  _buildDetailRow(
                    'Owner',
                    data['owner']?['name']?.toString() ?? document.owner,
                    r: r,
                  ),
                  _buildDetailRow(
                    'Employee ID',
                    data['owner']?['employee_id']?.toString() ?? 'N/A',
                    r: r,
                  ),
                  _buildDetailRow('Upload Date', document.uploadDate, r: r),
                  _buildDetailRow(
                    'Folder',
                    data['folder_path']?.toString() ?? document.folder,
                    r: r,
                  ),
                  _buildDetailRow(
                    'Classification',
                    data['doc_class']?.toString() ?? document.classification,
                    r: r,
                  ),
                  _buildDetailRow(
                    'Keywords',
                    data['keywords']?.toString() ?? document.keyword,
                    r: r,
                  ),
                  _buildDetailRow(
                    'Remarks',
                    data['remarks']?.toString() ?? document.details,
                    r: r,
                  ),
                  _buildDetailRow(
                    'Public Access',
                    data['is_public']?.toString() == 'true' ? 'Yes' : 'No',
                    r: r,
                  ),
                  _buildDetailRow(
                    'Download Allowed',
                    document.allowDownload ? 'Yes' : 'No',
                    r: r,
                  ),
                  _buildDetailRow(
                    'Version',
                    data['version_number']?.toString() ?? '1',
                    r: r,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _showDocumentVersions(document);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history, size: r.sp(18)),
                    SizedBox(width: r.p(6)),
                    const Text('Versions'),
                  ],
                ),
              ),
            ],
          );
        },
      );
    } else {
      _showSnackBar(result['message'] ?? 'Failed to load details', Colors.red);
    }
  }

  Future<void> _showDocumentVersions(Document document) async {
    await VersionHistoryDialog.show(context, document: document);
  }

  // Format date to DD-MM-YYYY
  String _formatDateDDMMYYYY(dynamic date) {
    try {
      if (date == null || date.toString().isEmpty) return 'N/A';

      final dateStr = date.toString().trim();

      if (dateStr.contains('/')) {
        final parts = dateStr.split('/');
        if (parts.length >= 3) {
          final day = parts[0].padLeft(2, '0');
          final month = parts[1].padLeft(2, '0');
          final year = parts[2];
          return '$day-$month-$year';
        }
      }

      if (dateStr.contains('-')) {
        final parts = dateStr.split('-');
        if (parts.length >= 3) {
          if (parts[0].length == 4) {
            final year = parts[0];
            final month = parts[1].padLeft(2, '0');
            final day = parts[2].split(' ')[0].padLeft(2, '0');
            return '$day-$month-$year';
          } else {
            final day = parts[0].padLeft(2, '0');
            final month = parts[1].padLeft(2, '0');
            final year = parts[2];
            return '$day-$month-$year';
          }
        }
      }

      try {
        final dateTime = DateTime.parse(dateStr);
        final day = dateTime.day.toString().padLeft(2, '0');
        final month = dateTime.month.toString().padLeft(2, '0');
        final year = dateTime.year.toString();
        return '$day-$month-$year';
      } catch (e) {
        return dateStr;
      }
    } catch (e) {
      debugPrint('Error formatting date: $e for input: $date');
      return date.toString();
    }
  }

  Widget _buildDetailRow(String label, String value, {ResponsiveHelper? r}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: r?.p(4) ?? 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: r?.p(120) ?? 120,
            child: Text(
              '$label: ',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: r?.sp(14) ?? 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: r?.sp(14) ?? 14),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRowWithIcon(
    String label,
    String value,
    IconData iconData, {
    ResponsiveHelper? r,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: r?.p(4) ?? 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(iconData, size: r?.sp(16) ?? 16, color: Colors.grey.shade600),
          SizedBox(width: r?.p(12) ?? 12),
          SizedBox(
            width: r?.p(100) ?? 100,
            child: Text(label, style: w400_14Poppins(color: Colors.black87)),
          ),
          SizedBox(width: r?.p(8) ?? 8),
          Expanded(
            child: Text(
              value,
              style: w400_14Poppins(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ============ EXPIRY HELPERS ============

  String _getExpiryText(String? expiryDate) {
    if (expiryDate == null || expiryDate.isEmpty || expiryDate == 'No Expiry') {
      return 'No Expiry';
    }

    try {
      final expiry = DateTime.parse(expiryDate);
      if (expiry.year >= 9999) return 'No Expiry';

      final now = DateTime.now();
      final difference = expiry.difference(now);

      if (difference.isNegative) return 'Expired';

      if (difference.inHours < 24) {
        final hours = difference.inMinutes <= 60 ? 1 : difference.inHours + 1;
        return 'In $hours hour${hours > 1 ? 's' : ''}';
      }

      final days = difference.inDays;
      if (days == 1) return 'Tomorrow';
      return 'In ${days + 1} days';
    } catch (e) {
      return 'No Expiry';
    }
  }

  Color _getExpiryColor(String? expiryDate) {
    if (expiryDate == null || expiryDate.isEmpty || expiryDate == 'No Expiry') {
      return Colors.grey;
    }

    try {
      final expiry = DateTime.parse(expiryDate);
      if (expiry.year >= 9999) return Colors.grey;

      final now = DateTime.now();
      final difference = expiry.difference(now);

      if (difference.isNegative) return Colors.grey;
      if (difference.inHours < 24) return Colors.red;
      if (difference.inDays < 7) return Colors.orange;
      return Colors.green;
    } catch (e) {
      return Colors.grey;
    }
  }

  // ============ DOCUMENT CARD ============

  Widget _buildDocumentCard(
    BuildContext context,
    Document document,
    int index,
  ) {
    final r = context.r;
    final iconData = _getFileIcon(document.type);
    final color = _getFileColor(document.type);
    print("document upload date: ${document.name} - ${document.uploadDate}");
    String formattedDate = _formatDateDDMMYYYY(document.uploadDate);
    String uniqueKey = document.id.isNotEmpty ? document.id : 'doc_$index';
    bool isExpanded = _expandedStates[uniqueKey] ?? false;

    return InkWell(
      onTap: () => _handleDocumentDoubleTap(document),
      borderRadius: BorderRadius.circular(r.p(12)),
      child: Card(
        margin: EdgeInsets.symmetric(horizontal: r.p(16), vertical: r.p(8)),
        elevation: 0.5,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(r.p(12)),
        ),
        child: Padding(
          padding: EdgeInsets.all(r.p(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.all(r.p(12)),
                    decoration: BoxDecoration(
                      color: color.withAlpha(10),
                      borderRadius: BorderRadius.circular(r.p(8)),
                    ),
                    child: FileTypeIcon.orElse(
                      document.type,
                      r.sp(32),
                      Icon(iconData, color: color, size: r.sp(32)),
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
                                    style: TextStyle(
                                      fontSize: r.sp(16),
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: isExpanded ? 2 : 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    'Type: ${document.type} • $formattedDate',
                                    style: w400_14Poppins(
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Expand/Collapse Button
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _expandedStates[uniqueKey] = !isExpanded;
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                width: r.p(36),
                                height: r.p(36),
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
                                      size: r.sp(22),
                                      color: isExpanded
                                          ? color
                                          : Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: r.p(4)),
                            // More Options Button
                            IconButton(
                              onPressed: () =>
                                  _showDocumentActions(document, context),
                              icon: Container(
                                width: r.p(36),
                                height: r.p(36),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.more_vert,
                                    size: r.sp(20),
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

              // Collapsible Content
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: SizedBox(
                  height: isExpanded ? null : 0,
                  child: Column(
                    children: [
                      SizedBox(height: r.p(16)),
                      const Divider(height: 1),
                      SizedBox(height: r.p(12)),
                      if (document.keyword.isNotEmpty)
                        _buildDetailRowWithIcon(
                          'Keyword',
                          document.keyword,
                          Icons.label,
                          r: r,
                        ),
                      _buildDetailRowWithIcon(
                        (document.sharedViaGroupName != null &&
                                document.sharedViaGroupName!.trim().isNotEmpty)
                            ? 'Shared via'
                            : 'Shared by',
                        (document.sharedViaGroupName != null &&
                                document.sharedViaGroupName!.trim().isNotEmpty)
                            ? document.sharedViaGroupName!.trim()
                            : (document.sharedByName?.trim().isNotEmpty == true
                                  ? document.sharedByName!.trim()
                                  : document.owner),
                        (document.sharedViaGroupName != null &&
                                document.sharedViaGroupName!.trim().isNotEmpty)
                            ? Icons.groups_rounded
                            : Icons.person,
                        r: r,
                      ),
                      _buildDetailRowWithIcon(
                        'Folder',
                        document.folder,
                        Icons.folder,
                        r: r,
                      ),
                      _buildDetailRowWithIcon(
                        'Classification',
                        document.classification,
                        Icons.security,
                        r: r,
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.schedule,
                            size: r.sp(16),
                            color: Colors.grey.shade600,
                          ),
                          SizedBox(width: r.p(12)),
                          SizedBox(
                            width: r.p(100),
                            child: Text(
                              "Expires in: ",
                              style: w400_14Poppins(color: Colors.black87),
                            ),
                          ),
                          SizedBox(width: r.p(8)),
                          Expanded(
                            child: Text(
                              _getExpiryText(document.expiresAt),
                              style: w400_14Poppins(
                                color: _getExpiryColor(document.expiresAt),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (document.details.isNotEmpty)
                        _buildDetailRowWithIcon(
                          'Details',
                          document.details,
                          Icons.info_outline,
                          r: r,
                        ),
                      SizedBox(height: r.p(16)),
                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  _handleDocumentDoubleTap(document),
                              icon: Icon(Icons.visibility, size: r.sp(18)),
                              label: const Text('View'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.purple,
                                side: const BorderSide(color: Colors.purple),
                                padding: EdgeInsets.symmetric(
                                  vertical: r.p(10),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: r.p(8)),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _showDocumentVersions(document),
                              icon: Icon(Icons.history, size: r.sp(18)),
                              label: const Text('Versions'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.blue,
                                side: const BorderSide(color: Colors.blue),
                                padding: EdgeInsets.symmetric(
                                  vertical: r.p(10),
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

  // ============ LAYOUT MODES ============

  Widget _buildLayoutSelector() {
    return LayoutCapsule(
      value: _currentViewMode,
      onChanged: (mode) => setState(() => _currentViewMode = mode),
    );
  }

  Widget _buildDocumentsContent(List<Document> documents) {
    final mode = switch (_currentViewMode) {
      AppViewMode.grid2x2 => ResponsiveDocumentViewMode.grid2,
      AppViewMode.grid3x3 => ResponsiveDocumentViewMode.grid3,
      _ => ResponsiveDocumentViewMode.list,
    };
    return ResponsiveDocumentGallery(
      documents: documents,
      mode: mode,
      shrinkWrap: true,
      onView: _handleDocumentDoubleTap,
      onOverflow: (document, anchorContext, _) =>
          _showDocumentActions(document, anchorContext),
      onVersions: _showDocumentVersions,
      onDownload: _downloadDocument,
      onShare: _showShareDialog,
    );
    /* switch (_currentViewMode) {
      case AppViewMode.list:
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: documents.length,
          itemBuilder: (context, index) {
            return _buildDocumentCard(context, documents[index], index);
          },
        );
      case AppViewMode.grid2x2:
        return LayoutBuilder(
          builder: (context, constraints) {
            final r = ResponsiveHelper.of(context);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: r.p(12),
                mainAxisSpacing: r.p(12),
                childAspectRatio: 0.9,
              ),
              itemCount: documents.length,
              itemBuilder: (context, index) {
                return _buildDocumentGridItem(context, documents[index], index, 2);
              },
            );
          },
        );
      case AppViewMode.grid3x3:
        return LayoutBuilder(
          builder: (context, constraints) {
            final r = ResponsiveHelper.of(context);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: r.p(8),
                mainAxisSpacing: r.p(8),
                childAspectRatio: 0.85,
              ),
              itemCount: documents.length,
              itemBuilder: (context, index) {
                return _buildDocumentGridItem(context, documents[index], index, 3);
              },
            );
          },
        );
      case AppViewMode.compact:
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: documents.length,
          itemBuilder: (context, index) {
            return _buildDocumentCompactItem(context, documents[index], index);
          },
        );
      case AppViewMode.detailed:
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: documents.length,
          itemBuilder: (context, index) {
            return _buildDocumentDetailedItem(context, documents[index], index);
          },
        );
    } */
  }

  // Grid view item
  Widget _buildDocumentGridItem(
    BuildContext context,
    Document document,
    int index,
    int columns,
  ) {
    final r = context.r;
    final iconData = _getFileIcon(document.type);
    final color = _getFileColor(document.type);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(r.p(12)),
      ),
      child: InkWell(
        onTap: () => _handleDocumentDoubleTap(document),
        borderRadius: BorderRadius.circular(r.p(12)),
        child: Container(
          padding: EdgeInsets.all(r.p(8)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(r.p(8)),
                decoration: BoxDecoration(
                  color: color.withAlpha(20),
                  borderRadius: BorderRadius.circular(r.p(12)),
                ),
                child: FileTypeIcon.orElse(
                  document.type,
                  columns == 2 ? r.sp(26) : r.sp(18),
                  Icon(
                    iconData,
                    color: color,
                    size: columns == 2 ? r.sp(26) : r.sp(18),
                  ),
                ),
              ),
              SizedBox(height: r.p(6)),
              Flexible(
                child: Text(
                  document.name,
                  style: TextStyle(
                    fontSize: columns == 2 ? r.sp(11) : r.sp(9),
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: columns == 2 ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(height: r.p(2)),
              Text(
                document.type,
                style: TextStyle(
                  fontSize: columns == 2 ? r.sp(9) : r.sp(8),
                  color: Colors.grey.shade600,
                ),
              ),
              if (columns == 2) ...[
                SizedBox(height: r.p(2)),
                Text(
                  _formatDateDDMMYYYY(document.uploadDate),
                  style: TextStyle(
                    fontSize: r.sp(8),
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Compact view item
  Widget _buildDocumentCompactItem(
    BuildContext context,
    Document document,
    int index,
  ) {
    final r = context.r;

    return Container(
      margin: EdgeInsets.only(bottom: r.p(4)),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(r.p(6)),
        elevation: 0.5,
        child: InkWell(
          onTap: () => _handleDocumentDoubleTap(document),
          borderRadius: BorderRadius.circular(r.p(6)),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: r.p(8), vertical: r.p(8)),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(r.p(6)),
              border: Border.all(color: Colors.grey.shade100, width: 1),
            ),
            child: Row(
              children: [
                Icon(
                  _getFileIcon(document.type),
                  color: _getFileColor(document.type),
                  size: r.sp(18),
                ),
                width10,
                Expanded(
                  child: Text(
                    document.name,
                    style: TextStyle(fontSize: r.sp(14)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(width: r.p(8)),
                Text(
                  _formatDateDDMMYYYY(document.uploadDate),
                  style: TextStyle(
                    fontSize: r.sp(11),
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Detailed view item
  Widget _buildDocumentDetailedItem(
    BuildContext context,
    Document document,
    int index,
  ) {
    final r = context.r;
    final iconData = _getFileIcon(document.type);
    final color = _getFileColor(document.type);

    return Card(
      elevation: 2,
      margin: EdgeInsets.only(bottom: r.p(8)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(r.p(12)),
      ),
      child: InkWell(
        onTap: () => _handleDocumentDoubleTap(document),
        borderRadius: BorderRadius.circular(r.p(12)),
        child: Container(
          padding: EdgeInsets.all(r.p(8)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.all(r.p(8)),
                    decoration: BoxDecoration(
                      color: color.withAlpha(20),
                      borderRadius: BorderRadius.circular(r.p(10)),
                    ),
                    child: FileTypeIcon.orElse(
                      document.type,
                      r.sp(24),
                      Icon(iconData, color: color, size: r.sp(24)),
                    ),
                  ),
                  SizedBox(width: r.p(12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          document.name,
                          style: TextStyle(
                            fontSize: r.sp(14),
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: r.p(4)),
                        Wrap(
                          spacing: r.p(8),
                          runSpacing: r.p(4),
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.person,
                                  size: r.sp(12),
                                  color: Colors.grey,
                                ),
                                SizedBox(width: r.p(4)),
                                Flexible(
                                  child: Text(
                                    document.owner,
                                    style: TextStyle(
                                      fontSize: r.sp(11),
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
                                  size: r.sp(12),
                                  color: Colors.grey,
                                ),
                                SizedBox(width: r.p(4)),
                                Flexible(
                                  child: Text(
                                    document.folder,
                                    style: TextStyle(
                                      fontSize: r.sp(11),
                                      color: Colors.grey.shade600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        SizedBox(height: r.p(4)),
                        Wrap(
                          spacing: r.p(8),
                          runSpacing: r.p(4),
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.calendar_today,
                                  size: r.sp(12),
                                  color: Colors.grey,
                                ),
                                SizedBox(width: r.p(4)),
                                Text(
                                  _formatDateDDMMYYYY(document.uploadDate),
                                  style: TextStyle(
                                    fontSize: r.sp(11),
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
                                  size: r.sp(12),
                                  color: Colors.grey,
                                ),
                                SizedBox(width: r.p(4)),
                                Text(
                                  document.classification,
                                  style: TextStyle(
                                    fontSize: r.sp(11),
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
                    onPressed: () => _showDocumentActions(document, context),
                    icon: Container(
                      width: r.p(32),
                      height: r.p(32),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.more_vert,
                        size: r.sp(16),
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: r.p(12)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _handleDocumentDoubleTap(document),
                      icon: Icon(
                        Icons.visibility,
                        size: r.sp(14),
                        color: Colors.purple,
                      ),
                      label: Text(
                        'View',
                        style: TextStyle(
                          fontSize: r.sp(12),
                          color: Colors.purple,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.purple),
                        padding: EdgeInsets.symmetric(vertical: r.p(6)),
                      ),
                    ),
                  ),
                  SizedBox(width: r.p(6)),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showDocumentVersions(document),
                      icon: Icon(
                        Icons.history,
                        size: r.sp(14),
                        color: Colors.blue,
                      ),
                      label: Text(
                        'Versions',
                        style: TextStyle(
                          fontSize: r.sp(12),
                          color: Colors.blue,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.blue),
                        padding: EdgeInsets.symmetric(vertical: r.p(6)),
                      ),
                    ),
                  ),
                  SizedBox(width: r.p(6)),
                  Expanded(
                    child: document.allowDownload
                        ? OutlinedButton.icon(
                            onPressed: () => _downloadDocument(document),
                            icon: Icon(
                              Icons.download,
                              size: r.sp(14),
                              color: Colors.green,
                            ),
                            label: Text(
                              'Download',
                              style: TextStyle(
                                fontSize: r.sp(12),
                                color: Colors.green,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.green),
                              padding: EdgeInsets.symmetric(vertical: r.p(6)),
                            ),
                          )
                        : ElevatedButton.icon(
                            onPressed: () =>
                                _showDownloadRestrictedPopup(context, document),
                            icon: Icon(
                              Icons.download,
                              size: r.sp(14),
                              color: Colors.grey.shade300,
                            ),
                            label: Text(
                              'Download',
                              style: TextStyle(
                                fontSize: r.sp(12),
                                color: Colors.grey.shade300,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey.shade200,
                              foregroundColor: Colors.grey.shade300,
                              padding: EdgeInsets.symmetric(vertical: r.p(6)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(r.p(8)),
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
    );
  }

  // ============ FILE TYPE FILTER BADGE ============

  Widget _buildFileTypeBadge(ResponsiveHelper r) {
    if (_selectedFileType == 'All') return const SizedBox.shrink();

    return Container(
      margin: EdgeInsets.only(left: r.p(8)),
      padding: EdgeInsets.symmetric(horizontal: r.p(8), vertical: r.p(4)),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(r.p(16)),
        border: Border.all(color: Colors.blue.shade200, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getFileIcon(_selectedFileType),
            size: r.sp(14),
            color: _getFileColor(_selectedFileType),
          ),
          SizedBox(width: r.p(6)),
          Text(
            _selectedFileType,
            style: TextStyle(fontSize: r.sp(12), color: Colors.blue.shade800),
          ),
          SizedBox(width: r.p(4)),
          GestureDetector(
            onTap: () {
              setState(() {
                _selectedFileType = 'All';
                _filterDocuments(fileType: 'All');
              });
            },
            child: Icon(
              Icons.close,
              size: r.sp(14),
              color: Colors.blue.shade800,
            ),
          ),
        ],
      ),
    );
  }

  void _showDownloadRestrictedPopup(BuildContext context, Document document) {
    showDialog(
      context: context,
      builder: (context) {
        final r = context.r;
        return AlertDialog(
          icon: Icon(
            Icons.download_outlined,
            size: r.sp(48),
            color: Colors.blue,
          ),
          title: const Text('Download Document'),
          content: const Text(
            'For security purposes, library documents require approval for downloading. '
            'Please reach out to your team administrator or the document owner '
            'to request download permissions.\n\n'
            'In the meantime, you can preview the document using the "View" option.',
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Understand'),
            ),
            ElevatedButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(context);
                final service = DownloadRequestsService();
                final result = await service.createRequest(
                  documentId: document.id,
                  reason: 'Requesting download access',
                );
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      result['success'] == true
                          ? 'Download request submitted'
                          : (result['message'] ?? 'Request failed'),
                    ),
                    backgroundColor: result['success'] == true
                        ? Colors.green
                        : Colors.red,
                  ),
                );
              },
              child: const Text('Request Download'),
            ),
          ],
        );
      },
    );
  }

  // ============ SECTION HEADER ============

  /// Shared folders as a list or 2x2 / 3x3 grid, sized to fit a panel.
  Widget _buildFolderSectionBody() {
    if (_currentViewMode == AppViewMode.list) {
      return Column(
        children: [
          for (final folder in _filteredFolders) _buildFolderCard(folder),
        ],
      );
    }
    final isThreeColumn = _currentViewMode == AppViewMode.grid3x3;
    return GridView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _filteredFolders.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isThreeColumn ? 3 : 2,
        crossAxisSpacing: isThreeColumn ? 8 : 12,
        mainAxisSpacing: 12,
        childAspectRatio: isThreeColumn ? 0.88 : 1.08,
      ),
      itemBuilder: (context, index) =>
          _buildSharedFolderGridCard(_filteredFolders[index]),
    );
  }

  Widget _buildSectionHeader(String title, int count, IconData icon) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.indigo),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.indigo,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.indigo.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.indigo,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============ FOLDER CARD ============

  Future<void> _showFolderActions(
    SharedFolder folder,
    BuildContext anchorContext,
  ) async {
    final action = await showMenu<String>(
      context: anchorContext,
      position: _menuPositionBelow(anchorContext),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: const [
        PopupMenuItem(
          value: 'details',
          height: 46,
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, color: Color(0xFF2563EB)),
              SizedBox(width: 10),
              Text('Folder Details'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'download',
          height: 46,
          child: Row(
            children: [
              Icon(Icons.archive_outlined, color: Color(0xFF2563EB)),
              SizedBox(width: 10),
              Text('Download as ZIP'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'share',
          height: 46,
          child: Row(
            children: [
              Icon(Icons.share_outlined, color: Color(0xFF2563EB)),
              SizedBox(width: 10),
              Text('Share Folder'),
            ],
          ),
        ),
      ],
    );

    if (!mounted) return;
    switch (action) {
      case 'details':
        await _showFolderDetails(folder);
        break;
      case 'download':
        await _downloadSharedFolder(folder);
        break;
      case 'share':
        await _shareFolder(folder);
        break;
    }
  }

  Future<void> _showFolderDetails(SharedFolder folder) async {
    _showSnackBar('Loading folder details...', Colors.blue);
    final result = await _sharedFoldersService.getSharedFolderContents(
      folder.id,
    );
    if (!mounted) return;

    if (result['success'] != true) {
      _showSnackBar(
        result['error']?.toString() ?? 'Failed to load folder details',
        Colors.red,
      );
      return;
    }

    final folderData = result['folder'] is Map
        ? Map<String, dynamic>.from(result['folder'] as Map)
        : <String, dynamic>{};
    final shareData = result['share'] is Map
        ? Map<String, dynamic>.from(result['share'] as Map)
        : <String, dynamic>{};
    final documents = result['documents'] is List
        ? (result['documents'] as List)
        : const [];
    final subfolders = result['folders'] is List
        ? (result['folders'] as List)
        : const [];
    final fileCount = folder.itemCount >= 0
        ? folder.itemCount
        : documents.length;
    final lastModified =
        folderData['updated_at'] ??
        folderData['modified_at'] ??
        folderData['last_modified'];

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.folder_rounded, color: Color(0xFF2583EA)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                folder.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Owner', folder.owner),
              _buildDetailRow('Created', folder.createdAt),
              if (lastModified != null)
                _buildDetailRow(
                  'Last Modified',
                  _formatDateDDMMYYYY(lastModified),
                ),
              _buildDetailRow('Files', '$fileCount'),
              _buildDetailRow('Subfolders', '${subfolders.length}'),
              _buildDetailRow(
                'Download Access',
                folder.canDownload ? 'Allowed' : 'Restricted',
              ),
              _buildDetailRow(
                'Upload Access',
                folder.canUpload ? 'Allowed' : 'Restricted',
              ),
              _buildDetailRow(
                'Share Access',
                folder.canShare ? 'Allowed' : 'Restricted',
              ),
              _buildDetailRow(
                'Sharing Status',
                shareData.isNotEmpty ? 'Shared with you' : 'Shared folder',
              ),
              _buildDetailRow('Expires', _getExpiryText(folder.expiresAt)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadSharedFolder(SharedFolder folder) async {
    if (!ApiService.isConnected) {
      _showSnackBar('Cannot download while offline', Colors.orange);
      return;
    }
    if (!folder.canDownload) {
      _showSnackBar(
        'You do not have permission to download this folder',
        Colors.orange,
      );
      return;
    }

    setState(() => _isDownloading = true);
    try {
      final result = await FolderDownloadService()
          .downloadFolderAsZipWithAccess(
            folderId: folder.id,
            folderNameHint: folder.name,
          );
      if (result['requiresApproval'] == true) {
        _showSnackBar(
          result['requestCreated'] == true
              ? 'Download request sent for approval'
              : (result['message']?.toString() ?? 'Download approval required'),
          Colors.orange,
        );
      } else if (result['success'] == true && result['filePath'] != null) {
        await DownloadFeedback.showDownloadedDialog(
          context,
          filename: result['filename']?.toString() ?? '${folder.name}.zip',
          filePath: result['filePath'].toString(),
        );
      } else {
        _showSnackBar(
          result['error']?.toString() ?? 'Folder download failed',
          Colors.red,
        );
      }
    } catch (error) {
      _showSnackBar('Folder download failed: $error', Colors.red);
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<void> _shareFolder(SharedFolder folder) async {
    if (!ApiService.isConnected) {
      _showSnackBar('Cannot share while offline', Colors.orange);
      return;
    }
    if (!folder.canShare) {
      _showSnackBar(
        'You do not have permission to share this folder',
        Colors.orange,
      );
      return;
    }
    await ShareAccessSheet.showForFolder(
      context: context,
      folderId: folder.id,
      folderName: folder.name,
    );
  }

  Widget _buildFolderCard(SharedFolder folder) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE1E7F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SharedFolderScreen(
                folderId: folder.id,
                folderName: folder.name,
                userName: folder.owner,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const FolderIllustration(size: 36),
              ),
              const SizedBox(width: 12),
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
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Owner: ${folder.owner}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${folder.itemCount < 0 ? 0 : folder.itemCount} items',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Created: ${folder.createdAt}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: RichText(
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            text: TextSpan(
                              text: 'Expires: ',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 13,
                              ),
                              children: [
                                TextSpan(
                                  text: _getExpiryText(folder.expiresAt),
                                  style: TextStyle(
                                    color: _getExpiryColor(folder.expiresAt),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Builder(
                builder: (buttonContext) => IconButton(
                  tooltip: 'Folder actions',
                  onPressed: () => _showFolderActions(folder, buttonContext),
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    color: Color(0xFF102A56),
                    size: 26,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSharedFolderGridCard(SharedFolder folder) {
    return FolderTile(
      title: folder.name,
      details: [
        '${folder.itemCount < 0 ? 0 : folder.itemCount} items',
        'Owner: ${folder.owner}',
      ],
      frontTop: 0.4,
      tabWidth: 0.34,
      titleSize: 15,
      detailSize: 11.5,
      titleLines: 2,
      radius: BorderRadius.circular(20),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SharedFolderScreen(
            folderId: folder.id,
            folderName: folder.name,
            userName: folder.owner,
          ),
        ),
      ),
      menu: Builder(
        builder: (buttonContext) => IconButton(
          tooltip: 'Folder actions',
          onPressed: () => _showFolderActions(folder, buttonContext),
          icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF64748B)),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
      ),
    );
  }

  // ============ EMPTY STATE ============

  Widget _buildEmptyState(ResponsiveHelper r) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_searchController.text.isEmpty)
            ShareEmptyIllustration(size: r.sp(64))
          else
            Icon(
              Icons.search_off,
              size: r.sp(58),
              color: const Color(0xFF0866E9),
            ),
          SizedBox(height: r.p(20)),
          Text(
            _searchController.text.isEmpty
                ? (_hasError
                      ? 'Unable to Load Data'
                      : 'No Documents Received Yet')
                : 'No Results Found',
            style: TextStyle(
              fontSize: r.sp(20),
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: r.p(10)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: r.p(40)),
            child: Text(
              _hasError
                  ? _errorMessage
                  : _searchController.text.isEmpty
                  ? 'Files and documents shared with you by end users will appear here.'
                  : 'No results found for "${_searchController.text}"',
              style: TextStyle(fontSize: r.sp(14), color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: r.p(20)),
          if (_searchController.text.isNotEmpty)
            ElevatedButton.icon(
              onPressed: _clearSearch,
              icon: const Icon(Icons.clear_all),
              label: const Text('Clear Search'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0866E9),
                foregroundColor: Colors.white,
              ),
            )
          else if (_hasError)
            ElevatedButton.icon(
              onPressed: _loadSharedData,
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

  void _showSnackBar(String message, Color backgroundColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ============ DOWNLOADING BANNER ============

  Widget _buildDownloadingBanner(ResponsiveHelper r) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: r.p(8), horizontal: r.p(16)),
      color: Colors.green[50],
      child: Row(
        children: [
          SizedBox(
            width: r.p(20),
            height: r.p(20),
            child: const CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: r.p(12)),
          Expanded(
            child: Text(
              'Downloading document...',
              style: TextStyle(
                color: const Color.fromARGB(255, 57, 170, 57),
                fontSize: r.sp(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============ BUILD ============

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final bool bothEmpty =
        _filteredFolders.isEmpty && _filteredDocuments.isEmpty;

    return DismissKeyboard(
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F9FF),
        body: ResponsivePage(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(r.p(20), r.p(12), r.p(20), 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('DELEGATED ACCESS', style: TextStyle(color: Color(0xFF6D82A1), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
                          SizedBox(height: 3),
                          Text('Received Workspace', style: TextStyle(color: Color(0xFF202A4A), fontSize: 16, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                    Text('Clearance managed', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              // ── Search bar + layout toggle ──────────────────────────────
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: r.p(16),
                  vertical: r.p(10),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: PillSearchField(
                            controller: _searchController,
                            hint: 'Search shared workspace...',
                            onChanged: (value) =>
                                _filterDocuments(searchQuery: value),
                            onClear: _clearSearch,
                            onSubmitted: (value) =>
                                _filterDocuments(searchQuery: value),
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
                        SizedBox(width: r.p(10)),
                        _buildLayoutSelector(),
                      ],
                    ),
                    SizedBox(height: r.p(8)),
                    // Stats row
                    Row(
                      children: [
                        Text(
                          '${_filteredFolders.length} folder${_filteredFolders.length == 1 ? '' : 's'}  •  '
                          '${_filteredDocuments.length} file${_filteredDocuments.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: r.sp(13),
                          ),
                        ),
                        _buildFileTypeBadge(r),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Downloading banner ──────────────────────────────────────
              if (_isDownloading) _buildDownloadingBanner(r),

              // ── Main content ────────────────────────────────────────────
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
                        height10,
                        Text(
                          'Loading shared documents...',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                )
              else if (bothEmpty)
                Expanded(child: _buildEmptyState(r))
              else
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadSharedData,
                    color: Colors.indigo,
                    child: CustomScrollView(
                      slivers: [
                        // ── Folders section ─────────────────────────────
                        if (_filteredFolders.isNotEmpty) ...[
                          SliverToBoxAdapter(
                            child: SectionPanel(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              header: _buildSectionHeader(
                                'Shared Folders',
                                _filteredFolders.length,
                                Icons.folder_open,
                              ),
                              child: _buildFolderSectionBody(),
                            ),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 14)),
                        ],

                        // ── Files section ────────────────────────────────
                        if (_filteredDocuments.isNotEmpty) ...[
                          SliverToBoxAdapter(
                            child: SectionPanel(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              header: _buildSectionHeader(
                                'Delegated Files',
                                _filteredDocuments.length,
                                Icons.file_copy_outlined,
                              ),
                              child: _buildDocumentsContent(
                                _filteredDocuments,
                              ),
                            ),
                          ),
                        ],

                        const SliverToBoxAdapter(child: SizedBox(height: 24)),
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
}
