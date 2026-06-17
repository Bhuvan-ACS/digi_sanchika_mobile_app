import 'dart:async';
import 'dart:io';
import 'package:digi_sanchika/utils/app_fonts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:digi_sanchika/services/api_client.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
// import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:digi_sanchika/local_storage.dart';
import 'package:digi_sanchika/models/document.dart';
import 'package:digi_sanchika/models/folder.dart';
import 'package:digi_sanchika/services/api_service.dart';
import 'package:digi_sanchika/services/token_storage.dart';
import 'package:digi_sanchika/services/my_documents_service.dart';
import 'package:digi_sanchika/presentations/Screens/upload_document.dart';
import 'package:digi_sanchika/presentations/Screens/folder_screen.dart';
import 'package:digi_sanchika/presentations/Screens/documents_hub.dart';
// ignore: unused_import
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:digi_sanchika/presentations/Screens/profile_screen.dart';
import 'package:digi_sanchika/presentations/Screens/notifications_screen.dart';
import 'package:digi_sanchika/services/document_opener_service.dart';
import 'package:digi_sanchika/presentations/Screens/document_tools_screen.dart';
import 'package:digi_sanchika/services/favorites_service.dart';
import 'package:digi_sanchika/services/download_requests_service.dart';
import 'package:digi_sanchika/services/download_access_service.dart';
import 'package:digi_sanchika/services/profile_service.dart';
import 'package:digi_sanchika/widgets/share_access_sheet.dart';
import 'package:digi_sanchika/models/app_view_mode.dart';
import 'package:digi_sanchika/widgets/view_mode_popup_button.dart';
import 'package:digi_sanchika/widgets/download_feedback.dart';
import 'package:digi_sanchika/widgets/version_history_dialog.dart';
import 'package:digi_sanchika/services/folder_download_service.dart';
import 'package:digi_sanchika/services/document_library_service.dart';
import 'package:digi_sanchika/services/recycle_bin_service.dart';
import 'package:digi_sanchika/presentations/Screens/all_folders_screen.dart';
import 'package:digi_sanchika/utils/responsive_helper.dart';
import 'package:digi_sanchika/utils/design_tokens.dart';
import 'package:digi_sanchika/widgets/dismiss_keyboard.dart';
import 'package:digi_sanchika/widgets/folder_member_avatar_stack.dart';

class HomePage extends StatefulWidget {
  final String? userName;
  final String? userEmail;
  const HomePage({super.key, this.userName, this.userEmail});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _folderNameController = TextEditingController();
  final TextEditingController _newKeywordController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _searchDebounce;
  final Map<String, String> _folderPathCache = {};

  List<Document> allDocuments = [];
  List<Folder> folders = [];
  bool _showRecent = false;
  String _docTypeFilter = 'All'; // 'All', 'PDF', 'Docs', 'Sheets'
  bool _showFolderDropdown = false;
  bool _showDocumentsDropdown = true;
  bool _isLoading = true;
  bool _isDownloading = false;
  bool _isUploading = false;
  bool _showProfileDrawer = false;
  String? _currentFolderId;
  Document? _selectedDocument;
  String? _downloadingFileName;

  Map<String, bool> _expandedStates = {};

  // API search state
  List<Document>? _apiSearchResults;
  bool _isSearching = false;
  String? _searchError;
  String _lastSemanticQuery = '';

  final FavoritesService _favoritesService = FavoritesService();
  final Map<String, String> _favoriteDocumentMap = {};
  final Map<String, String> _favoriteFolderMap = {};

  // Add these variables for layout modes
  AppViewMode _currentViewMode = AppViewMode.list;
  bool _showLayoutOptions = false;
  String? _effectiveUserName;
  String? _effectiveUserEmail;

  @override
  void initState() {
    super.initState();
    final incomingName = widget.userName?.trim() ?? '';
    _effectiveUserName =
        incomingName.isEmpty || incomingName.toLowerCase() == 'user'
        ? null
        : incomingName;

    final incomingEmail = widget.userEmail?.trim() ?? '';
    _effectiveUserEmail = incomingEmail.isEmpty ? null : incomingEmail;
    _tabController = TabController(length: 3, vsync: this);
    _loadInitialData();
    _initializeBackend();
    _loadFavorites();
    _loadStoredUserProfile();

    _tabController.addListener(() {
      _dismissKeyboard();
      if (mounted) {
        // Keep UI (e.g. NavigationRail selection) in sync with tab index changes.
        setState(() {});
      }
      if (_tabController.index == 1) {
      } else if (_tabController.index == 0) {
        _refreshData();
      }
    });
  }

