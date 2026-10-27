import 'dart:async';

import 'package:digi_sanchika/utils/app_fonts.dart';
import 'package:digi_sanchika/widgets/folder_illustration.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:digi_sanchika/models/document.dart';
import 'package:digi_sanchika/models/folder.dart';
import 'package:digi_sanchika/presentations/Screens/folder_screen.dart';
import 'package:digi_sanchika/services/api_client.dart';
import 'package:digi_sanchika/services/api_service.dart';
import 'package:digi_sanchika/services/folder_download_service.dart';
import 'package:digi_sanchika/services/document_opener_service.dart';
import 'package:digi_sanchika/services/my_documents_service.dart';
import 'package:digi_sanchika/services/document_library_service.dart';
import 'package:digi_sanchika/utils/responsive_helper.dart';
import 'package:digi_sanchika/widgets/download_feedback.dart';
import 'package:digi_sanchika/widgets/dismiss_keyboard.dart';
import 'package:digi_sanchika/widgets/folder_tile.dart';
import 'package:digi_sanchika/widgets/share_access_sheet.dart';

class AllFoldersScreen extends StatefulWidget {
  final String? userName;

  const AllFoldersScreen({super.key, this.userName});

  @override
  State<AllFoldersScreen> createState() => _AllFoldersScreenState();
}

class _AllFoldersScreenState extends State<AllFoldersScreen> {
  bool _loading = true;
  String _search = '';
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _lastDocumentSearchQuery = '';
  bool _docSearching = false;
  String? _docSearchError;
  List<Document> _searchDocuments = const [];
  final Map<String, String> _folderPathCache = {};
  final Set<String> _publishingFolderIds = {};
  final Set<String> _publishedFolderIds = {};

  List<Folder> _allFolders = const [];

