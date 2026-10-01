import 'dart:async';
import 'dart:io';

import 'package:digi_sanchika/local_storage.dart';
import 'package:digi_sanchika/models/document.dart';
import 'package:digi_sanchika/models/folder.dart';
import 'package:digi_sanchika/models/folder_tree_node.dart';
import 'package:digi_sanchika/presentations/Screens/document_scan_screen.dart';
import 'package:digi_sanchika/presentations/Screens/recent_activity_widget.dart';
import 'package:digi_sanchika/presentations/Screens/shared_with_me_screen.dart';
import 'package:digi_sanchika/presentations/Screens/upload_document.dart';
import 'package:digi_sanchika/services/api_service.dart';
import 'package:digi_sanchika/services/document_opener_service.dart';
import 'package:digi_sanchika/services/favorites_service.dart';
import 'package:digi_sanchika/services/folder_operations_service.dart';
import 'package:digi_sanchika/services/folder_tree_service.dart';
import 'package:digi_sanchika/services/my_documents_service.dart';
import 'package:digi_sanchika/services/shared_documents_service.dart';
import 'package:digi_sanchika/utils/app_fonts.dart';
import 'package:digi_sanchika/utils/responsive_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:path/path.dart' as path;

class DashboardScreen extends StatefulWidget {
  final Function(Document) onDocumentUploaded;
  final List<Folder> folders;
  final String? userName;
  final VoidCallback? onViewAll;
  const DashboardScreen({super.key, required this.onDocumentUploaded,
    required this.folders,
    this.userName,
    this.onViewAll,});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Document>? _apiSearchResults;
  final FocusNode _searchFocusNode = FocusNode();
  final FavoritesService _favoritesService = FavoritesService();
  final FolderTreeService _treeService = FolderTreeService();
  final FolderOperationsService _opsService = FolderOperationsService();
  final TextEditingController _folderNameController = TextEditingController();
  List<FolderTreeNode> _rootFolders = [];
  FolderTreeNode? _currentFolder;
  final SharedDocumentsService _sharedService = SharedDocumentsService();
  List<Document> sharedDocuments = [];


  bool _didChange = false; // Used to notify previous screen to refresh.

  bool _isSearching = false;
  String? _searchError;
  String _lastSemanticQuery = '';
  
  Timer? _searchDebounce;
  bool _showRecent = false;

  bool _isLoading = true;

  List<Document> allDocuments = [];
  
     List<Document> semanticDocs=[];
     List<Document> normalOnlyDocs =[];
  final Map<String, String> _folderPathCache = {};

Future<void> _loadSharedDocuments() async {
  try {
    final response = await _sharedService.fetchSharedDocuments();

    if (!mounted) return;

    setState(() {
      sharedDocuments = response.documents.take(5).toList();
    });

    print("Shared docs: ${sharedDocuments.length}");
  } catch (e) {
    print("Shared documents error: $e");
  }
}
  
  void _clearSearch() {
    _searchController.clear();
    _dismissKeyboard();
    setState(() {
      _apiSearchResults = null;
      _isSearching = false;
      _searchError = null;
      _lastSemanticQuery = '';
    });
  }
  String get activeQuery => _searchController.text.trim();


  
  // ADD THIS METHOD
  void _dismissKeyboard() {
    // Dismiss keyboard if search field has focus
    if (_searchFocusNode.hasFocus) {
      _searchFocusNode.unfocus();
    }

    // Also dismiss any other keyboard
    FocusManager.instance.primaryFocus?.unfocus();
  }

  List<Document> get filteredDocuments => activeQuery.isEmpty
        ? _getFilteredDocuments().take(5).toList()
        : const <Document>[];