  String _getUserInitial() {
    final name = _displayUserName.trim();
    if (name.isNotEmpty && name.toLowerCase() != 'user') {
      final parts = name
          .split(RegExp(r'\s+'))
          .where((p) => p.trim().isNotEmpty)
          .toList();

      if (parts.length >= 2) {
        final first = parts.first.trim();
        final last = parts.last.trim();
        if (first.isNotEmpty && last.isNotEmpty) {
          return (first[0] + last[0]).toUpperCase();
        }
      }

      if (parts.isNotEmpty && parts.first.isNotEmpty) {
        return parts.first[0].toUpperCase();
      }
    }

    final email = (_displayUserEmail ?? '').trim();
    if (email.isNotEmpty) {
      final local = email.split('@').first;
      final tokens = local
          .split(RegExp(r'[._\-\s]+'))
          .where((t) => t.trim().isNotEmpty)
          .toList();

      if (tokens.length >= 2) {
        return (tokens.first[0] + tokens.last[0]).toUpperCase();
      }
      if (tokens.isNotEmpty && tokens.first.isNotEmpty) {
        return tokens.first[0].toUpperCase();
      }
    }

    return 'U';
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

  String? get _displayUserEmail {
    if (_effectiveUserEmail != null && _effectiveUserEmail!.isNotEmpty) {
      return _effectiveUserEmail;
    }
    return widget.userEmail;
  }

  Future<void> _loadStoredUserProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedName = prefs.getString('user_name');
      final storedEmail = prefs.getString('user_email');
      if (!mounted) return;
      setState(() {
        final currentName = (_effectiveUserName ?? '').trim();
        if ((currentName.isEmpty || currentName.toLowerCase() == 'user') &&
            storedName != null &&
            storedName.trim().isNotEmpty) {
          _effectiveUserName = storedName.trim();
        }

        final currentEmail = (_effectiveUserEmail ?? '').trim();
        if (currentEmail.isEmpty &&
            storedEmail != null &&
            storedEmail.trim().isNotEmpty) {
          _effectiveUserEmail = storedEmail.trim();
        }
      });
    } catch (_) {}
  }

  Future<void> _refreshProfileFromApi() async {
    try {
      final response = await ProfileService.getUserProfile();
      if (!mounted) return;

      if (response['success'] == true && response['data'] != null) {
        final data = response['data'];
        Map<String, dynamic> user = {};
        if (data is Map<String, dynamic>) {
          final inner = data['user'];
          if (inner is Map<String, dynamic>) {
            user = inner;
          } else {
            user = data;
          }
        }

        final name = (user['name'] ?? user['full_name'] ?? user['fullName'])
            ?.toString()
            .trim();
        final email = (user['email'] ?? user['user_email'] ?? user['mail'])
            ?.toString()
            .trim();

        if ((name != null && name.isNotEmpty) ||
            (email != null && email.isNotEmpty)) {
          final prefs = await SharedPreferences.getInstance();
          if (name != null && name.isNotEmpty) {
            await prefs.setString('user_name', name);
          }
          if (email != null && email.isNotEmpty) {
            await prefs.setString('user_email', email);
          }

          if (!mounted) return;
          setState(() {
            if (name != null && name.isNotEmpty) {
              _effectiveUserName = name;
            }
            if (email != null && email.isNotEmpty) {
              _effectiveUserEmail = email;
            }
          });
        }
      }
    } catch (_) {}
  }

  // ADD THIS METHOD
  void _dismissKeyboard() {
    // Dismiss keyboard if search field has focus
    if (_searchFocusNode.hasFocus) {
      _searchFocusNode.unfocus();
    }

    // Also dismiss any other keyboard
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _initializeBackend() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }
    await ApiService.initialize();
    await _refreshProfileFromApi();
    if (ApiService.isConnected) {
      await _loadAllUserDocuments();
      await _loadFavorites();
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

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
      _favoriteFolderMap
        ..clear()
        ..addEntries(
          items
              .where((i) => i.entityType.toLowerCase().contains('folder'))
              .map((i) => MapEntry(i.entityId, i.id)),
        );
      setState(() {});
    } catch (_) {}
  }

  bool _isFavorite(String documentId) {
    return _favoriteDocumentMap.containsKey(documentId);
  }

  bool _isFavoriteFolder(String folderId) {
    return _favoriteFolderMap.containsKey(folderId);
  }

  Future<void> _toggleFavorite(Document document) async {
    final isFav = _isFavorite(document.id);
    final previousId = _favoriteDocumentMap[document.id];

    setState(() {
      if (isFav) {
        _favoriteDocumentMap.remove(document.id);
      } else {
        _favoriteDocumentMap[document.id] = 'pending';
      }
    });

    bool ok = false;
    if (isFav) {
      ok = await _favoritesService.removeFavorite(
        entityId: document.id,
        entityType: 'document',
      );
    } else {
      ok = await _favoritesService.addFavorite(
        entityId: document.id,
        entityType: 'document',
      );
    }

    if (ok) {
      if (!isFav) {
        _showTopMessage('File added to favorites');
      }
    } else {
      if (!mounted) return;
      setState(() {
        if (isFav) {
          if (previousId != null) {
            _favoriteDocumentMap[document.id] = previousId;
          }
        } else {
          _favoriteDocumentMap.remove(document.id);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isFav ? 'Failed to remove favorite' : 'Failed to add favorite',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _toggleFavoriteFolder(Folder folder) async {
    final isFav = _isFavoriteFolder(folder.id);
    final previousId = _favoriteFolderMap[folder.id];

    setState(() {
      if (isFav) {
        _favoriteFolderMap.remove(folder.id);
      } else {
        _favoriteFolderMap[folder.id] = 'pending';
      }
    });

    bool ok = false;
    if (isFav) {
      ok = await _favoritesService.removeFavorite(
        entityId: folder.id,
        entityType: 'folder',
      );
    } else {
      ok = await _favoritesService.addFavorite(
        entityId: folder.id,
        entityType: 'folder',
      );
    }

    if (ok) {
      if (!isFav) {
        _showTopMessage('Folder added to favorites');
      }
    } else {
      if (!mounted) return;
      setState(() {
        if (isFav) {
          if (previousId != null) {
            _favoriteFolderMap[folder.id] = previousId;
          }
        } else {
          _favoriteFolderMap.remove(folder.id);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isFav ? 'Failed to remove favorite' : 'Failed to add favorite',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _refreshData() async {
    await ApiService.checkConnection();
    if (ApiService.isConnected) {
      await _loadAllUserDocuments();
      await _loadFavorites();
    } else {
      await _loadDataFromLocalStorage();
      if (mounted) {
        final messenger = ScaffoldMessenger.maybeOf(this.context);
        messenger?.showSnackBar(
          const SnackBar(
            content: Text('You\'re offline. Showing saved data'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
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

  Future<List<Folder>> _getAllFoldersFlat() async {
    final dio = ApiClient.instance.dio;
    final seen = <String>{};
    final out = <Folder>[];
    final queue = <String?>[null];

    void ingestFolder(Map folderMap, {required String? inferredParentId}) {
      final id = folderMap['id']?.toString() ?? '';
      if (id.isEmpty) return;
      if (!seen.add(id)) return;

      DateTime createdAt;
      try {
        createdAt = DateTime.parse(folderMap['created_at']?.toString() ?? '');
      } catch (_) {
        createdAt = DateTime.now();
      }

      out.add(
        Folder(
          id: id,
          name: folderMap['name']?.toString() ?? 'Unknown',
          documents: <Document>[],
          createdAt: createdAt,
          owner: _displayUserName,
          parentId:
              folderMap['parent_id']?.toString() ??
              folderMap['parentId']?.toString() ??
              inferredParentId,
        ),
      );

      final children = folderMap['children'];
      if (children is List) {
        for (final child in children) {
          if (child is! Map) continue;
          ingestFolder(child, inferredParentId: id);
        }
      }

      queue.add(id);
    }

    var safety = 0;
    while (queue.isNotEmpty && safety < 500) {
      safety++;
      final parentId = queue.removeLast();
      try {
        final response = await dio.get(
          '/folders',
          queryParameters: parentId != null ? {'parentId': parentId} : null,
        );
        if (response.statusCode != 200) continue;

        final body = response.data;
        final raw = body is List
            ? body
            : (body['items'] ?? body['folders'] ?? []);
        if (raw is! List) continue;

        for (final f in raw) {
          if (f is! Map) continue;
          ingestFolder(f, inferredParentId: parentId);
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error fetching folders: $e');
        }
        break;
      }
    }

    return out;
  }

  List<Document> _convertToDocumentList(
    List<dynamic> docList,
    String? folderId,
    String folderPath,
  ) {
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

    String extractFileName(Map<String, dynamic> doc) {
      return safeString(
        doc['name'] ??
            doc['original_filename'] ??
            doc['original_name'] ??
            doc['file_name'] ??
            doc['fileName'] ??
            doc['filename'],
        fallback: 'Unknown',
      );
    }

    return docList.map<Document>((doc) {
      final docMap = (doc is Map<String, dynamic>)
          ? doc
          : (doc as Map).cast<String, dynamic>();

      final fileName = extractFileName(docMap);
      final ownerName = extractOwnerName(docMap['owner']);
      final effectiveOwner =
          (ownerName.isEmpty || ownerName.toLowerCase() == 'unknown')
          ? _displayUserName
          : ownerName;
      final mimeType = docMap['mime_type']?.toString();
      final fileType = mimeType != null && mimeType.isNotEmpty
          ? _extractFileTypeFromMime(mimeType, fileName)
          : _extractFileType(fileName);

      return Document(
        id: safeString(docMap['id']),
        name: fileName,
        type: fileType,
        size:
            '${safeString(docMap['file_size_bytes'] ?? docMap['file_size'], fallback: 'Unknown')} bytes',
        keyword: safeString(docMap['keywords']),
        uploadDate: safeString(
          docMap['created_at'] ?? docMap['updated_at'] ?? docMap['upload_date'],
        ),
        owner: effectiveOwner,
        details: safeString(docMap['remarks']),
        classification: safeString(
          docMap['classification'] ?? docMap['doc_class'],
          fallback: 'internal',
        ),
        allowDownload: docMap['allow_download'] ?? true,
        sharingType:
            (docMap['is_public'] == true ||
                docMap['classification']?.toString().toLowerCase() == 'public')
            ? 'Public'
            : 'Private',
        folder: safeString(folderPath, fallback: 'Unknown'),
        folderId: folderId?.toString(),
        path: fileName,
        fileType: fileType,
      );
    }).toList();
  }

  Future<void> _loadAllUserDocuments() async {
    if (!ApiService.isConnected) {
      if (kDebugMode) {
        print('WARN Skipping backend load - not connected');
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      if (kDebugMode) {
        print('Loading ALL user documents...');
      }

      final allFoldersFlat = await _getAllFoldersFlat();
      final allFolderIds = allFoldersFlat.map((f) => f.id).toList();

      final futures = <Future<Map<String, dynamic>>>[];
      futures.add(_fetchMyDocumentsWithParams(null));
      for (final folderId in allFolderIds) {
        futures.add(_fetchMyDocumentsWithParams(folderId));
      }

      if (kDebugMode) {
        print('Executing ${futures.length} parallel requests...');
      }

      final results = await Future.wait(futures);

      final root = results.isNotEmpty ? results[0] : <String, dynamic>{};
      final rootOk = root['_ok'] != false;
      final hadFailures = results.any((r) => r['_ok'] == false);

      if (!rootOk) {
        final statusCode = root['statusCode'];
        final message = root['message'];
        if (kDebugMode) {
          print('WARN Document load failed');
        }
        await _loadDataFromLocalStorage();
        if (mounted) {
          if (statusCode == 401) {
            try {
              await ApiService.clearTokens();
            } catch (_) {}
            Navigator.of(
              context,
            ).pushNamedAndRemoveUntil('/login', (r) => false);
          } else {
            final msg = message?.toString().trim().isNotEmpty == true
                ? message.toString()
                : 'Couldn\'t refresh documents. Showing saved data.';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(msg), backgroundColor: Colors.orange),
            );
          }
        }
        return;
      }

      final combinedDocuments = <Document>[];
      final allFolders = <Folder>[];

      final rootDocs = root['documents'];
      if (rootDocs is List) {
        combinedDocuments.addAll(
          _convertToDocumentList(rootDocs, null, 'Home'),
        );
      }

      allFolders.addAll(allFoldersFlat);

      for (int i = 1; i < results.length; i++) {
        final r = results[i];
        if (r['_ok'] == false) continue;

        final docs = r['documents'];
        if (docs is! List || docs.isEmpty) continue;

        final folderId = allFolderIds[i - 1];
        final first = docs.first;
        final folderPath = first is Map<String, dynamic>
            ? (first['folder_path']?.toString() ?? 'Unknown')
            : 'Unknown';

        combinedDocuments.addAll(
          _convertToDocumentList(docs, folderId, folderPath),
        );
      }

      if (!mounted) return;
      setState(() {
        allDocuments = combinedDocuments;
        folders = allFolders;
        _folderPathCache.clear();

        if (!folders.any((f) => f.name == 'Home')) {
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
      });

      if (kDebugMode) {
        print(
          'Loaded ${combinedDocuments.length} documents (sources: ${results.length}, failures: ${hadFailures ? 'yes' : 'no'})',
        );
      }

      if (!hadFailures) {
        try {
          await LocalStorageService.saveDocuments(combinedDocuments);
          if (kDebugMode) {
            print(
              'Saved ${combinedDocuments.length} documents to local storage',
            );
          }
        } catch (e) {
          if (kDebugMode) {
            print('WARN Error saving to local storage: $e');
          }
        }
      } else {
        if (kDebugMode) {
          print('WARN Skipping local cache save due to failed requests');
        }
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('ERROR Exception in _loadAllUserDocuments: $e');
        print('Stack trace: $stackTrace');
      }
      await _loadDataFromLocalStorage();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<Map<String, dynamic>> _fetchMyDocumentsWithParams(
    String? folderId,
  ) async {
    try {
      final response = await ApiClient.instance.dio.get(
        '/documents',
        queryParameters: folderId != null ? {'folderId': folderId} : null,
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          final map = Map<String, dynamic>.from(data);
          map['_ok'] = true;
          return map;
        }
        return {'_ok': true, 'documents': data, 'folders': []};
      }

      final data = response.data;
      final message = data is Map<String, dynamic>
          ? (data['message'] ?? data['error'] ?? data['detail'])?.toString()
          : null;

      return {
        '_ok': false,
        'statusCode': response.statusCode,
        'message': message ?? 'Failed to fetch documents',
        'documents': null,
        'folders': null,
      };
    } catch (e) {
      if (kDebugMode) {
        print('WARN Document load failed');
      }
      return {
        '_ok': false,
        'statusCode': null,
        'message': e.toString(),
        'documents': null,
        'folders': null,
      };
    }
  }

  void _loadInitialData() {
    setState(() {
      folders.add(
        Folder(
          name: 'Home',
          id: 'home',
          documents: [],
          createdAt: DateTime.now(),
          owner: _displayUserName,
        ),
      );
    });
  }

  void _addNewDocument(Document document) async {
    if (ApiService.isConnected) {
      if (!_isLoading) {
        await _refreshData();
      }
      return;
    }

    setState(() {
      allDocuments.add(document);
      _organizeDocumentsIntoFolders();
    });

    final isPublic = document.sharingType == 'Public';
    await LocalStorageService.addDocument(document, isPublic: isPublic);
  }

  void _addNewFolder(String folderName) {
    if (folderName.isEmpty) return;

    setState(() {
      folders.add(
        Folder(
          name: folderName,
          id: 'folder_${DateTime.now().millisecondsSinceEpoch}',
          documents: [],
          createdAt: DateTime.now(),
          owner: _displayUserName,
        ),
      );
    });
  }

  Future<void> _createFolderInBackend(String folderName) async {
    if (!ApiService.isConnected) {
      _addNewFolder(folderName);
      return;
    }

    try {
      final result = await MyDocumentsService.createFolder(
        folderName: folderName,
        parentFolderId: _currentFolderId,
      );

      if (result['success'] == true) {
        _addNewFolder(folderName);
        _refreshData();
      } else {
        throw Exception(result['error']);
      }
    } catch (e) {
      if (kDebugMode) {
        print('WARN Document load failed');
      }
      _addNewFolder(folderName);
    }
  }

  Future<Map<String, String>> _createAuthHeaders() async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    try {
      final token = await TokenStorage.getAccessToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer ' + token;
      }
    } catch (e) {
      if (kDebugMode) {
        print('WARN Document load failed');
      }
    }

    return headers;
  }

  Future<void> _deleteFolder(int index) async {
    if (index >= 0 && index < folders.length) {
      final folder = folders[index];
      final folderName = folder.name;

      if (ApiService.isConnected && folder.id != 'home') {
        try {
          final result = await MyDocumentsService.deleteFolder(folder.id);
          if (result['success'] != true) {
            throw Exception(result['error']);
          }
        } catch (e) {
          if (kDebugMode) {
            print('WARN Document load failed');
          }
        }
      }

      allDocuments.removeWhere((doc) => doc.folder == folderName);
      setState(() {
        folders.removeAt(index);
      });

      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Folder "$folderName" deleted successfully'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _deleteDocument(int index) async {
    if (index >= 0 && index < allDocuments.length) {
      Document docToDelete = allDocuments[index];

      try {
        if (ApiService.isConnected) {
          final result = await RecycleBinService().moveToRecycleBin(
            entityType: 'document',
            entityId: docToDelete.id,
          );
          if (result['success'] != true) {
            final fallback = await RecycleBinService()
                .moveToRecycleBinViaDocumentDelete(documentId: docToDelete.id);
            if (fallback['success'] != true) {
              throw Exception(
                (result['message'] ?? fallback['message'] ?? 'Move failed')
                    .toString(),
              );
            }
          }
        }

        setState(() {
          allDocuments.removeAt(index);
          _organizeDocumentsIntoFolders();
        });

        await LocalStorageService.deleteDocument(
          docToDelete.name,
          isPublic: docToDelete.sharingType == 'Public',
        );

        // Auto-refresh from backend/local to keep UI in sync (e.g., folder counts).
        if (mounted) {
          try {
            await _refreshData();
          } catch (_) {}
        }

        // ignore: use_build_context_synchronously
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('Moved "${docToDelete.name}" to Recycle Bin'),
            backgroundColor: Colors.orange,
          ),
        );
      } catch (e) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('Failed to delete document: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _downloadDocument(Document document) async {
    if (!ApiService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot download while offline'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadingFileName = document.name;
    });

    try {
      final result = await DownloadAccessService.downloadBytesWithAccess(
        documentId: document.id,
      );

      if (result['success'] == true) {
        final directory = await getDownloadDirectory();
        final filePath = '${directory.path}/${document.name}';
        final file = File(filePath);
        await file.writeAsBytes((result['bytes'] as List<int>));

        if (!mounted) return;
        await DownloadFeedback.showDownloadedDialog(
          context,
          filename: document.name,
          filePath: filePath,
        );
      } else if (result['requiresApproval'] == true) {
        final reqService = DownloadRequestsService();
        final reqResult = await reqService.createRequest(
          documentId: document.id,
          reason: 'Need offline copy',
        );
        if (reqResult['success'] == true) {
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Download request sent for approval'),
              backgroundColor: Colors.orange,
            ),
          );
        } else {
          throw Exception(reqResult['message'] ?? 'Request failed');
        }
      } else {
        throw Exception(result['error'] ?? 'Download failed');
      }
    } catch (e) {
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isDownloading = false;
        _downloadingFileName = null;
      });
    }
  }

  void _openDocumentTools(Document document) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DocumentToolsScreen(document: document),
      ),
    );
  }

  Future<Directory> getDownloadDirectory() async {
    if (Platform.isAndroid) {
      return await getApplicationDocumentsDirectory();
    } else if (Platform.isIOS) {
      return await getApplicationDocumentsDirectory();
    }
    return Directory.current;
  }

  String _getFileProviderUri(String filePath) {
    if (Platform.isAndroid) {
      try {
        final file = File(filePath);
        if (file.existsSync()) {
          final fileName = file.path.split('/').last;
          return 'content://com.example.digi_sanchika.fileprovider/files/$fileName';
        }
      } catch (e) {
        if (kDebugMode) {
          print('WARN Document load failed');
        }
      }
    }
    return filePath;
  }

  Future<void> _showDocumentVersions(Document document) async {
    await VersionHistoryDialog.show(
      context,
      document: document,
      onRestored: _refreshData,
    );
  }

  Future<void> _openSelectedVersion(
    BuildContext context,
    Document document,
    Map<String, dynamic> version,
  ) async {
    setState(() {
      _isDownloading = true;
    });

    try {
      final documentOpener = DocumentOpenerService();
      final versionNumber =
          (version['version_number'] ??
                  version['version'] ??
                  version['versionNumber'] ??
                  version['number'])
              ?.toString()
              .trim();
      if (versionNumber == null || versionNumber.isEmpty) {
        throw Exception('Invalid version selected');
      }

      await documentOpener.openDocumentVersion(
        context: context,
        documentId: document.id,
        versionNumber: versionNumber,
        originalFileName: document.name,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to open version: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isDownloading = false;
      });
    }
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

  Future<void> _showFolderShareDialog(Folder folder) async {
    if (!ApiService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot share while offline'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    await ShareAccessSheet.showForFolder(
      context: context,
      folderId: folder.id,
      folderName: folder.name,
    );
  }

  Future<void> _downloadFolderZip(Folder folder) async {
    if (!ApiService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot download while offline'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final svc = FolderDownloadService();
      final result = await svc.downloadFolderAsZipWithAccess(
        folderId: folder.id,
        reason: 'Need offline copy',
        folderNameHint: folder.name,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        await DownloadFeedback.showDownloadedDialog(
          context,
          filename: (result['filename'] ?? '${folder.name}.zip').toString(),
          filePath: (result['filePath'] ?? '').toString(),
        );
        return;
      }

      if (result['requiresApproval'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (result['requestCreated'] == true)
                  ? 'Download request sent for approval'
                  : (result['message']?.toString() ??
                        'Download requires approval'),
            ),
            backgroundColor: (result['requestCreated'] == true)
                ? Colors.orange
                : Colors.red,
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(() {
            final err = result['error']?.toString() ?? 'Download failed';
            final d = result['downloaded'];
            final f = result['failed'];
            if (d is int || f is int) {
              return '$err (downloaded: ${d ?? 0}, failed: ${f ?? 0})';
            }
            return err;
          }()),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _downloadFolderFiles(Folder folder) async {
    if (!ApiService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot download while offline'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final svc = FolderDownloadService();
      final result = await svc.downloadFolderFilesWithAccess(
        folderId: folder.id,
        reason: 'Need offline copy',
        folderNameHint: folder.name,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        await DownloadFeedback.showDownloadedDialog(
          context,
          filename: (result['rootName'] ?? folder.name).toString(),
          filePath: (result['folderPath'] ?? '').toString(),
        );
        return;
      }

      if (result['requiresApproval'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (result['requestCreated'] == true)
                  ? 'Download request sent for approval'
                  : (result['message']?.toString() ??
                        'Download requires approval'),
            ),
            backgroundColor: (result['requestCreated'] == true)
                ? Colors.orange
                : Colors.red,
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(() {
            final err = result['error']?.toString() ?? 'Download failed';
            final d = result['downloaded'];
            final f = result['failed'];
            if (d is int || f is int) {
              return '$err (downloaded: ${d ?? 0}, failed: ${f ?? 0})';
            }
            return err;
          }()),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showDocumentDetails(Document document) async {
    if (!ApiService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot load details while offline'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final result = await MyDocumentsService.getDocumentDetails(document.id);

      if (result['success'] == true) {
        final details = result['details'];
        final name =
            details['name'] ??
            details['original_filename'] ??
            details['file_name'] ??
            'Document';
        final mimeType = details['mime_type']?.toString();
        final fileType = mimeType != null && mimeType.isNotEmpty
            ? _extractFileTypeFromMime(mimeType, name.toString())
            : _extractFileType(name.toString());
        setState(() {
          _selectedDocument = Document(
            id: details['id'].toString(),
            name: name.toString(),
            type: fileType,
            size:
                '${details['file_size_bytes'] ?? details['file_size'] ?? 'Unknown'} bytes',
            keyword: details['keywords'] ?? '',
            uploadDate: _formatDate(
              details['created_at'] ?? details['updated_at'],
            ),
            owner: details['owner']?['name'] ?? 'Unknown',
            details: details['remarks'] ?? '',
            classification:
                details['classification'] ?? details['doc_class'] ?? 'internal',
            allowDownload: details['allow_download'] ?? true,
            sharingType:
                (details['is_public'] == true ||
                    details['classification']?.toString().toLowerCase() ==
                        'public')
                ? 'Public'
                : 'Private',
            folder: details['folder_path'] ?? 'Home',
            folderId: details['folder_id']?.toString(),
            path: name.toString(),
            fileType: fileType,
          );
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('WARN Document load failed');
      }
    }
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

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tabController.dispose();
    _searchFocusNode.dispose();
    _searchController.dispose();
    _folderNameController.dispose();
    _newKeywordController.dispose();
    super.dispose();
  }

  void _showCreateFolderDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.9,
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.create_new_folder,
                        color: Colors.indigo,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Create New Folder',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _folderNameController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Folder Name',
                    hintText: 'Enter folder name',
                    prefixIcon: const Icon(Icons.folder, color: Colors.indigo),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.indigo,
                        width: 2,
                      ),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          _folderNameController.clear();
                          Navigator.of(context).pop();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey.shade700,
                          side: BorderSide(color: Colors.grey.shade300),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          String folderName = _folderNameController.text.trim();
                          if (folderName.isNotEmpty) {
                            await _createFolderInBackend(folderName);
                            _folderNameController.clear();
                            Navigator.of(context).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Folder "$folderName" created successfully',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please enter a folder name'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text(
                          'Create',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color.fromARGB(
                            255,
                            28,
                            36,
                            121,
                          ),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 2,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDeleteFolderConfirmation(BuildContext context, int index) {
    if (index >= 0 && index < folders.length) {
      final folder = folders[index];
      final folderName = folder.name;
      final documentCount = folder.documents.length;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.delete, color: Colors.red, size: 28),
              const SizedBox(width: 12),
              const Text(
                'Delete Folder',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Are you sure you want to delete folder "$folderName"?'),
              if (documentCount > 0) ...[
                const SizedBox(height: 8),
                Text(
                  'This folder contains $documentCount document${documentCount == 1 ? '' : 's'}. All documents in this folder will also be deleted.',
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
            ],
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await _deleteFolder(index);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }
  }

  void _showDeleteConfirmation(BuildContext context, int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Document'),
        content: const Text('Are you sure you want to delete this document?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _deleteDocument(index);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showDeleteOptions(BuildContext context, int index, Document document) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete'),
        content: Text('Choose what to do with "${document.name}".'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteDocument(index); // Move to recycle bin (soft delete)
            },
            child: const Text('Move to Recycle Bin'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showPermanentDeleteConfirmation(document);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              'Delete Permanently',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showPermanentDeleteConfirmation(Document document) {
    if (!mounted) return;
    // Use the State's active context; do not use a dialog's ctx or a stale caller context.
    final dialogContext = this.context;
    showDialog(
      context: dialogContext,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Permanently'),
        content: Text(
          'This will permanently delete "${document.name}" and cannot be undone. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final direct = await MyDocumentsService.deleteDocument(
                  document.id,
                );
                final deleted =
                    (direct['success'] == true) &&
                    await RecycleBinService().deletePermanently(
                      entityType: 'document',
                      entityId: document.id,
                    );
                if (!mounted) return;
                if (deleted) {
                  setState(() {
                    if (document.id.trim().isNotEmpty) {
                      allDocuments.removeWhere((d) => d.id == document.id);
                    } else {
                      allDocuments.removeWhere(
                        (d) =>
                            d.name == document.name &&
                            d.path == document.path &&
                            d.uploadDate == document.uploadDate,
                      );
                    }
                    _organizeDocumentsIntoFolders();
                  });
                  // Backend may delete asynchronously; refresh to ensure it disappears.
                  try {
                    await _refreshData();
                  } catch (_) {}
                  if (!mounted) return;
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(
                      content: Text('"${document.name}" permanently deleted'),
                      backgroundColor: Colors.red,
                    ),
                  );
                } else {
                  if (!mounted) return;
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(
                      content: Text(
                        (direct['error'] ??
                                direct['message'] ??
                                'Permanent delete failed')
                            .toString(),
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              'Delete Permanently',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.logout, color: Colors.black, size: 28),
            const SizedBox(width: 12),
            const Text(
              'Logout',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ],
        ),
        content: const Text('Are you sure you want to logout?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.black)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushReplacementNamed(context, '/login');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromARGB(255, 14, 25, 129),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _openNotifications() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const NotificationsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;

    final layout = AppLayout.of(context);
    final tabViews = TabBarView(
      controller: _tabController,
      children: [
        _buildMyDocumentsTab(),
        DocumentsHub(),
        UploadDocumentTab(
          onDocumentUploaded: _addNewDocument,
          folders: folders,
          userName: _displayUserName,
        ),
      ],
    );

    PreferredSizeWidget? tabBar;
    if (!layout.useNavigationRail) {
      tabBar = TabBar(
        controller: _tabController,
        indicatorColor: Colors.white,
        indicatorWeight: 3,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: r.sp(12)),
        unselectedLabelStyle: TextStyle(fontSize: r.sp(12)),
        tabs: const [
          Tab(text: 'My Documents'),
          Tab(text: 'Document Hub'),
          Tab(text: 'Upload Docs'),
        ],
      );
    }

    final content = layout.useNavigationRail
        ? Row(
            children: [
              NavigationRail(
                selectedIndex: _tabController.index,
                onDestinationSelected: (index) {
                  setState(() {
                    _tabController.animateTo(index);
                  });
                },
                minWidth: layout.navigationRailWidth,
                labelType: NavigationRailLabelType.all,
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.folder_open_outlined),
                    selectedIcon: Icon(Icons.folder_open),
                    label: Text('Docs'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.hub_outlined),
                    selectedIcon: Icon(Icons.hub),
                    label: Text('Hub'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.upload_file_outlined),
                    selectedIcon: Icon(Icons.upload_file),
                    label: Text('Upload'),
                  ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: tabViews),
            ],
          )
        : tabViews;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: Text(
          'Digi Sanchika',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: r.sp(20),
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color.fromARGB(255, 43, 65, 189),
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _openNotifications,
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_outlined, color: Colors.white),
          ),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfileScreen()),
              );
            },
            child: Container(
              margin: EdgeInsets.only(right: r.p(14)),
              child: CircleAvatar(
                backgroundColor: Colors.white,
                radius: r.p(17),
                child: Text(
                  _getUserInitial(),
                  style: TextStyle(
                    color: const Color.fromARGB(255, 43, 65, 189),
                    fontWeight: FontWeight.bold,
                    fontSize: r.sp(15),
                  ),
                ),
              ),
            ),
          ),
        ],
        bottom: tabBar,
        
      ),

      body: Stack(
        children: [
          DismissKeyboard(child: content),
          if (_showProfileDrawer)
            GestureDetector(
              onTap: () {
                setState(() {
                  _showProfileDrawer = false;
                });
              },
              child: Container(color: Colors.black.withAlpha(30)),
            ),
          if (_showProfileDrawer) _buildProfileSidebar(),
        ],
      ),
    );
  }

  Widget _buildFoldersSection(
    List<Folder> displayFolders, {
    required int totalFolderCount,
  }) {
    if (displayFolders.isEmpty) return const SizedBox.shrink();
    final r = context.r;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Folders',
                style: TextStyle(
                  fontSize: r.sp(16),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (totalFolderCount > 4)
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          AllFoldersScreen(userName: _displayUserName),
                    ),
                  );
                },
                child: const Text('View all'),
              ),
          ],
        ),
       SizedBox(
  height: 280.h,
  child: GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: displayFolders.length,
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      crossAxisSpacing: 12.w,
      mainAxisSpacing: 12.h,
      childAspectRatio: 1.08,
    ),
    itemBuilder: (context, index) {
      final folder = displayFolders[index];

      // ── Per-index folder icon colour pairs ──────────────────────────
      const folderColorPairs = [
        [Color(0xFFEDE7F6), Color.fromARGB(255, 190, 169, 248)], // purple
        [Color(0xFFE0F7FA), Color.fromARGB(255, 108, 179, 172)], // teal
        [Color(0xFFFFF3E0), Color.fromARGB(255, 240, 186, 121)], // orange
        [Color(0xFFE8F5E9), Color.fromARGB(255, 136, 221, 140)], // green
        [Color(0xFFE3F2FD), Color.fromARGB(255, 132, 171, 204)], // blue
        [Color(0xFFFCE4EC), Color.fromARGB(255, 226, 140, 169)], // pink
      ];
      final iconBg    = folderColorPairs[index % folderColorPairs.length][0];
      final iconColor = folderColorPairs[index % folderColorPairs.length][1];

      // ── Document count & size ────────────────────────────────────────
      final folderDocs = allDocuments
          .where((d) => d.folderId == folder.id)
          .toList();
      final fileCount = folderDocs.length;

      double totalBytes = 0;
      for (final d in folderDocs) {
        final raw = d.size.replaceAll(RegExp(r'[^0-9.]'), '').trim();
        totalBytes += double.tryParse(raw) ?? 0;
      }
      final sizeMB = totalBytes / (1024 * 1024);
      final sizeLabel = sizeMB >= 1
          ? '${sizeMB.toStringAsFixed(0)} MB'
          : '${(totalBytes / 1024).toStringAsFixed(0)} KB';

      // ── Time ago ─────────────────────────────────────────────────────
      String timeAgo(DateTime dt) {
        final diff = DateTime.now().difference(dt);
        if (diff.inDays >= 7)  return '${(diff.inDays / 7).floor()}w ago';
        if (diff.inDays >= 1)  return '${diff.inDays}d ago';
        if (diff.inHours >= 1) return '${diff.inHours}h ago';
        return 'just now';
      }

      return Material(
        elevation: 0.5,
        color: Colors.white,
        borderRadius: BorderRadius.circular(r.p(12)),
        child: InkWell(
          borderRadius: BorderRadius.circular(r.p(12)),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => FolderScreen(
                  folderId: folder.id,
                  folderName: folder.name,
                  userName: _displayUserName,
                ),
              ),
            );
          },
          onLongPress: () => _showDeleteFolderConfirmation(context, index),
          child: Container(
            padding: EdgeInsets.symmetric(vertical: r.p(6),horizontal: r.p(12)),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(r.p(12)),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: coloured folder icon + ⋮ menu
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: EdgeInsets.all(r.p(8)),
                      decoration: BoxDecoration(
                        color: iconBg,
                        borderRadius: BorderRadius.circular(r.p(10)),
                      ),
                      child: Icon(
                        Icons.folder_rounded,
                        color: iconColor,
                        size: r.sp(24),
                      ),
                    ),
                    PopupMenuButton<String>(
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'download',     child: Text('Download')),
                        PopupMenuItem(value: 'download_zip', child: Text('Download as ZIP')),
                        PopupMenuItem(value: 'share',        child: Text('Share Folder')),
                        PopupMenuItem(value: 'delete',       child: Text('Delete Folder')),
                      ],
                      onSelected: (value) {
                        if (value == 'download') {
                          _downloadFolderFiles(folder);
                        } else if (value == 'download_zip') {
                          _downloadFolderZip(folder);
                        } else if (value == 'share') {
                          _showFolderShareDialog(folder);
                        } else if (value == 'delete') {
                          _showDeleteFolderConfirmation(context, index);
                        }
                      },
                      icon: Icon(Icons.more_vert,
                          size: r.sp(18), color: Colors.grey.shade500),
                    ),
                  ],
                ),

                SizedBox(height: r.p(8)),

                // Folder name
                Text(
                  folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: r.sp(14),
                    color: Colors.black87,
                  ),
                ),

                SizedBox(height: r.p(3)),

                // "N files · X MB"
                Text(
                  '$fileCount ${fileCount == 1 ? 'file' : 'files'} · $sizeLabel',
                  style: TextStyle(
                    fontSize: r.sp(12),
                    color: Colors.grey.shade500,
                  ),
                ),
Divider(height: r.p(12)),

                // Bottom row: owner avatars + time ago
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    FolderMemberAvatarStack(
                      folderId: folder.id,
                      fallbackInitial: _getUserInitial().substring(0, 1),
                    ),
                    

                    const Spacer(),

                    Row(
                      children: [
                        Icon(Icons.access_time_rounded,
                            size: r.sp(11), color: Colors.grey.shade400),
                        SizedBox(width: r.p(2)),
                        Text(
                          timeAgo(folder.createdAt),
                          style: TextStyle(
                            fontSize: r.sp(11),
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  ),
)
        ]);

   
  }

  Widget _buildFolderSearchSection(List<Folder> matches) {
    final r = context.r;
    if (matches.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(top: r.p(8)),
        child: Text(
          'No folder matches',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    return Column(
      children: [
        for (final f in matches)
          ListTile(
            dense: true,
            leading: Icon(Icons.folder, color: Colors.amber.shade700),
            title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              'Path: ${_folderPathForId(f.id)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => FolderScreen(
                    folderId: f.id,
                    folderName: f.name,
                    userName: _displayUserName,
                  ),
                ),
              );
            },
          ),
      ],
    );
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
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: r.sp(14)),
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
            'No results for \"$query\"',
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

  Widget _buildTypeFilterChips() {
    final r = context.r;

    bool isHomeDoc(Document d) {
      final folderId = d.folderId?.trim();
      if (folderId != null && folderId.isNotEmpty) return false;
      final folderName = d.folder.trim().toLowerCase();
      return folderName.isEmpty || folderName == 'home';
    }

    final allHomeDocs = allDocuments.where(isHomeDoc).toList();
    final filters = [
      {'label': 'All', 'count': allHomeDocs.length},
      {
        'label': 'PDF',
        'count': allHomeDocs
            .where((d) => d.type.toLowerCase().replaceAll('.', '') == 'pdf')
            .length,
      },
      {
        'label': 'Docs',
        'count': allHomeDocs.where((d) {
          final ext = d.type.toLowerCase().replaceAll('.', '');
          return ext == 'doc' || ext == 'docx' || ext == 'txt' || ext == 'odt';
        }).length,
      },
      {
        'label': 'Sheets',
        'count': allHomeDocs.where((d) {
          final ext = d.type.toLowerCase().replaceAll('.', '');
          return ext == 'xls' || ext == 'xlsx' || ext == 'csv' || ext == 'ods';
        }).length,
      },
    ];

    return Container(
      // color: Colors.white,
      padding: EdgeInsets.symmetric(
        horizontal: r.horizontalPadding,
        vertical: r.p(5),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.map((f) {
            final label = f['label'] as String;
            final count = f['count'] as int;
            final isSelected = _docTypeFilter == label;
            return Padding(
              padding: EdgeInsets.only(right: r.p(8)),
              child: GestureDetector(
                onTap: () => setState(() => _docTypeFilter = label),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: EdgeInsets.symmetric(
                    horizontal: r.p(14),
                    vertical: r.p(7),
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF2B41BD)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(r.p(8)),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF2B41BD)
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: r.sp(13),
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isSelected
                              ? Colors.white
                              : Colors.black87,
                        ),
                      ),
                      SizedBox(width: r.p(5)),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: r.p(6),
                          vertical: r.p(2),
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white.withAlpha(50)
                              : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(r.p(10)),
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            fontSize: r.sp(11),
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildDocumentsSection(List<Document> documents) {
    final r = context.r;
    Widget content;
    if (_isLoading && documents.isEmpty) {
      content = _buildDocumentsLoadingState();
    } else if (documents.isEmpty) {
      content = _buildDocumentsEmptyState();
    } else {
      switch (_currentViewMode) {
        case AppViewMode.list:
        case AppViewMode.detailed:
          content = Column(
            children: [
              for (int i = 0; i < documents.length; i++)
                _buildDocumentCard(documents[i], i),
            ],
          );
          break;
        case AppViewMode.compact:
          content = Column(
            children: [
              for (int i = 0; i < documents.length; i++)
                ListTile(
                  dense: true,
                  visualDensity: const VisualDensity(vertical: -2),
                  leading: Icon(
                    _getDocumentIcon(documents[i].type),
                    size: r.sp(22),
                    color: _getDocumentColor(documents[i].type),
                  ),
                  title: Text(
                    documents[i].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: r.sp(14)),
                  ),
                  subtitle: Text(
                    documents[i].type.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: r.sp(11)),
                  ),
                  trailing: IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.more_vert, size: r.sp(20)),
                    onPressed: () => _showDocumentActions(documents[i], i),
                  ),
                  onTap: () => DocumentOpenerService().openPreviewDialog(
                    context: context,
                    document: documents[i],
                  ),
                ),
            ],
          );
          break;
        case AppViewMode.grid2x2:
        case AppViewMode.grid3x3:
          final crossAxisCount = _currentViewMode == AppViewMode.grid3x3
              ? 3
              : 2;
          final spacing = r.p(_currentViewMode == AppViewMode.grid3x3 ? 8 : 12);
          final aspect = _currentViewMode == AppViewMode.grid3x3 ? 0.88 : 0.95;
          content = GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: documents.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
              childAspectRatio: aspect,
            ),
            itemBuilder: (context, index) {
              final doc = documents[index];
              final iconData = _getDocumentIcon(doc.type);
              final color = _getDocumentColor(doc.type);
              return Card(
                
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(r.p(12)),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(r.p(12)),
                  onTap: () => DocumentOpenerService().openPreviewDialog(
                    context: context,
                    document: doc,
                  ),
                  onLongPress: () => _showDocumentActions(doc, index),
                  child: Padding(
                    padding: EdgeInsets.all(r.p(10)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              width: r.p(38),
                              height: r.p(38),
                              decoration: BoxDecoration(
                                color: color.withAlpha(18),
                                borderRadius: BorderRadius.circular(r.p(10)),
                              ),
                              child: Icon(
                                iconData,
                                size: r.sp(22),
                                color: color,
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              size: r.sp(18),
                              color: Colors.black38,
                            ),
                          ],
                        ),
                        SizedBox(height: r.p(8)),
                        Text(
                          doc.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: r.sp(13),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          doc.type.toUpperCase(),
                          style: TextStyle(
                            fontSize: r.sp(11),
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
          break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Documents',
          style: TextStyle(fontSize: r.sp(16), fontWeight: FontWeight.bold),
        ),
        SizedBox(height: r.p(8)),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) {
            final slide = Tween<Offset>(
              begin: const Offset(0, 0.02),
              end: Offset.zero,
            ).animate(animation);
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(position: slide, child: child),
            );
          },
          child: KeyedSubtree(
            key: ValueKey('${_isLoading}_${documents.isEmpty}_$_docTypeFilter'),
            child: content,
          ),
        ),
      ],
    );
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

  Widget _buildMyDocumentsTab() {
    final r = context.r;
    final layout = AppLayout.of(context);
    final isExpanded =
        ResponsiveHelper.of(context).widthClass == WidthClass.expanded;
    final activeQuery = _searchController.text.trim();
    final normalDocs = activeQuery.isEmpty
        ? <Document>[]
        : _normalSearchDocuments(activeQuery);
    final semanticDocs =
        (activeQuery.isNotEmpty && _lastSemanticQuery == activeQuery)
        ? (_apiSearchResults ?? const <Document>[])
        : const <Document>[];

    final semanticIds = semanticDocs.map((d) => d.id).toSet();
    final normalOnlyDocs = normalDocs
        .where((d) => !semanticIds.contains(d.id))
        .toList();

    final filteredDocuments = activeQuery.isEmpty
        ? _getFilteredDocuments()
        : const <Document>[];
    final allDisplayFolders = folders.where((f) => f.name != 'Home').toList();
    allDisplayFolders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final displayFolders = allDisplayFolders.length > 4
        ? allDisplayFolders.take(4).toList()
        : allDisplayFolders;
    final totalFolderCount = allDisplayFolders.length;
    final folderMatches = activeQuery.isEmpty
        ? const <Folder>[]
        : _normalSearchFolders(activeQuery);

    if (isExpanded) {
      Widget searchBar() => Container(
        padding: EdgeInsets.symmetric(
          horizontal: layout.gutter,
          vertical: r.p(10),
        ),
        color: Colors.grey.shade100,
        child: Row(
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
                style: TextStyle(fontSize: r.sp(14)),
                onTapOutside: (_) => _dismissKeyboard(),
                decoration: InputDecoration(
                  hintText: 'Search documents…',
                  hintStyle: TextStyle(fontSize: r.sp(14)),
                  prefixIcon: _isSearching
                      ? Padding(
                          padding: EdgeInsets.all(r.p(12)),
                          child: SizedBox(
                            width: r.sp(18),
                            height: r.sp(18),
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          ),
                        )
                      : Icon(
                          Icons.search,
                          color: Colors.indigo,
                          size: r.sp(22),
                        ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, size: r.sp(20)),
                          onPressed: _clearSearch,
                        )
                      : null,
                  contentPadding: EdgeInsets.symmetric(vertical: r.p(12)),
                  isDense: true,
                ),
              ),
            ),
            SizedBox(width: r.p(10)),
            ViewModePopupButton(
              value: _currentViewMode,
              onSelected: (mode) => setState(() => _currentViewMode = mode),
            ),
          ],
        ),
      );

      final banners = <Widget>[
        if (!ApiService.isConnected) _buildOfflineBanner(),
        if (_isDownloading) _buildDownloadingBanner(),
        if (_isUploading) _buildUploadingBanner(),
      ];

      return Column(
        children: [
          ...banners,
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: 360,
                  child: Column(
                    children: [
                      searchBar(),
                      _buildTypeFilterChips(),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _refreshData,
                          child: ListView(
                            padding: EdgeInsets.all(r.p(14)),
                            children: [
                              if (activeQuery.isEmpty)
                                _buildFoldersSection(
                                  displayFolders,
                                  totalFolderCount: totalFolderCount,
                                )
                              else ...[
                                Text(
                                  'Folder matches',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: r.sp(16),
                                    color: Colors.indigo,
                                  ),
                                ),
                                SizedBox(height: r.p(10)),
                                _buildFolderSearchSection(folderMatches),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refreshData,
                    child: ListView(
                      padding: EdgeInsets.all(r.p(14)),
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
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        if (!ApiService.isConnected) _buildOfflineBanner(),
        if (_isDownloading) _buildDownloadingBanner(),
        if (_isUploading) _buildUploadingBanner(),

        // Search bar
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: r.horizontalPadding,
            vertical: r.p(10),
          ),
          color: Colors.grey.shade100,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  onSubmitted: (value) {
                    final q = value.trim();
                    if (q.isNotEmpty) {
                      _dismissKeyboard();
                      _performSearch(q);
                    }
                  },
                  textInputAction: TextInputAction.search,
                  style: TextStyle(fontSize: r.sp(14)),
                  onTapOutside: (_) => _dismissKeyboard(),
                  decoration: InputDecoration(
                    hintText: 'Search documents…',
                    hintStyle: TextStyle(fontSize: r.sp(14)),
                    prefixIcon: _isSearching
                        ? Padding(
                            padding: EdgeInsets.all(r.p(8)),
                            child: SizedBox(
                              width: r.sp(18),
                              height: r.sp(18),
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            ),
                          )
                        : Icon(
                            Icons.search,
                            color: Colors.indigo,
                            size: r.sp(22),
                          ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, size: r.sp(20)),
                            onPressed: _clearSearch,
                          )
                        : null,
                    contentPadding: EdgeInsets.symmetric(vertical: r.p(12)),
                    isDense: true,
                  ),
                ),
              ),
              SizedBox(width: r.p(10)),
              ViewModePopupButton(
                value: _currentViewMode,
                onSelected: (mode) => setState(() => _currentViewMode = mode),
              ),
            ],
          ),
        ),

        // Filter chips: All / PDF / Docs / Sheets
        _buildTypeFilterChips(),

        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshData,
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: r.p(14)),
              children: [
                if (activeQuery.isEmpty) ...[
                  _buildFoldersSection(
                    displayFolders,
                    totalFolderCount: totalFolderCount,
                  ),
                  _buildDocumentsSection(filteredDocuments),
                ] else ...[
                  Text(
                    'Folder matches',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: r.sp(16),
                      color: Colors.indigo,
                    ),
                  ),
                  SizedBox(height: r.p(10)),
                  _buildFolderSearchSection(folderMatches),
                  SizedBox(height: r.p(14)),
                  _buildSearchDocumentsSection(
                    query: activeQuery,
                    semanticDocs: semanticDocs,
                    normalOnlyDocs: normalOnlyDocs,
                  ),
                ],
              ],
            ),
          ),
        ),
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

  List<Document> _normalSearchDocuments(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];

    final out = <Document>[];
    for (final doc in allDocuments) {
      final ext = path.extension(doc.name).replaceAll('.', '').toLowerCase();
      final folderPath = _documentDirectoryPath(doc).toLowerCase();
      final haystack = <String>[
        doc.name,
        ext,
        doc.type,
        doc.fileType,
        doc.keyword,
        doc.owner,
        doc.classification,
        doc.folder,
        folderPath,
        doc.details,
      ].join(' ').toLowerCase();

      if (haystack.contains(q)) out.add(doc);
    }
    return out;
  }

  List<Folder> _normalSearchFolders(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];

    final out = <Folder>[];
    for (final f in folders) {
      final p = _folderPathForId(f.id).toLowerCase();
      final haystack = '${f.name} $p'.toLowerCase();
      if (haystack.contains(q)) out.add(f);
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
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

  void _showDocumentActions(Document document, int index) {
    final isFav = _isFavorite(document.id);
    final documentOpener = DocumentOpenerService();

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
                  documentOpener.openPreviewDialog(
                    context: context,
                    document: document,
                  );
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
                  _showDocumentVersions(document);
                },
              ),
              ListTile(
                leading: Icon(
                  isFav ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                ),
                title: Text(
                  isFav ? 'Remove from Favorites' : 'Add to Favorites',
                ),
                onTap: () {
                  Navigator.pop(context);
                  _toggleFavorite(document);
                },
              ),
              ListTile(
                leading: Icon(
                  document.isPublishedToLibrary
                      ? Icons.unpublished
                      : Icons.publish,
                  color: document.isPublishedToLibrary
                      ? Colors.orange
                      : Colors.indigo,
                ),
                title: Text(
                  document.isPublishedToLibrary
                      ? 'Unpublish from Library'
                      : 'Publish to Library',
                ),
                onTap: () async {
                  Navigator.pop(context);
                  final wasPublished = document.isPublishedToLibrary;
                  final svc = DocumentLibraryService();
                  final result = wasPublished
                      ? await svc.unpublishDocument(document.id)
                      : await svc.publishDocument(document.id);
                  if (!mounted) return;

                  if (result['success'] == true) {
                    setState(() {
                      document.isPublishedToLibrary = !wasPublished;
                    });
                  }

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        result['success'] == true
                            ? (wasPublished
                                  ? 'Document unpublished from library'
                                  : 'Document published to library')
                            : result['message']?.toString() ?? 'Action failed',
                      ),
                      backgroundColor: result['success'] == true
                          ? Colors.green
                          : Colors.red,
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete'),
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteOptions(context, index, document);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
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

  void _showTopMessage(String message) {
    if (!mounted) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        return SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Material(
              color: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.only(top: 12, left: 16, right: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(40),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);
    Future.delayed(const Duration(milliseconds: 1500), () {
      entry.remove();
    });
  }

  Widget _buildStatusBanner({required String message, required Color color}) {
    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Text(
        message,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }

  Widget _buildOfflineBanner() {
    return _buildStatusBanner(
      message: 'Offline mode: showing cached data',
      color: Colors.orange,
    );
  }

  Widget _buildLoadingBanner() {
    return _buildStatusBanner(
      message: 'Loading documents...',
      color: Colors.blue,
    );
  }

  Widget _buildDownloadingBanner() {
    return _buildStatusBanner(
      message: 'Downloading document...',
      color: Colors.green,
    );
  }

  Widget _buildUploadingBanner() {
    return _buildStatusBanner(
      message: 'Uploading document...',
      color: Colors.purple,
    );
  }

  // ADD THESE MISSING METHODS
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

  // Original folder list item (updated)
  Widget _buildFolderListItem(Folder folder, int index) {
    final r = context.r;
    return Container(
      margin: EdgeInsets.only(bottom: r.p(8)),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(r.p(12)),
        elevation: 1,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => FolderScreen(
                  folderId: folder.id,
                  folderName: folder.name,
                  userName: _displayUserName,
                ),
              ),
            );
          },
          onLongPress: () => _showDeleteFolderConfirmation(context, index),
          borderRadius: BorderRadius.circular(r.p(12)),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: r.p(14),
              vertical: r.p(11),
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(r.p(12)),
              border: Border.all(color: Colors.grey.shade200, width: 1),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(r.p(9)),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(r.p(10)),
                  ),
                  child: Icon(
                    Icons.folder,
                    color: Colors.amber.shade700,
                    size: r.sp(26),
                  ),
                ),
                SizedBox(width: r.p(14)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        folder.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: r.sp(15),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: r.p(4)),
                PopupMenuButton(
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'download',
                      child: Row(
                        children: [
                          Icon(
                            Icons.download_rounded,
                            size: r.sp(18),
                            color: Colors.green,
                          ),
                          SizedBox(width: r.p(8)),
                          const Text('Download'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'download_zip',
                      child: Row(
                        children: [
                          Icon(
                            Icons.archive_rounded,
                            size: r.sp(18),
                            color: Colors.green,
                          ),
                          SizedBox(width: r.p(8)),
                          const Text('Download as ZIP'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'share',
                      child: Row(
                        children: [
                          Icon(Icons.share, size: r.sp(18), color: Colors.blue),
                          SizedBox(width: r.p(8)),
                          const Text('Share Folder'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, size: r.sp(18), color: Colors.red),
                          SizedBox(width: r.p(8)),
                          const Text('Delete Folder'),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (value) {
                    if (value == 'download') {
                      _downloadFolderFiles(folder);
                    } else if (value == 'download_zip') {
                      _downloadFolderZip(folder);
                    } else if (value == 'share') {
                      _showFolderShareDialog(folder);
                    } else if (value == 'delete') {
                      _showDeleteFolderConfirmation(context, index);
                    }
                  },
                  child: Container(
                    width: r.p(34),
                    height: r.p(34),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(
                        Icons.more_vert,
                        size: r.sp(18),
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Original document card (updated)
  Widget _buildDocumentCard(
    Document document,
    int index, {
    String? searchModeLabel,
  }) {
    final r = context.r;
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
    IconData icon = docIcons[fileType] ?? Icons.insert_drive_file;
    Color color = docColors[fileType] ?? Colors.indigo;

    // Format the date to DD MM YYYY
    String formattedDate = _formatToDDMMYYYY(document.uploadDate);
    final folderPath = _documentDirectoryPath(document);

    // Get document opener service instance
    final documentOpener = DocumentOpenerService();

    // IMPORTANT: Check if this specific document is expanded using its ID
    bool isExpanded = _expandedStates[document.id] ?? false;

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
                                    style: TextStyle(
                                      fontSize: r.sp(15),
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: isExpanded ? 2 : 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                      SizedBox(height: r.p(3)),
                                  
                        Text(
                          '$formattedDate',
                          style:w500_14Poppins(color:Colors.grey.shade600 ),
                        ),
                        SizedBox(height: r.p(2)),
                        Text(
                          'Path: $folderPath / ${document.name}',
                          style: w400_13Poppins(color:Colors.grey.shade600 ),
                          maxLines: isExpanded ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                                ],
                              ),
                            ),
                          
                            
                            // Expand / collapse
                            GestureDetector(
                              onTap: () => setState(() {
                                _expandedStates[document.id] = !isExpanded;
                              }),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                width: r.p(32),
                                height: r.p(32),
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
                                      size: r.sp(20),
                                      color: isExpanded
                                          ? color
                                          : Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
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
                              onPressed: () =>
                                  _showDocumentActions(document, index),
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
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: SizedBox(
                  height: isExpanded ? null : 0,
                  child: Column(
                    children: [
                      SizedBox(height: r.p(14)),
                      const Divider(height: 1),
                      SizedBox(height: r.p(10)),
                      _buildDetailRow('Owner', document.owner, Icons.person_2_outlined),
                      _buildDetailRow('Path', folderPath, Icons.folder_copy_outlined),
                      _buildDetailRow(
                        'Classification',
                        document.classification[0].toUpperCase() + document.classification.substring(1),
                        Icons.security_outlined,
                      ),
                      _buildDetailRow(
                        'Sharing',
                        document.sharingType,
                        Icons.share_outlined,
                      ),
                      if (document.details.isNotEmpty)
                        _buildDetailRow(
                          'Details',
                          document.details,
                          Icons.info_outline,
                        ),
                      SizedBox(height: r.p(14)),
                      // Action buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => documentOpener.openPreviewDialog(
                                context: context,
                                document: document,
                              ),
                              icon: Icon(Icons.visibility, size: btnIconSize),
                              label: Text(
                                'View',
                                style: TextStyle(fontSize: r.sp(12)),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.purple,
                                side: const BorderSide(color: Colors.purple),
                                padding: btnPad,
                              ),
                            ),
                          ),
                          SizedBox(width: r.p(6)),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _showDocumentVersions(document),
                              icon: Icon(Icons.history, size: btnIconSize),
                              label: Text(
                                'Versions',
                                style: TextStyle(fontSize: r.sp(12)),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.blue,
                                side: const BorderSide(color: Colors.blue),
                                padding: btnPad,
                              ),
                            ),
                          ),
                          SizedBox(width: r.p(6)),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _downloadDocument(document),
                              icon: Icon(Icons.download, size: btnIconSize),
                              label: Text(
                                document.allowDownload ? 'Download' : 'Request',
                                style: TextStyle(fontSize: r.sp(12)),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.green,
                                side: const BorderSide(color: Colors.green),
                                padding: btnPad,
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

  // Add this helper method to format dates to DD MM YYYY
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

  Widget _buildDetailRow(String label, String value, IconData icon) {
    final r = context.r;
    return Padding(
      padding: EdgeInsets.only(bottom: r.p(7)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: r.sp(15), color: Colors.grey),
          SizedBox(width: r.p(8)),
          SizedBox(
            width: r.p(100),
            child: Text(
              '$label:',
              style: w400_14Poppins(color:Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: w500_14Poppins(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 20),
            const Text(
              'No Documents Yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Upload your first document using the Upload Document tab',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

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
    if (_docTypeFilter != 'All') {
      allDocs = allDocs.where((doc) {
        final ext = doc.type.toLowerCase().replaceAll('.', '');
        switch (_docTypeFilter) {
          case 'PDF':
            return ext == 'pdf';
          case 'Docs':
            return ext == 'doc' || ext == 'docx' || ext == 'txt' || ext == 'odt';
          case 'Sheets':
            return ext == 'xls' || ext == 'xlsx' || ext == 'csv' || ext == 'ods';
          default:
            return true;
        }
      }).toList();
    }

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

  Widget _buildProfileSidebar() {
    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      child: Container(
        width: 300,
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(30),
              blurRadius: 10,
              offset: const Offset(-2, 0),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: const Color.fromARGB(255, 43, 65, 189),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Profile',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _showProfileDrawer = false;
                      });
                    },
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      backgroundColor: const Color.fromARGB(255, 43, 65, 189),
                      radius: 50,
                      child: Text(
                        _getUserInitial(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    Text(
                      _displayUserName,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    if (_displayUserEmail != null &&
                        _displayUserEmail!.isNotEmpty)
                      Column(
                        children: [
                          const SizedBox(height: 20),
                          const Row(
                            children: [
                              Icon(
                                Icons.email_outlined,
                                color: Colors.grey,
                                size: 18,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Email',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _displayUserEmail!,
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),

                    const SizedBox(height: 20),
                    const Row(
                      children: [
                        Icon(Icons.work_outline, color: Colors.grey, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Experience',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '5+ Years',
                      style: TextStyle(fontSize: 16, color: Colors.black87),
                    ),

                    const Spacer(),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _showProfileDrawer = false;
                          });
                          _showLogoutDialog();
                        },
                        icon: const Icon(Icons.logout),
                        label: const Text(
                          'Logout',
                          style: TextStyle(fontSize: 16),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color.fromARGB(
                            255,
                            43,
                            65,
                            189,
                          ),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}