  String get _ownerName {
    final raw = widget.userName?.trim() ?? '';
    return raw.isEmpty ? 'Unknown' : raw;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading) setState(() => _loading = true);
    try {
      final folders = await _getAllFoldersFlat();
      final publishedFolders = await DocumentLibraryService().fetchLibraryFolders();
      folders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() {
        _allFolders = folders;
        _publishedFolderIds
          ..clear()
          ..addAll(publishedFolders.map((folder) => folder.id));
        _folderPathCache.clear();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load folders: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _refresh() async {
    await _load(showLoading: false);
    final q = _search.trim();
    if (q.isNotEmpty) {
      await _loadSearchDocuments(q, showLoading: false);
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
          owner: _ownerName,
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

  void _onSearchChanged(String value) {
    setState(() => _search = value);

    _searchDebounce?.cancel();
    final q = value.trim();

    if (q.isEmpty) {
      setState(() {
        _docSearching = false;
        _docSearchError = null;
        _searchDocuments = const [];
        _lastDocumentSearchQuery = '';
      });
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _loadSearchDocuments(q);
    });
  }

  Future<void> _loadSearchDocuments(
    String query, {
    bool showLoading = true,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return;
    if (!ApiService.isConnected) {
      if (!mounted) return;
      setState(() {
        _docSearching = false;
        _docSearchError = 'Offline: showing only folder matches';
        _searchDocuments = const [];
        _lastDocumentSearchQuery = q;
      });
      return;
    }

    if (_lastDocumentSearchQuery == q && _searchDocuments.isNotEmpty) return;

    if (showLoading) {
      setState(() {
        _docSearching = true;
        _docSearchError = null;
        _lastDocumentSearchQuery = q;
      });
    }

    try {
      final result = await MyDocumentsService.keywordSearch(
        query: q,
        scope: 'mine',
        limit: 30,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        final docs = (result['documents'] as List?)?.cast<Document>() ?? const [];
        setState(() {
          _docSearching = false;
          _docSearchError = null;
          _searchDocuments = docs;
          _lastDocumentSearchQuery = q;
        });
        return;
      }

      setState(() {
        _docSearching = false;
        _docSearchError = (result['error'] ?? 'Search failed').toString();
        _searchDocuments = const [];
        _lastDocumentSearchQuery = q;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _docSearching = false;
        _docSearchError = e.toString();
        _searchDocuments = const [];
        _lastDocumentSearchQuery = q;
      });
    }
  }

  List<Folder> get _filteredFolders {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _allFolders;
    return _allFolders
        .where((f) => f.name.toLowerCase().contains(q))
        .toList(growable: false);
  }

  String _folderPathForId(String? folderId) {
    final id = (folderId ?? '').trim();
    if (id.isEmpty) return '';
    final cached = _folderPathCache[id];
    if (cached != null) return cached;

    final byId = <String, Folder>{for (final f in _allFolders) f.id: f};
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

  Future<void> _deleteFolder(Folder folder) async {
    if (folder.id == 'home') return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.delete, color: Colors.red, size: 26),
            SizedBox(width: 10),
            Text('Delete Folder'),
          ],
        ),
        content: Text('Are you sure you want to delete folder "${folder.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    if (!ApiService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot delete while offline'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final result = await MyDocumentsService.deleteFolder(folder.id);
      if (result['success'] != true) {
        throw Exception((result['error'] ?? 'Delete failed').toString());
      }

      if (!mounted) return;
      setState(() {
        _allFolders = _allFolders.where((f) => f.id != folder.id).toList();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Folder "${folder.name}" deleted'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
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
            backgroundColor:
                (result['requestCreated'] == true) ? Colors.orange : Colors.red,
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error']?.toString() ?? 'Download failed'),
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
            backgroundColor:
                (result['requestCreated'] == true) ? Colors.orange : Colors.red,
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error']?.toString() ?? 'Download failed'),
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

  Future<void> _shareFolder(Folder folder) async {
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

  Future<void> _publishFolder(Folder folder) async {
    if (_publishingFolderIds.contains(folder.id)) return;
    setState(() => _publishingFolderIds.add(folder.id));
    try {
      final isPublished = _publishedFolderIds.contains(folder.id);
      final service = DocumentLibraryService();
      final result = isPublished
          ? await service.unpublishFolder(folder.id)
          : await service.publishFolder(folder.id);
      if (!mounted) return;
      if (result['success'] == true) {
        setState(() {
          if (isPublished) {
            _publishedFolderIds.remove(folder.id);
          } else {
            _publishedFolderIds.add(folder.id);
          }
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (result['message'] ??
                    (result['success'] == true
                        ? (isPublished
                              ? 'Folder unpublished from library'
                              : 'Folder published to library')
                        : 'Folder publish failed'))
                .toString(),
          ),
          backgroundColor: result['success'] == true ? Colors.green : Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _publishingFolderIds.remove(folder.id));
    }
  }

  String _folderSizeLabel(Folder folder) {
    final sizes = folder.documents
        .map((document) => document.size.trim())
        .where((size) => size.isNotEmpty)
        .toList();
    return sizes.isEmpty ? '0 KB' : sizes.first;
  }

  String _folderAgeLabel(Folder folder) {
    final days = DateTime.now().difference(folder.createdAt).inDays;
    if (days <= 0) return 'today';
    if (days < 7) return '${days}d ago';
    final weeks = days ~/ 7;
    if (weeks < 5) return '${weeks}w ago';
    final months = days ~/ 30;
    if (months < 12) return '${months}mo ago';
    return '${days ~/ 365}y ago';
  }

  Widget _buildFolderCard(Folder folder) {
    final r = context.r;
    final radius = BorderRadius.circular(r.p(20));
    final fileCount = folder.documents.length;

    return Container(
      margin: EdgeInsets.only(bottom: r.p(10)),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: radius,
            border: Border.all(color: Colors.grey.shade100, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => FolderScreen(
                    folderId: folder.id,
                    folderName: folder.name,
                    userName: widget.userName,
                  ),
                ),
              );
            },
            onLongPress: () => _deleteFolder(folder),
            child: Padding(
              padding: EdgeInsets.all(r.p(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: r.p(54),
                        height: r.p(54),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF2FF),
                          borderRadius: BorderRadius.circular(r.p(16)),
                        ),
                        child: FolderIllustration(size: r.p(38)),
                      ),
                      PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          Icons.more_horiz,
                          size: r.sp(24),
                          color: Colors.grey.shade400,
                        ),
                        onSelected: (value) {
                          if (value == 'download') {
                            _downloadFolderFiles(folder);
                          } else if (value == 'download_zip') {
                            _downloadFolderZip(folder);
                          } else if (value == 'share') {
                            _shareFolder(folder);
                          } else if (value == 'publish') {
                            _publishFolder(folder);
                          } else if (value == 'delete') {
                            _deleteFolder(folder);
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'download',
                            child: Row(
                              children: [
                                Icon(Icons.download_rounded, size: r.sp(18), color: Colors.green),
                                SizedBox(width: r.p(8)),
                                const Text('Download'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'download_zip',
                            child: Row(
                              children: [
                                Icon(Icons.archive_rounded, size: r.sp(18), color: Colors.green),
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
                            value: 'publish',
                            child: Row(
                              children: [
                                Icon(
                                  _publishedFolderIds.contains(folder.id)
                                      ? Icons.unpublished_rounded
                                      : Icons.library_add_rounded,
                                  size: r.sp(18),
                                  color: _publishedFolderIds.contains(folder.id)
                                      ? Colors.orange
                                      : Colors.indigo,
                                ),
                                SizedBox(width: r.p(8)),
                                Text(
                                  _publishedFolderIds.contains(folder.id)
                                      ? 'Unpublish from Library'
                                      : 'Publish to Library',
                                ),
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
                      ),
                    ],
                  ),
                  SizedBox(height: r.p(16)),
                  Text(
                    folder.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: r.sp(18),
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  SizedBox(height: r.p(5)),
                  Text(
                    '$fileCount ${fileCount == 1 ? 'file' : 'files'}',
                    style: TextStyle(
                      fontSize: r.sp(14),
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  SizedBox(height: r.p(20)),
                  Text(
                    '${_folderSizeLabel(folder)}  •  ${_folderAgeLabel(folder)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: r.sp(13),
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReferenceFolderCard(Folder folder) {
    final r = context.r;
    final fileCount = folder.documents.length;
    final files = '$fileCount ${fileCount == 1 ? 'file' : 'files'}';

    return FolderTile(
      title: folder.name,
      details: [
        files,
        '${_folderSizeLabel(folder)} · ${_folderAgeLabel(folder)}',
      ],
      frontTop: 0.4,
      tabWidth: 0.34,
      titleSize: r.sp(15),
      detailSize: r.sp(11.5),
      titleLines: 2,
      contentPadding: EdgeInsets.fromLTRB(r.p(14), 0, r.p(4), r.p(10)),
      radius: BorderRadius.circular(r.p(20)),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FolderScreen(
              folderId: folder.id,
              folderName: folder.name,
              userName: widget.userName,
            ),
          ),
        );
      },
      onLongPress: () => _deleteFolder(folder),
      menu: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        icon: Icon(Icons.more_horiz, size: r.sp(24), color: Colors.white),
        onSelected: (value) {
          if (value == 'download') {
            _downloadFolderFiles(folder);
          } else if (value == 'download_zip') {
            _downloadFolderZip(folder);
          } else if (value == 'share') {
            _shareFolder(folder);
          } else if (value == 'publish') {
            _publishFolder(folder);
          } else if (value == 'delete') {
            _deleteFolder(folder);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(value: 'download', child: Text('Download')),
          PopupMenuItem(value: 'download_zip', child: Text('Download as ZIP')),
          PopupMenuItem(value: 'share', child: Text('Share Folder')),
          PopupMenuItem(
            value: 'publish',
            child: Text(
              _publishedFolderIds.contains(folder.id)
                  ? 'Unpublish from Library'
                  : 'Publish to Library',
            ),
          ),
          PopupMenuItem(value: 'delete', child: Text('Delete Folder')),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    final r = context.r;
    return Padding(
      padding: EdgeInsets.only(bottom: r.p(8), top: r.p(6)),
      child: Text(
        title,
        style: TextStyle(
          fontSize: r.sp(14),
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade800,
        ),
      ),
    );
  }

  Widget _buildDocumentSearchTile(Document document) {
    final r = context.r;
    final fromId = _folderPathForId(document.folderId).trim();
    final folderPath = fromId.isNotEmpty
        ? fromId
        : (document.folder.trim().isEmpty ? 'Unknown folder' : document.folder);
    final fullPath = folderPath.trim().isEmpty
        ? document.name
        : '$folderPath / ${document.name}';

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r.p(16))),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: r.p(14), vertical: r.p(6)),
        leading: Container(
          width: r.p(44),
          height: r.p(44),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(r.p(12)),
          ),
          child: Icon(Icons.insert_drive_file, color: Colors.blue.shade700),
        ),
        title: Text(
          document.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: r.sp(14)),
        ),
        subtitle: Text(
          fullPath,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: r.sp(12), color: Colors.grey.shade600),
        ),
        onTap: () {
          DocumentOpenerService().openViewer(context: context, document: document);
        },
        onLongPress: () {
          DocumentOpenerService().handleDoubleTap(context: context, document: document);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final folders = _filteredFolders;
    final query = _search.trim();
    final showSearchResults = query.isNotEmpty;
    final documents = showSearchResults ? _searchDocuments : const <Document>[];

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
      backgroundColor: Colors.grey.shade50,
iconTheme: IconThemeData(color: Colors.black87),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Text('Folders', style: w600_16Poppins()),
            Text(
              'All folders',
              style: w400_12Poppins()
            ),
          ],
        ),
      ),
      body: DismissKeyboard(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final crossAxisCount = width >= 900 ? 3 : (width >= 600 ? 2 : 1);

            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.all(r.p(14)),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      children: [
                        TextField(
                          controller: _searchController,
                          onChanged: _onSearchChanged,
                          decoration: InputDecoration(
                            hintText: 'Search folders or files...',
                            prefixIcon: const Icon(Icons.search),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: r.p(12),
                              vertical: r.p(12),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(r.p(14)),
                              borderSide: BorderSide(color: Colors.grey.shade200),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(r.p(14)),
                              borderSide: BorderSide(color: Colors.grey.shade200),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(r.p(14)),
                              borderSide: BorderSide(color: Colors.blue.shade300),
                            ),
                          ),
                        ),
                        SizedBox(height: r.p(14)),
                      ],
                    ),
                  ),
                ),
                if (_loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: r.p(14)),
                    sliver: SliverToBoxAdapter(
                      child: _buildSectionHeader(showSearchResults ? 'Folder matches' : 'All folders'),
                    ),
                  ),
                  if (folders.isEmpty)
                    SliverPadding(
                      padding: EdgeInsets.only(top: r.p(18)),
                      sliver: SliverToBoxAdapter(
                        child: Center(
                          child: Text(
                            showSearchResults
                                ? 'No folder matches for "$query"'
                                : 'No folders found',
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                        ),
                      ),
                    )
                  else if (crossAxisCount == 1)
                    SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: r.p(14)),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => _buildReferenceFolderCard(folders[i]),
                          childCount: folders.length,
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: r.p(14)),
                      sliver: SliverGrid(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => _buildReferenceFolderCard(folders[i]),
                          childCount: folders.length,
                        ),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: r.p(12),
                          mainAxisSpacing: r.p(12),
                          childAspectRatio: 1.08,
                        ),
                      ),
                    ),
                  if (showSearchResults) ...[
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(r.p(14), r.p(14), r.p(14), r.p(6)),
                      sliver: SliverToBoxAdapter(child: _buildSectionHeader('File matches')),
                    ),
                    if (_docSearchError != null)
                      SliverPadding(
                        padding: EdgeInsets.symmetric(horizontal: r.p(14)),
                        sliver: SliverToBoxAdapter(
                          child: Text(
                            _docSearchError!,
                            style: TextStyle(color: Colors.orange.shade800),
                          ),
                        ),
                      ),
                    if (_docSearching)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      )
                    else if (documents.isEmpty)
                      SliverPadding(
                        padding: EdgeInsets.only(top: r.p(10)),
                        sliver: SliverToBoxAdapter(
                          child: Center(
                            child: Text(
                              'No file matches for "$query"',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: EdgeInsets.symmetric(horizontal: r.p(14)),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, i) => _buildDocumentSearchTile(documents[i]),
                            childCount: documents.length,
                          ),
                        ),
                      ),
                    SliverToBoxAdapter(child: SizedBox(height: r.p(14))),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    ),
    );
  }
}