         List<Document> _getFilteredDocuments() {
    // Home page shows only documents in the root ("Home") context.
    // Documents uploaded into a specific folder should appear only inside that folder,
    // not in the root document list.
    bool isHomeDoc(Document d) {
      final folderId = d.folderId?.trim();
      if (folderId != null && folderId.isNotEmpty) return false;

      final folderName = d.folder.trim().toLowerCase();
      return folderName.isEmpty || folderName == 'home';
    }

    List<Document> allDocs = allDocuments.where(isHomeDoc).toList();

    // Apply type filter
   

    if (_showRecent) {
      allDocs.sort((a, b) => b.uploadDate.compareTo(a.uploadDate));
      return allDocs.take(10).toList();
    }

    final searchTerm = _searchController.text.toLowerCase();
    if (searchTerm.isEmpty) {
      return allDocs;
    }

    return allDocs.where((doc) {
      return doc.name.toLowerCase().contains(searchTerm) ||
          doc.keyword.toLowerCase().contains(searchTerm) ||
          doc.type.toLowerCase().contains(searchTerm) ||
          doc.owner.toLowerCase().contains(searchTerm) ||
          doc.classification.toLowerCase().contains(searchTerm) ||
          doc.folder.toLowerCase().contains(searchTerm);
    }).toList();
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

   String _extractFileType(String filename) {
    final ext = path.extension(filename).toLowerCase();
    switch (ext) {
      case '.pdf':
        return 'PDF';
      case '.doc':
      case '.docx':
        return 'DOCX';
      case '.xls':
      case '.xlsx':
        return 'XLSX';
      case '.ppt':
      case '.pptx':
        return 'PPTX';
      case '.txt':
        return 'TXT';
      default:
        return ext.replaceAll('.', '').toUpperCase();
    }
  }

  String? _effectiveUserName;


   Document _documentFromDetails(Map details) {
    final name =
        details['name'] ??
        details['original_filename'] ??
        details['file_name'] ??
        details['original_name'] ??
        details['filename'] ??
        'Document';

    final mimeType = details['mime_type']?.toString();
    final fileType = mimeType != null && mimeType.isNotEmpty
        ? _extractFileTypeFromMime(mimeType, name.toString())
        : _extractFileType(name.toString());

    return Document(
      id: (details['id'] ?? '').toString(),
      name: name.toString(),
      type: fileType,
      size:
          '${details['file_size_bytes'] ?? details['file_size'] ?? details['size'] ?? 'Unknown'} bytes',
      keyword: (details['keywords'] ?? '').toString(),
      uploadDate: _formatDate(details['created_at'] ?? details['updated_at']),
      owner:
          (details['owner'] is Map ? (details['owner']['name'] ?? '') : '')
              ?.toString() ??
          (details['created_by'] ?? details['uploaded_by'] ?? 'Unknown')
              .toString(),
      details: (details['remarks'] ?? details['details'] ?? '').toString(),
      classification:
          (details['classification'] ?? details['doc_class'] ?? 'internal')
              .toString(),
      allowDownload:
          details['allow_download'] ?? details['allowDownload'] ?? true,
      sharingType:
          (details['is_public'] == true ||
              details['classification']?.toString().toLowerCase() == 'public')
          ? 'Public'
          : 'Private',
      folder: (details['folder_path'] ?? details['folder'] ?? 'Home')
          .toString(),
      folderId:
          details['folder_id']?.toString() ?? details['folderId']?.toString(),
      path: name.toString(),
      fileType: fileType,
    );
  }

    String _formatDate(dynamic date) {
    try {
      DateTime parsedDate = DateTime.parse(date.toString());
      String day = parsedDate.day.toString().padLeft(2, '0');
      String month = parsedDate.month.toString().padLeft(2, '0');
      String year = parsedDate.year.toString();
      return '$day $month $year';
    } catch (e) {
      return date.toString();
    }
  }


    Future<void> _performSearch(String query) async {
    if (!ApiService.isConnected) return;
    setState(() => _isSearching = true);
    try {
      // Confirmed backend semantic endpoint/payload in `MyDocumentsService.semanticSearch`:
      // POST `/search/semantic` with `{ query, scope, limit }`.
      _lastSemanticQuery = query;

      final semantic = await MyDocumentsService.semanticSearch(
        query: query,
        scope: 'mine',
        limit: 30,
      );

      final results = semantic['results'];
      final semanticIds = results is List
          ? results
                .map(
                  (e) => e is Map
                      ? (e['documentId'] ?? e['document_id'] ?? '').toString()
                      : '',
                )
                .where((s) => s.trim().isNotEmpty)
                .toList()
          : const <String>[];

      final byId = {for (final d in allDocuments) d.id: d};
      final semanticDocs = <Document>[];
      final missingIds = <String>[];

      for (final id in semanticIds) {
        final d = byId[id];
        if (d != null) {
          semanticDocs.add(d);
        } else {
          missingIds.add(id);
        }
      }

      // If semantic returns IDs we haven't loaded (common for deep subfolders),
      // fetch details so semantic search works beyond root-level documents.
      for (final id in missingIds.take(20)) {
        try {
          final detailsResult = await MyDocumentsService.getDocumentDetails(id);
          if (detailsResult['success'] == true &&
              detailsResult['details'] is Map) {
            semanticDocs.add(
              _documentFromDetails(detailsResult['details'] as Map),
            );
          }
        } catch (_) {}
      }

      if (!mounted) return;

      if (semantic['success'] == true) {
        setState(() {
          _apiSearchResults = semanticDocs;
          _searchError = null;
        });
      } else {
        setState(() {
          _apiSearchResults = const [];
          _searchError = (semantic['error'] ?? 'Semantic search failed')
              .toString();
        });
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }
  
  void _onSearchChanged(String value) {
    setState(() {
      _showRecent = false;
      if (value.isEmpty) {
        _apiSearchResults = null;
        _searchError = null;
        _lastSemanticQuery = '';
      }
    });

    _searchDebounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) return;

    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _performSearch(q);
    });
  }

   Future<void> _loadDataFromLocalStorage() async {
    try {
      final localDocs = await LocalStorageService.loadDocuments();
      setState(() {
        allDocuments = localDocs;
        _organizeDocumentsIntoFolders();
      });
    } catch (e) {
      if (kDebugMode) {
        print('WARN Document load failed');
      }
    }
  }
  List<Folder> folders = [];

  void _organizeDocumentsIntoFolders() {
    for (var folder in folders) {
      folder.documents.clear();
    }

    if (folders.isEmpty || !folders.any((f) => f.name == 'Home')) {
      folders.insert(
        0,
        Folder(
          name: 'Home',
          id: 'home',
          documents: [],
          createdAt: DateTime.now(),
          owner: _displayUserName,
        ),
      );
    }

    final folderById = <String, Folder>{};
    for (final f in folders) {
      if (f.id.isNotEmpty) folderById[f.id] = f;
    }

    for (var document in allDocuments) {
      final folderId = document.folderId;
      if (folderId != null && folderById.containsKey(folderId)) {
        folderById[folderId]!.documents.add(document);
        continue;
      }

      final folderName = document.folder;
      if (folderName.isEmpty || folderName == 'Home') {
        final homeFolder = folders.firstWhere((f) => f.name == 'Home');
        homeFolder.documents.add(document);
        continue;
      }

      // Fallback for older payloads that don't include `folderId`.
      var folder = folders.firstWhere(
        (f) => f.name == folderName,
        orElse: () {
          final newFolder = Folder(
            name: folderName,
            id: folderId ?? 'folder_${DateTime.now().millisecondsSinceEpoch}',
            documents: [],
            createdAt: DateTime.now(),
            owner: _displayUserName,
          );
          folders.add(newFolder);
          folderById[newFolder.id] = newFolder;
          return newFolder;
        },
      );
      folder.documents.add(document);
    }
  }

   String get _displayUserName {
    if (_effectiveUserName != null && _effectiveUserName!.isNotEmpty) {
      return _effectiveUserName!;
    }
    if (widget.userName != null && widget.userName!.isNotEmpty) {
      return widget.userName!;
    }
    return 'User';
  }
  final Map<String, String> _favoriteDocumentMap = {};

Future<void> _loadFavorites() async {
    try {
      final items = await _favoritesService.listFavorites();
      if (!mounted) return;
      _favoriteDocumentMap
        ..clear()
        ..addEntries(
          items
              .where((i) => i.entityType.toLowerCase().contains('doc'))
              .map((i) => MapEntry(i.entityId, i.id)),
        );
      
      setState(() {});
    } catch (_) {}
  }

  

 Future<void> _refreshData() async {
    await ApiService.checkConnection();
    if (ApiService.isConnected) {
      // await _loadAllUserDocuments();
      await _loadFavorites();
    } else {
      await _loadDataFromLocalStorage();
      if (mounted) {
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.showSnackBar(
          const SnackBar(
            content: Text('You\'re offline. Showing saved data'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }


  @override
  void initState() {
    super.initState();
    folders = List.from(widget.folders);
    _loadInitialData();

  _loadSharedDocuments();
  }

  Future<void> _loadInitialData() async {
    await _loadDataFromLocalStorage();
    await ApiService.checkConnection();
    if (ApiService.isConnected) {
      await _loadFavorites();
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
child: Padding(
  padding: const EdgeInsets.all(16.0),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: _onSearchChanged,
                onSubmitted: (value) {
                  final q = value.trim();
                  if (q.isNotEmpty) {
                    _dismissKeyboard();
                    _performSearch(q);
                  }
                },
                textInputAction: TextInputAction.search,
                style: const TextStyle(
                  fontSize: 14,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w400,
                ),
                onTapOutside: (_) => _dismissKeyboard(),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  hintText: 'Search documents, people, tags…',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w400,
                    color: Colors.grey.shade500,
                  ),
                  prefixIcon: _isSearching
                      ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: const CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : const Icon(Icons.search, color: Colors.indigo, size: 22),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: _clearSearch,
                        )
                      : Icon(Icons.mic_none_rounded,
                          color: Colors.indigo, size: 22),
                  contentPadding: const EdgeInsets.symmetric(vertical: 13),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.indigo, width: 1.2),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Blue "+" action button
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UploadDocumentTab(
                    onDocumentUploaded: widget.onDocumentUploaded,
                    folders: widget.folders,
                    userName: widget.userName,
                  ),
                ),
              ),
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.indigo,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 26),
              ),
            ),
          ],
        ),
        height15,
        Row(
          children: [
            UploadDocument(
              icon: Icons.upload_outlined,
              title: "Upload",
              subtitle: "Document",
              iconBackground: const Color.fromARGB(255, 224, 228, 253),
              iconColor: Colors.indigo,
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => UploadDocumentTab(onDocumentUploaded: widget.onDocumentUploaded, folders: widget.folders, userName: widget.userName)));
              },
            ),
            const SizedBox(width: 10),
            UploadDocument(
              icon: Icons.qr_code_scanner,
              title: "Scan",
              subtitle: "Document",
              iconBackground: const Color.fromARGB(255, 228, 251, 228),
              iconColor: Colors.green,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DocumentScanScreen(
                      onScannedFileReady: (File savedFile) {},
                      folders: widget.folders,
                      userName: widget.userName,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 10),
            UploadDocument(
              icon: Icons.folder_open,
              title: "New Folder",
              subtitle: "Create",
              iconBackground: const Color.fromARGB(255, 253, 238, 215),
              iconColor: Colors.orange,
              onTap: () {
                _createFolder(_currentFolder);
              },
            ),
          ],
        ),
        height15,
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'Recent Documents',
              style: TextStyle(
                fontSize: 18,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w800,
                color: Colors.black,
                letterSpacing: -0.2,
              ),
            ),
            InkWell(
              onTap: widget.onViewAll,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  children: const [
                    Text(
                      'View all',
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        color: Colors.indigo,
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(Icons.chevron_right, color: Colors.indigo, size: 18),
                  ],
                ),
              ),
            ),
          ],
        ),
        height10,
         RefreshIndicator(
           onRefresh: _refreshData,
           child: Container(
          height: 170.h,
decoration: BoxDecoration(
  borderRadius: BorderRadius.circular(12),
  color: Colors.white
),
             child: ListView(
              physics: const NeverScrollableScrollPhysics(),
               padding: EdgeInsets.all((14)),
               children: [
                 if (activeQuery.isEmpty)
                   _buildDocumentsSection(filteredDocuments)
                 else
                   _buildSearchDocumentsSection(
                     query: activeQuery,
                     semanticDocs: semanticDocs,
                     normalOnlyDocs: normalOnlyDocs,
                   ),
               ],
             ),
           ),
         ),
    height10,
    sharedDocuments.length ==0?SizedBox():
      Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Shared with me',
              style: TextStyle(
                fontSize: 18,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w800,
                color: Colors.black,
                letterSpacing: -0.2,
              ),
            ),
            InkWell(
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => SharedWithMeScreen()));
              },
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  children:  [
                    Text(
                      'View all',
                      style:w500_14Poppins(color: Colors.indigo
                      )
                    ),
                    SizedBox(width: 2),
                    Icon(Icons.chevron_right, color: Colors.indigo, size: 18),
                  ],
                ),
              ),
            )
          ],
        ),
        height10,
        Container(
          height: sharedDocuments.length ==1?50.h:sharedDocuments.length==2?100.h:sharedDocuments.length==3?150.h: sharedDocuments.length ==0?0:150.h,
decoration: BoxDecoration(
  borderRadius: BorderRadius.circular(12),
  color: Colors.white
),
          child: ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sharedDocuments.length,
            itemBuilder: (context, index) {
              return _buildDocumentSharedCard(context, sharedDocuments[index], index);
            },
          ),
        ),
        height10,
//         Text(
//             'Activity',
//            style: w900_20Poppins(color: Colors.black)
//           ),
//           height10,
//         ActivityFeed(
//   activities: [
//     ActivityItem(
//       icon: Icons.check,
//       iconColor: Colors.green,
//       iconBackground: Colors.green.withOpacity(0.12),
//       textSpans:  [
//         TextSpan(text: 'You ',style:w400_15Poppins()),
//         TextSpan(text: 'approved', style:w700_15Poppins()),
//         TextSpan(text: " Ravi's edit request on ",style:w400_15Poppins()),
//         TextSpan(text: 'recuirement.pptx',  style:w700_15Poppins()),
//       ],
//       timeAgo: '18 minutes ago',
//     ),
//     ActivityItem(
//       icon: Icons.upload,
//       iconColor: Colors.indigo,
//       iconBackground: Colors.indigo.withOpacity(0.12),
//       textSpans:  [
//         TextSpan(text: 'You ',style:w400_15Poppins()),
//         TextSpan(text: 'uploaded', style:w700_15Poppins()),
//         TextSpan(text: ' 3 files to ',style:w400_15Poppins()),
//         TextSpan(text: 'Payroll', style:w700_15Poppins()),
//       ],
//       timeAgo: '2 hours ago',
//     ),
//     ActivityItem(
//       icon: Icons.share,
//       iconColor: Colors.purple,
//       iconBackground: Colors.purple.withOpacity(0.12),
//       textSpans:  [
//         TextSpan(text: 'Meera ',style:w400_15Poppins()),
//         TextSpan(text: 'shared', style: w700_16Poppins()),
//         TextSpan(text: ' Vendor Agreement.pdf with you',style:w400_15Poppins()),
//       ],
//       timeAgo: 'Yesterday',
//     ),
//     ActivityItem(
//       icon: Icons.edit,
//       iconColor: Colors.orange,
//       iconBackground: Colors.orange.withOpacity(0.12),
//       textSpans:  [
//         TextSpan(text: 'You ',style:w400_15Poppins()),
//         TextSpan(text: 'renamed', style: w700_16Poppins()),
//         TextSpan(text: ' Invoice_final.pdf to ',style:w400_15Poppins()),
//         TextSpan(text: 'Invoice March.pdf',style: w700_16Poppins()),
//       ],
//       timeAgo: '2 days ago',
//     ),
//   ],
// )
    ],
  ),
),
    );
  }

  final DocumentOpenerService _documentOpener = DocumentOpenerService();


  void _handleDocumentDoubleTap(Document document) {
    _documentOpener.openPreviewDialog(context: context, document: document);
  }

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

   String _formatDateDDMMYYYY(dynamic date) {
    try {
      if (date == null || date.toString().isEmpty) {
        return 'N/A';
      }

      final dateStr = date.toString().trim();

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


  Widget _buildDocumentSharedCard(BuildContext context, Document document, int index) {
    final iconData = _getFileIcon(document.type);
    final color = _getFileColor(document.type);
    final timeText = _getUpdatedText(document.updatedAt);

    return InkWell(
      onTap: () => _handleDocumentDoubleTap(document),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── File icon badge ────────────────────────────────────────
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(iconData, color: color, size: 24),
            ),
            const SizedBox(width: 12),

            // ── Name + sharer + time ───────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    document.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: w700_16Poppins()
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if ((document.sharedByName ?? '').isNotEmpty)
                        Container(
                          width: 16,
                          height: 16,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: Colors.indigo.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              (document.sharedByName ?? 'U')
                                  .substring(0, 1)
                                  .toUpperCase(),
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Colors.indigo,
                              ),
                            ),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          '${document.sharedByName ?? 'Someone'} shared · $timeText',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w400,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // ── Permission pill ────────────────────────────────────────
            Builder(builder: (_) {
              final permission = document.permission;
              if (permission == null || permission.isEmpty) {
                return const SizedBox.shrink();
              }
              Color pillColor;
              switch (permission) {
                case 'Can Edit':
                  pillColor = Colors.blue;
                  break;
                case 'Full Access':
                  pillColor = Colors.green;
                  break;
                default:
                  pillColor = Colors.grey.shade600;
              }
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: pillColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: pillColor.withOpacity(0.25)),
                ),
                child: Text(
                  permission,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    color: pillColor,
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

 String _getUpdatedText(String? updatedAt) {
  if (updatedAt == null || updatedAt.isEmpty) {
    return 'Never Updated';
  }

  try {
    final updated = DateTime.parse(updatedAt);
    final now = DateTime.now();
    final difference = now.difference(updated);

    if (difference.inMinutes < 1) {
      return 'Just now';
    }

    if (difference.inHours < 1) {
      return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
    }

    if (difference.inDays < 1) {
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    }

    if (difference.inDays == 1) {
      return 'Yesterday';
    }

    if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    }

    return '${updated.day.toString().padLeft(2, '0')}/'
        '${updated.month.toString().padLeft(2, '0')}/'
        '${updated.year}';
  } catch (_) {
    return updatedAt;
  }
}

Widget _buildSearchDocumentsSection({
    required String query,
    required List<Document> semanticDocs,
    required List<Document> normalOnlyDocs,
  }) {
    final r = context.r;

    Widget section(String title, List<Document> docs, {required String badge}) {
      if (docs.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: r.p(8)),
          Text(
            title,
            style: w900_15Poppins(color: Colors.black),
          ),
          SizedBox(height: r.p(10)),
          for (int i = 0; i < docs.length; i++)
            _buildDocumentCard(docs[i], i, searchModeLabel: badge),
        ],
      );
    }

    final hasAny = semanticDocs.isNotEmpty || normalOnlyDocs.isNotEmpty;

    if (_isSearching && !hasAny) {
      return _buildDocumentsLoadingState();
    }

    if (!hasAny) {
      return Padding(
        padding: EdgeInsets.only(top: r.p(22)),
        child: Center(
          child: Text(
            'No results for "$query"',
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_searchError != null)
          Padding(
            padding: EdgeInsets.only(bottom: r.p(10)),
            child: Text(
              _searchError!,
              style: TextStyle(color: Colors.orange.shade800),
            ),
          ),
        section('Semantic results', semanticDocs, badge: 'Semantic'),
        section('Normal results', normalOnlyDocs, badge: 'Normal'),
      ],
    );
  }

String _folderPathForId(String? folderId) {
    final id = (folderId ?? '').trim();
    if (id.isEmpty) return '';
    final cached = _folderPathCache[id];
    if (cached != null) return cached;

    final byId = <String, Folder>{for (final f in folders) f.id: f};
    final parts = <String>[];
    Folder? node = byId[id];

    var safety = 0;
    while (node != null && safety < 100) {
      safety++;
      final name = node.name.trim();
      if (name.isNotEmpty) parts.add(name);
      final parentId = (node.parentId ?? '').trim();
      if (parentId.isEmpty) break;
      node = byId[parentId];
    }

    final path = parts.reversed.join(' / ');
    _folderPathCache[id] = path;
    return path;
  }


String _documentDirectoryPath(Document document) {
    final fromId = _folderPathForId(document.folderId).trim();
    if (fromId.isNotEmpty) return fromId;
    final fallback = document.folder.trim();
    return fallback.isEmpty ? 'Unknown folder' : fallback;
  }

   String _formatToDDMMYYYY(String dateString) {
    try {
      // Try to parse the date string
      DateTime date = DateTime.parse(dateString);

      // Format as DD MM YYYY
      String day = date.day.toString().padLeft(2, '0');
      String month = date.month.toString().padLeft(2, '0');
      String year = date.year.toString();

      return '$day $month $year';
    } catch (e) {
      // If parsing fails, return the original string
      return dateString;
    }
  }

 Widget _buildDocumentCard(
    Document document,
    int index, {
    String? searchModeLabel,
  }) {
    final r = context.r;
    // final docIcons = {
    //   'PDF': Icons.picture_as_pdf,
    //   'DOCX': Icons.description,
    //   'XLSX': Icons.table_chart,
    //   'PPTX': Icons.slideshow,
    //   'TXT': Icons.text_snippet,
    //   'XLS': Icons.table_chart,
    //   'PPT': Icons.slideshow,
    //   'DOC': Icons.description,
    // };
    final docColors = {
      'PDF': Colors.red,
      'DOCX': Colors.blue,
      'XLSX': Colors.green,
      'PPTX': Colors.orange,
      'TXT': Colors.grey,
      'PPT': Colors.orange,
      'XLS': Colors.green,
      'DOC': Colors.blue,
    };

    String fileType = document.type.toUpperCase();
    // IconData icon = docIcons[fileType] ?? Icons.insert_drive_file;
    Color color = docColors[fileType] ?? Colors.indigo;

    // Format the date to DD MM YYYY
    String formattedDate = _formatToDDMMYYYY(document.uploadDate);
    final folderPath = _documentDirectoryPath(document);

    // Get document opener service instance
    final documentOpener = DocumentOpenerService();

    // IMPORTANT: Check if this specific document is expanded using its ID
    // bool isExpanded = _expandedStates[document.id] ?? false;

    final btnPad = EdgeInsets.symmetric(vertical: r.p(9));
    final btnIconSize = r.sp(16);

    return InkWell(
      onTap: () =>
          documentOpener.openViewer(context: context, document: document),
      borderRadius: BorderRadius.circular(r.p(12)),
      child: Card(
        margin: EdgeInsets.only(bottom: r.p(14)),
        elevation: 0.5,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(r.p(12)),
        ),
        child: Padding(
          padding: EdgeInsets.all(r.p(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  // File-type icon
                  Container(
                    padding: EdgeInsets.all(r.p(10)),
                    decoration: BoxDecoration(
                      color: color.withAlpha(20),
                      borderRadius: BorderRadius.circular(r.p(8)),
                    ),
                    child:  Text(
                          document.type,
                          style:w600_14Poppins(color:color ),
                        ),
                  ),
                  SizedBox(width: r.p(12)),
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
                                    style:w700_14Poppins(color:Colors.black ),
                                    maxLines:  1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                      SizedBox(height: r.p(3)),
                                  
                        Text(
                          formattedDate,
                          style:w500_14Poppins(color:Colors.grey.shade600 ),
                        ),
                        SizedBox(height: r.p(2)),
                        Text(
                          'Path: $folderPath / ${document.name}',
                          style: w400_13Poppins(color:Colors.grey.shade600 ),
                          maxLines:  1,
                          overflow: TextOverflow.ellipsis,
                        ),
                                ],
                              ),
                            ),
                          
                            
                            // Expand / collapse
                         
                            if (searchModeLabel != null) ...[
                              SizedBox(width: r.p(6)),
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: r.p(8),
                                  vertical: r.p(4),
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.indigo.withAlpha(18),
                                  borderRadius: BorderRadius.circular(r.p(999)),
                                ),
                                child: Text(
                                  searchModeLabel,
                                  style: TextStyle(
                                    fontSize: r.sp(10),
                                    fontWeight: FontWeight.w700,
                                    color: Colors.indigo,
                                  ),
                                ),
                              ),
                            ],
                        
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: (){},

                              // onPressed: () =>
                              //     _showDocumentActions(document, index),
                              icon: Container(
                                width: r.p(32),
                                height: r.p(32),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.more_vert,
                                    size: r.sp(18),
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

              // Collapsible details
           
            ],
          ),
        ),
      ),
    );
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

   Widget _buildCreateFolderDialog(FolderTreeNode? parent) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Create New Folder',
            style:w700_20Poppins()
          ),
          height5,
          Text("Give your new folder a name",style: w500_14Poppins(color: Colors.grey.shade400),)
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
            style: const TextStyle(fontSize: 15, ),
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
                color: Color(0xFF666666),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFFE0E0E0),
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
            shadowColor: const Color(0xFF2B41BD).withValues(alpha: 0.3),
          ),
        ),
      ],
    );
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
        _showSuccessSnackBar('Folder "$result" created successfully');
        await _loadFolderTree(showLoading: false);
      } else {
        _showErrorSnackBar(createResult['error'] ?? 'Failed to create folder');
      }

      setState(() => _isLoading = false);
    }
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

  IconData _getDocumentIcon(String fileType) {
    final docIcons = {
      'PDF': Icons.picture_as_pdf,
      'DOCX': Icons.description,
      'XLSX': Icons.table_chart,
      'PPTX': Icons.slideshow,
      'TXT': Icons.text_snippet,
      'XLS': Icons.table_chart,
      'PPT': Icons.slideshow,
      'DOC': Icons.description,
    };
    return docIcons[fileType.toUpperCase()] ?? Icons.insert_drive_file;
  }

  Color _getDocumentColor(String fileType) {
    final docColors = {
      'PDF': Colors.red,
      'DOCX': Colors.blue,
      'XLSX': Colors.green,
      'PPTX': Colors.orange,
      'TXT': Colors.grey,
      'PPT': Colors.orange,
      'XLS': Colors.green,
      'DOC': Colors.blue,
    };
    return docColors[fileType.toUpperCase()] ?? Colors.indigo;
  }

   Widget _buildDocumentsLoadingState() {
    Widget skeletonLine({double? width}) {
      return Container(
        height: 12,
        width: width,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(8),
        ),
      );
    }
     Widget skeletonCard() {
      return Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF2B41BD).withAlpha(18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.description_rounded,
                  color: Color(0xFF2B41BD),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    skeletonLine(width: 180),
                    const SizedBox(height: 10),
                    skeletonLine(width: 120),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Card(
          elevation: 0,
          color: const Color(0xFF2B41BD).withAlpha(18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Loading your documents…',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.indigo.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        skeletonCard(),
        skeletonCard(),
        skeletonCard(),
      ],
    );
   }
Widget _buildDocumentsEmptyState() {
    return Card(
      elevation: 0,
      color: Colors.grey.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFF2B41BD).withAlpha(16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.folder_open_rounded,
                color: Color(0xFF2B41BD),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'No documents yet',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Pull down to refresh, or upload a document to get started.',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }


   Widget _buildDocumentsSection(List<Document> documents) {
    const docColors = {
      'PDF': Colors.red,
      'DOCX': Colors.blue,
      'XLSX': Colors.green,
      'PPTX': Colors.orange,
      'TXT': Colors.grey,
      'PPT': Colors.orange,
      'XLS': Colors.green,
      'DOC': Colors.blue,
    };

    // Badge label abbreviation for the colored box (match design: PDF, W, X, etc.)
    String _badgeLabel(String type) {
      switch (type.toUpperCase()) {
        case 'DOCX':
        case 'DOC':
          return 'W';
        case 'XLSX':
        case 'XLS':
          return 'X';
        case 'PPTX':
        case 'PPT':
          return 'P';
        default:
          return type.toUpperCase().length > 4
              ? type.toUpperCase().substring(0, 4)
              : type.toUpperCase();
      }
    }

    Widget content;
    if (_isLoading && documents.isEmpty) {
      content = _buildDocumentsLoadingState();
    } else if (documents.isEmpty) {
      content = _buildDocumentsEmptyState();
    } else {
      final shown = documents.length > 3 ? 3 : documents.length;
      content = Column(
        children: [
          for (int i = 0; i < shown; i++)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => DocumentOpenerService().openPreviewDialog(
                context: context,
                document: documents[i],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // ── Colored letter badge ───────────────────
                    Builder(builder: (_) {
                      final fileType = documents[i].type.toUpperCase();
                      final color = (docColors[fileType] ?? Colors.indigo) as Color;
                      return Container(
                        height: 46,
                        width: 46,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _badgeLabel(documents[i].type),
                          style: TextStyle(
                            fontSize: 13,
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                      );
                    }),

                    const SizedBox(width: 12),

                    // ── Name + subtitle ────────────────────────
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            documents[i].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:w700_16Poppins(color:Colors.black ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _documentSubtitle(documents[i]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: w400_13Poppins(color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 8),

                    // ── Time + more button ─────────────────────
                  
                  ],
                ),
              ),
            ),
            // if (i < shown - 1)
            //   Divider(height: 1, color: Colors.grey.shade100),
        ],
      );
    }
    return content;
  }

  String _documentSubtitle(Document doc) {
    final folder = doc.folder.trim();
    final label = folder.isEmpty || folder.toLowerCase() == 'home' ? '' : folder;
    final shared = doc.sharingType == 'Public' ? 'Shared' : '';
    if (label.isNotEmpty && shared.isNotEmpty) return '$label · $shared';
    if (label.isNotEmpty) return label;
    if (shared.isNotEmpty) return shared;
    return doc.type.toUpperCase();
  }
    

    
   
  


  Widget UploadDocument({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color iconBackground,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w400,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  
}