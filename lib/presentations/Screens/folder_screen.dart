import 'package:flutter/material.dart';
import 'package:digi_sanchika/utils/responsive_helper.dart';
import 'package:digi_sanchika/services/folder_service.dart';
import 'package:digi_sanchika/services/api_service.dart';
import 'package:digi_sanchika/models/folder.dart';
import 'package:digi_sanchika/models/document.dart';
import 'package:digi_sanchika/presentations/Screens/home_page.dart';
import 'package:digi_sanchika/services/document_opener_service.dart';
import 'package:digi_sanchika/services/favorites_service.dart';
import 'package:digi_sanchika/presentations/Screens/document_tools_screen.dart';
import 'package:digi_sanchika/widgets/share_access_sheet.dart';
import 'package:digi_sanchika/widgets/folder_alert_sheet.dart';
import 'package:digi_sanchika/services/download_access_service.dart';
import 'package:digi_sanchika/services/download_requests_service.dart';
import 'package:digi_sanchika/services/folder_download_service.dart';
import 'package:digi_sanchika/services/folder_operations_service.dart';
import 'package:digi_sanchika/services/recycle_bin_service.dart';
import 'package:digi_sanchika/services/document_library_service.dart';
import 'package:digi_sanchika/services/my_documents_service.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:digi_sanchika/models/app_view_mode.dart';
import 'package:digi_sanchika/widgets/download_feedback.dart';
import 'package:digi_sanchika/widgets/dismiss_keyboard.dart';

// Add ShareUser model if not exists
class ShareUser {
  final String id;
  final String name;
  final String? employeeId;
  final String? department;
  final String? avatarUrl;
  bool isSelected;

  ShareUser({
    required this.id,
    required this.name,
    this.employeeId,
    this.department,
    this.avatarUrl,
    this.isSelected = false,
  });

  ShareUser copyWith({
    String? id,
    String? name,
    String? employeeId,
    String? department,
    String? avatarUrl,
    bool? isSelected,
  }) {
    return ShareUser(
      id: id ?? this.id,
      name: name ?? this.name,
      employeeId: employeeId ?? this.employeeId,
      department: department ?? this.department,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isSelected: isSelected ?? this.isSelected,
    );
  }
}

class FolderScreen extends StatefulWidget {
  final String folderId;
  final String folderName;
  final String? parentFolderId;
  final String? parentFolderName;
  final String? userName;

  const FolderScreen({
    super.key,
    required this.folderId,
    required this.folderName,
    this.parentFolderId,
    this.parentFolderName,
    this.userName,
  });

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  List<Document> documents = [];
  List<Folder> subfolders = [];
  bool _isLoading = true;
  bool _isDownloading = false;
  String _errorMessage = '';
  final TextEditingController _searchController = TextEditingController();
  bool _showRecent = false;

  // Add these variables for layout modes (same as HomePage)
  AppViewMode _currentViewMode = AppViewMode.list;
  Map<String, bool> _expandedStates = {};

  final FavoritesService _favoritesService = FavoritesService();
  final Map<String, String> _favoriteDocumentMap =
      {}; // For document card expand/collapse

  // Users for sharing
  List<ShareUser> _shareUsers = [];

  @override
  void initState() {
    super.initState();
    _loadFolderContents();
    _loadShareUsers();
    _loadFavorites();
  }

  Future<void> _loadFolderContents() async {
    if (!ApiService.isConnected) {
      setState(() {
        _errorMessage = 'Offline - Cannot load folder contents';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final result = await FolderService.getFolderContents(widget.folderId);

      if (result['success'] == true) {
        setState(() {
          documents = result['documents'] as List<Document>;
          subfolders = result['subfolders'] as List<Folder>;
        });
      } else {
        setState(() {
          _errorMessage =
              result['error']?.toString() ?? 'Failed to load folder';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadShareUsers() async {
    try {
      final users = await FolderService.getUsersForSharing();
      if (users != null && users.isNotEmpty) {
        setState(() {
          _shareUsers = users
              .map(
                (user) => ShareUser(
                  id: user.id?.isNotEmpty == true ? user.id! : 'unknown',
                  name: user.name?.isNotEmpty == true
                      ? user.name!
                      : 'Unknown User',
                  employeeId: user.employeeId,
                  department: user.department,
                  avatarUrl: user.avatarUrl,
                  isSelected: false,
                ),
              )
              .where((user) => user.name.isNotEmpty)
              .toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading share users: $e');

      setState(() {
        _shareUsers = [
          ShareUser(id: '1234', name: 'Ashok Buddharaju', employeeId: '1234'),
          ShareUser(
            id: '5017',
            name: 'Raja Shekhar Perepa',
            employeeId: '5017',
          ),
          ShareUser(id: '2923', name: 'Thakur Vijay Singh', employeeId: '2923'),
          ShareUser(
            id: '2961',
            name: 'Lt Col Ashutosh Jha',
            employeeId: '2961',
          ),
          ShareUser(id: '2930', name: 'Bhuvan Varshit', employeeId: '2930'),
          ShareUser(
            id: 'ADMIN001',
            name: 'System Administrator',
            employeeId: 'ADMIN001',
          ),
        ];
      });
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
      setState(() {});
    } catch (_) {}
  }

  bool _isFavorite(String documentId) {
    return _favoriteDocumentMap.containsKey(documentId);
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

  void _showTopMessage(String message) {
    if (!mounted) return;
    final overlay = Overlay.of(context);
    if (overlay == null) return;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        final r = context.r;
        return SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Material(
              color: Colors.transparent,
              child: Container(
                margin: EdgeInsets.only(
                  top: r.p(12),
                  left: r.p(16),
                  right: r.p(16),
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: r.p(16),
                  vertical: r.p(10),
                ),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(r.p(8)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(40),
                      blurRadius: r.p(8),
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  message,
                  style: TextStyle(color: Colors.white, fontSize: r.sp(13)),
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

  void _navigateToSubfolder(Folder folder) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FolderScreen(
          folderId: folder.id,
          folderName: folder.name,
          parentFolderId: widget.folderId,
          parentFolderName: widget.folderName,
          userName: widget.userName,
        ),
      ),
    );
  }

  void _goBack() {
    if (widget.parentFolderId != null) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              HomePage(userName: widget.userName, userEmail: null),
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
              _deleteDocument(index);
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
                final ok =
                    (direct['success'] == true) &&
                    await RecycleBinService().deletePermanently(
                      entityType: 'document',
                      entityId: document.id,
                    );
                if (!mounted) return;
                if (ok) {
                  setState(() {
                    if (document.id.trim().isNotEmpty) {
                      documents.removeWhere((d) => d.id == document.id);
                    } else {
                      documents.removeWhere(
                        (d) =>
                            d.name == document.name &&
                            d.path == document.path &&
                            d.uploadDate == document.uploadDate,
                      );
                    }
                  });
                  try {
                    await _loadFolderContents();
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

  Future<void> _deleteDocument(int index) async {
    if (index >= 0 && index < documents.length) {
      final docToDelete = documents[index];
      try {
        if (ApiService.isConnected) {
          final result = await RecycleBinService().moveToRecycleBin(
            entityType: 'document',
            entityId: docToDelete.id,
          );
          if (result['success'] != true) {
            // Compatibility fallback: some backends soft-delete via DELETE /documents/:id
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

        if (!mounted) return;
        setState(() {
          documents.removeAt(index);
        });
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('Moved "${docToDelete.name}" to Recycle Bin'),
            backgroundColor: Colors.orange,
          ),
        );
        // Auto-refresh to reflect backend state and folder counts.
        try {
          await _loadFolderContents();
        } catch (_) {}
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
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
    });

    try {
      final result = await DownloadAccessService.downloadBytesWithAccess(
        documentId: document.id,
      );

      if (result['success'] == true) {
        final dir = await getApplicationDocumentsDirectory();
        final filePath = '${dir.path}/${document.name}';
        final file = File(filePath);
        await file.writeAsBytes((result['bytes'] as List<int>));

        if (!mounted) return;
        await DownloadFeedback.showDownloadedDialog(
          context,
          filename: document.name,
          filePath: filePath,
        );
      } else if (result['requiresApproval'] == true) {
        final req = DownloadRequestsService();
        final reqResult = await req.createRequest(
          documentId: document.id,
          reason: 'Need offline copy',
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              reqResult['success'] == true
                  ? 'Download request sent for approval'
                  : (reqResult['message'] ?? 'Download request failed'),
            ),
            backgroundColor: reqResult['success'] == true
                ? Colors.orange
                : Colors.red,
          ),
        );
      } else {
        throw Exception(result['error'] ?? 'Download failed');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
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

  void _showDocumentActions(Document document, int index) {
    final isFav = _isFavorite(document.id);
    final documentOpener = DocumentOpenerService();

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
                    documentOpener.openPreviewDialog(
                      context: context,
                      document: document,
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.build, color: Colors.blueGrey),
                  title: const Text('Tools'),
                  onTap: () {
                    Navigator.pop(context);
                    _openDocumentTools(document);
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
                              : result['message']?.toString() ??
                                    'Action failed',
                        ),
                        backgroundColor: result['success'] == true
                            ? Colors.green
                            : Colors.red,
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text('Delete'),
                  onTap: () {
                    Navigator.pop(context);
                    _showDeleteOptions(context, index, document);
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

  Future<void> _showFolderShareSheet(Folder folder) async {
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

  void _confirmDeleteFolder(Folder folder) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Folder'),
        content: Text(
          'Delete "${folder.name}"? This will remove its documents.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteFolder(folder);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFolder(Folder folder) async {
    try {
      if (!ApiService.isConnected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot delete while offline'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final ops = FolderOperationsService();
      final result = await ops.deleteFolder(folder.id);
      if (result['success'] == true) {
        setState(() {
          subfolders.removeWhere((f) => f.id == folder.id);
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Folder deleted'),
            backgroundColor: Colors.red,
          ),
        );
      } else {
        throw Exception(result['error'] ?? 'Delete failed');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Delete failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
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

  // Helper method for avatar color
  Color _getAvatarColor(String name) {
    final colors = [
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.indigo,
    ];
    final index = name.hashCode % colors.length;
    return colors[index];
  }

  // // Helper method for initials
  // String _getInitials(String name) {
  //   final parts = name.split(' ');
  //   if (parts.length >= 2) {
  //     return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  //   }
  //   return name.length >= 2 ? name.substring(0, 2).toUpperCase() : name;
  // }
  // Helper method for initials - FIXED VERSION
  String _getInitials(String name) {
    if (name.isEmpty) return '?';

    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return '?';

    final parts = trimmedName.split(' ');

    // Remove empty parts
    final validParts = parts.where((part) => part.isNotEmpty).toList();

    if (validParts.length >= 2) {
      // Get first letter of first and last name
      return '${validParts.first[0]}${validParts.last[0]}'.toUpperCase();
    }

    // If only one part, get first 2 characters if available
    if (trimmedName.length >= 2) {
      return trimmedName.substring(0, 2).toUpperCase();
    }

    // If only 1 character
    return trimmedName[0].toUpperCase();
  }

  // FIXED SHARE DIALOG METHOD
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

    // Prefer the new share sheet. If it fails for any reason, fall back to the
    // legacy in-dialog user picker below.
    try {
      await ShareAccessSheet.showForDocument(
        context: context,
        documentId: document.id,
        documentName: document.name,
      );
      return;
    } catch (e) {
      debugPrint('ShareAccessSheet failed, falling back to legacy dialog: $e');
    }

    // Create a copy of users to avoid state issues
    List<ShareUser> dialogUsers = _shareUsers.map((user) {
      return ShareUser(
        id: user.id,
        name: user.name,
        employeeId: user.employeeId,
        department: user.department,
        avatarUrl: user.avatarUrl,
        isSelected: user.isSelected,
      );
    }).toList();

    String searchQuery = '';
    bool isSharing = false;
    String? errorMessage;
    bool showSuccessMessage = false;

    // First, try to load already shared users
    try {
      final sharedUsers = await FolderService.getDocumentSharedUsers(
        document.id,
      );
      // Mark already shared users as selected
      for (var sharedUser in sharedUsers) {
        final index = dialogUsers.indexWhere((u) => u.id == sharedUser.id);
        if (index >= 0) {
          dialogUsers[index] = dialogUsers[index].copyWith(isSelected: true);
        }
      }
    } catch (e) {
      debugPrint('Error loading shared users: $e');
    }

    await showDialog(
      // ignore: use_build_context_synchronously
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            // FIXED: Ensure filteredUsers is always a valid list
            List<ShareUser> filteredUsers = [];

            if (searchQuery.isEmpty) {
              filteredUsers = List.from(dialogUsers);
            } else {
              filteredUsers = dialogUsers.where((user) {
                final nameMatch = user.name.toLowerCase().contains(
                  searchQuery.toLowerCase(),
                );
                final employeeIdMatch =
                    user.employeeId?.toLowerCase().contains(
                      searchQuery.toLowerCase(),
                    ) ??
                    false;
                final departmentMatch =
                    user.department?.toLowerCase().contains(
                      searchQuery.toLowerCase(),
                    ) ??
                    false;

                return nameMatch || employeeIdMatch || departmentMatch;
              }).toList();
            }

            int selectedCount = filteredUsers.where((u) => u.isSelected).length;

            return AlertDialog(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Digi Sanchika',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Share Document',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Share: ${document.name}',
                    style: const TextStyle(fontSize: 14, color: Colors.blue),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // ADD SUCCESS MESSAGE VISIBILITY
                  if (showSuccessMessage)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        '✓ Document already shared with selected users',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),

                    // User search field
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: 'Search users...',
                              prefixIcon: const Icon(Icons.search, size: 20),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              isDense: true,
                            ),
                            onChanged: (value) {
                              setState(() {
                                searchQuery = value;
                              });
                            },
                          ),
                        ),
                      ],
                    ),

                    if (errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        errorMessage!,
                        style: TextStyle(
                          color: Colors.red.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // Users list header
                    Row(
                      children: [
                        const Text(
                          'Select users to share with:',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        if (selectedCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$selectedCount selected',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Users list - FIXED with proper error handling
                    Container(
                      constraints: const BoxConstraints(
                        maxHeight: 300,
                        minHeight: 100,
                      ),
                      child: _buildUsersList(
                        filteredUsers,
                        dialogUsers,
                        setState,
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Permission selection
                    if (selectedCount > 0) ...[
                      const Divider(),
                      const SizedBox(height: 8),
                      const Text(
                        'Sharing permissions:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('View only'),
                              selected: true,
                              onSelected: (selected) {},
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('Can edit'),
                              selected: false,
                              onSelected: (selected) {},
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: selectedCount == 0 || isSharing
                      ? null
                      : () async {
                          final selectedUsers = dialogUsers
                              .where((u) => u.isSelected)
                              .toList();

                          setState(() {
                            isSharing = true;
                            errorMessage = null;
                          });

                          // Show sharing in progress
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Sharing "${document.name}" with ${selectedUsers.length} user${selectedUsers.length > 1 ? 's' : ''}...',
                              ),
                              backgroundColor: Colors.blue,
                            ),
                          );

                          // Call API to share document
                          final result = await FolderService.shareDocument(
                            documentId: document.id,
                            userIds: selectedUsers.map((u) => u.id).toList(),
                            permission: 'view', // Default to view only
                          );

                          setState(() {
                            isSharing = false;
                          });

                          if (result['success'] == true) {
                            setState(() {
                              showSuccessMessage = true;
                              // Reset selection after successful share
                              for (var user in dialogUsers) {
                                final index = dialogUsers.indexWhere(
                                  (u) => u.id == user.id,
                                );
                                if (index >= 0) {
                                  dialogUsers[index] = dialogUsers[index]
                                      .copyWith(isSelected: false);
                                }
                              }
                            });

                            // Wait a moment to show success, then close
                            await Future.delayed(
                              const Duration(milliseconds: 1500),
                            );
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  result['message'] ??
                                      'Document shared successfully!',
                                ),
                                backgroundColor: Colors.green,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          } else {
                            // Show error but don't close dialog
                            setState(() {
                              errorMessage =
                                  result['message'] ??
                                  result['error'] ??
                                  'Failed to share document. Please try again.';
                            });
                            // Also show snackbar error
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  result['message'] ??
                                      result['error'] ??
                                      'Failed to share document',
                                ),
                                backgroundColor: Colors.red,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: isSharing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text('Share'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Helper method to build users list safely
  Widget _buildUsersList(
    List<ShareUser> filteredUsers,
    List<ShareUser> dialogUsers,
    void Function(void Function()) setState,
  ) {
    if (filteredUsers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.group, size: 40, color: Colors.grey),
            const SizedBox(height: 8),
            Text(
              'No users available',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: filteredUsers.length,
      itemBuilder: (context, index) {
        // Safety check
        if (index < 0 || index >= filteredUsers.length) {
          return const SizedBox();
        }

        final user = filteredUsers[index];

        if (user.name.isEmpty) {
          return const SizedBox();
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: user.isSelected ? Colors.blue : Colors.grey.shade200,
              width: user.isSelected ? 1.5 : 1,
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            leading: CircleAvatar(
              backgroundColor: _getAvatarColor(user.name),
              child: user.avatarUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.network(
                        user.avatarUrl!,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                      ),
                    )
                  : Text(
                      _getInitials(user.name),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
            title: Text(
              user.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (user.employeeId != null)
                  Text(
                    user.employeeId!,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                if (user.department != null)
                  Text(
                    user.department!,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
              ],
            ),
            trailing: Checkbox(
              value: user.isSelected,
              onChanged: (value) {
                setState(() {
                  // Find and update the user in dialogUsers
                  final dialogIndex = dialogUsers.indexWhere(
                    (u) => u.id == user.id,
                  );
                  if (dialogIndex >= 0) {
                    dialogUsers[dialogIndex] = dialogUsers[dialogIndex]
                        .copyWith(isSelected: value ?? false);
                  }
                });
              },
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            onTap: () {
              setState(() {
                // Find and update the user in dialogUsers
                final dialogIndex = dialogUsers.indexWhere(
                  (u) => u.id == user.id,
                );
                if (dialogIndex >= 0) {
                  dialogUsers[dialogIndex] = dialogUsers[dialogIndex].copyWith(
                    isSelected: !dialogUsers[dialogIndex].isSelected,
                  );
                }
              });
            },
          ),
        );
      },
    );
  }

  /// NEW: Method to build layout selector (same as HomePage)
  Widget _buildLayoutSelector() {
    final r = context.r;
    return PopupMenuButton<AppViewMode>(
      tooltip: 'Change Layout',
      icon: Icon(
        _getViewModeIcon(_currentViewMode),
        color: const Color.fromARGB(255, 226, 227, 231),
        size: r.sp(24),
      ),
      onSelected: (AppViewMode mode) {
        setState(() {
          _currentViewMode = mode;
        });
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<AppViewMode>>[
        PopupMenuItem<AppViewMode>(
          value: AppViewMode.list,
          child: Row(
            children: [
              Icon(Icons.list, color: Colors.indigo),
              SizedBox(width: 8),
              Text('List View'),
              if (_currentViewMode == AppViewMode.list)
                Icon(Icons.check, color: Colors.green, size: 16),
            ],
          ),
        ),
        PopupMenuItem<AppViewMode>(
          value: AppViewMode.grid2x2,
          child: Row(
            children: [
              Icon(Icons.grid_on, color: Colors.indigo),
              SizedBox(width: 8),
              Text('Grid (2x2)'),
              if (_currentViewMode == AppViewMode.grid2x2)
                Icon(Icons.check, color: Colors.green, size: 16),
            ],
          ),
        ),
        PopupMenuItem<AppViewMode>(
          value: AppViewMode.grid3x3,
          child: Row(
            children: [
              Icon(Icons.view_module, color: Colors.indigo),
              SizedBox(width: 8),
              Text('Grid (3x3)'),
              if (_currentViewMode == AppViewMode.grid3x3)
                Icon(Icons.check, color: Colors.green, size: 16),
            ],
          ),
        ),
        PopupMenuItem<AppViewMode>(
          value: AppViewMode.compact,
          child: Row(
            children: [
              Icon(Icons.view_headline, color: Colors.indigo),
              SizedBox(width: 8),
              Text('Compact View'),
              if (_currentViewMode == AppViewMode.compact)
                Icon(Icons.check, color: Colors.green, size: 16),
            ],
          ),
        ),
        PopupMenuItem<AppViewMode>(
          value: AppViewMode.detailed,
          child: Row(
            children: [
              Icon(Icons.table_rows, color: Colors.indigo),
              SizedBox(width: 8),
              Text('Detailed View'),
              if (_currentViewMode == AppViewMode.detailed)
                Icon(Icons.check, color: Colors.green, size: 16),
            ],
          ),
        ),
      ],
    );
  }

  IconData _getViewModeIcon(AppViewMode mode) {
    switch (mode) {
      case AppViewMode.list:
        return Icons.list;
      case AppViewMode.grid2x2:
        return Icons.grid_on;
      case AppViewMode.grid3x3:
        return Icons.view_module;
      case AppViewMode.compact:
        return Icons.view_headline;
      case AppViewMode.detailed:
        return Icons.table_rows;
    }
  }

  // ADD THIS METHOD HERE
  String _getViewModeLabel(AppViewMode mode) {
    switch (mode) {
      case AppViewMode.list:
        return 'List';
      case AppViewMode.grid2x2:
        return 'Grid 2×2';
      case AppViewMode.grid3x3:
        return 'Grid 3×3';
      case AppViewMode.compact:
        return 'Compact';
      case AppViewMode.detailed:
        return 'Detailed';
    }
  }

  Widget _buildSubfoldersSection(List<Folder> folders) {
    if (folders.isEmpty) return const SizedBox.shrink();

    final r = context.r;

    Widget content;
    switch (_currentViewMode) {
      case AppViewMode.list:
      case AppViewMode.detailed:
        content = Column(
          children: [
            for (final folder in folders)
              Container(
                margin: EdgeInsets.only(bottom: r.p(8)),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(r.p(12)),
                  elevation: 1,
                  child: InkWell(
                    onTap: () => _navigateToSubfolder(folder),
                    borderRadius: BorderRadius.circular(r.p(12)),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: r.p(16),
                        vertical: r.p(12),
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(r.p(12)),
                        border: Border.all(
                          color: Colors.grey.shade200,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(r.p(10)),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(r.p(10)),
                            ),
                            child: Icon(
                              Icons.folder,
                              color: Colors.amber.shade700,
                              size: r.sp(28),
                            ),
                          ),
                          SizedBox(width: r.p(16)),
                          Expanded(
                            child: Text(
                              folder.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: r.sp(16),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          PopupMenuButton<String>(
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'download',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.download_rounded,
                                      color: Colors.green,
                                    ),
                                    SizedBox(width: 8),
                                    Text('Download'),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'download_zip',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.archive_rounded,
                                      color: Colors.green,
                                    ),
                                    SizedBox(width: 8),
                                    Text('Download as ZIP'),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'share',
                                child: Row(
                                  children: [
                                    Icon(Icons.share, color: Colors.blue),
                                    SizedBox(width: 8),
                                    Text('Share'),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete, color: Colors.red),
                                    SizedBox(width: 8),
                                    Text('Delete'),
                                  ],
                                ),
                              ),
                            ],
                            onSelected: (v) {
                              if (v == 'download') {
                                _downloadFolderFiles(folder);
                              } else if (v == 'download_zip') {
                                _downloadFolderZip(folder);
                              } else if (v == 'share') {
                                _showFolderShareSheet(folder);
                              } else if (v == 'delete') {
                                _confirmDeleteFolder(folder);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
        break;
      case AppViewMode.compact:
        content = Column(
          children: [
            for (final folder in folders)
              ListTile(
                dense: true,
                visualDensity: const VisualDensity(vertical: -2),
                leading: Icon(
                  Icons.folder,
                  color: Colors.amber,
                  size: r.sp(20),
                ),
                title: Text(
                  folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: PopupMenuButton<String>(
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'download',
                      child: Row(
                        children: [
                          Icon(Icons.download_rounded, color: Colors.green),
                          SizedBox(width: 8),
                          Text('Download'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'download_zip',
                      child: Row(
                        children: [
                          Icon(Icons.archive_rounded, color: Colors.green),
                          SizedBox(width: 8),
                          Text('ZIP'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'share',
                      child: Row(
                        children: [
                          Icon(Icons.share, color: Colors.blue),
                          SizedBox(width: 8),
                          Text('Share'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Delete'),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (v) {
                    if (v == 'download') {
                      _downloadFolderFiles(folder);
                    } else if (v == 'download_zip') {
                      _downloadFolderZip(folder);
                    } else if (v == 'share') {
                      _showFolderShareSheet(folder);
                    } else if (v == 'delete') {
                      _confirmDeleteFolder(folder);
                    }
                  },
                ),
                onTap: () => _navigateToSubfolder(folder),
              ),
          ],
        );
        break;
      case AppViewMode.grid2x2:
      case AppViewMode.grid3x3:
        final crossAxisCount = _currentViewMode == AppViewMode.grid3x3 ? 3 : 2;
        final spacing = _currentViewMode == AppViewMode.grid3x3
            ? r.p(8)
            : r.p(12);
        final aspect = _currentViewMode == AppViewMode.grid3x3 ? 1.05 : 1.15;
        content = GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: folders.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: aspect,
          ),
          itemBuilder: (context, index) {
            final folder = folders[index];
            return Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(r.p(12)),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(r.p(12)),
                onTap: () => _navigateToSubfolder(folder),
                child: Stack(
                  children: [
                    Padding(
                      padding: EdgeInsets.all(r.p(10)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: r.p(40),
                            height: r.p(40),
                            decoration: BoxDecoration(
                              color: Colors.amber.withAlpha(22),
                              borderRadius: BorderRadius.circular(r.p(10)),
                            ),
                            child: const Icon(
                              Icons.folder_rounded,
                              color: Colors.amber,
                            ),
                          ),
                          SizedBox(height: r.p(8)),
                          Text(
                            folder.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: r.sp(13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: PopupMenuButton<String>(
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'download',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.download_rounded,
                                  color: Colors.green,
                                ),
                                SizedBox(width: 8),
                                Text('Download'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'download_zip',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.archive_rounded,
                                  color: Colors.green,
                                ),
                                SizedBox(width: 8),
                                Text('ZIP'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'share',
                            child: Row(
                              children: [
                                Icon(Icons.share, color: Colors.blue),
                                SizedBox(width: 8),
                                Text('Share'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Delete'),
                              ],
                            ),
                          ),
                        ],
                        onSelected: (v) {
                          if (v == 'download') {
                            _downloadFolderFiles(folder);
                          } else if (v == 'download_zip') {
                            _downloadFolderZip(folder);
                          } else if (v == 'share') {
                            _showFolderShareSheet(folder);
                          } else if (v == 'delete') {
                            _confirmDeleteFolder(folder);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Subfolders',
          style: TextStyle(fontSize: r.sp(16), fontWeight: FontWeight.bold),
        ),
        SizedBox(height: r.p(8)),
        content,
        SizedBox(height: r.p(16)),
      ],
    );
  }

  // File icon helpers (used by compact/grid views)
  IconData _getFileIcon(String type) {
    switch (type.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      case 'txt':
        return Icons.text_snippet;
      case 'image':
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image;
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
      case 'doc':
      case 'docx':
        return Colors.blue;
      case 'xls':
      case 'xlsx':
        return Colors.green;
      case 'ppt':
      case 'pptx':
        return Colors.orange;
      case 'txt':
        return Colors.grey;
      case 'image':
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Colors.purple;
      case 'csv':
        return Colors.green.shade700;
      default:
        return Colors.indigo;
    }
  }

  void _handleDocumentDoubleTap(Document document) {
    DocumentOpenerService().openViewer(context: context, document: document);
  }

  Widget _buildDocumentsSection(List<Document> documents) {
    if (documents.isEmpty) {
      return const Center(child: Text('No documents found'));
    }

    final r = context.r;

    Widget content;
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
            for (final doc in documents)
              ListTile(
                dense: true,
                visualDensity: const VisualDensity(vertical: -2),
                leading: Icon(
                  _getFileIcon(doc.type),
                  color: _getFileColor(doc.type),
                ),
                title: Text(
                  doc.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  doc.type.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => _handleDocumentDoubleTap(doc),
              ),
          ],
        );
        break;
      case AppViewMode.grid2x2:
      case AppViewMode.grid3x3:
        final crossAxisCount = _currentViewMode == AppViewMode.grid3x3 ? 3 : 2;
        final spacing = _currentViewMode == AppViewMode.grid3x3
            ? r.p(8)
            : r.p(12);
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
            final iconData = _getFileIcon(doc.type);
            final color = _getFileColor(doc.type);
            return Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(r.p(12)),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(r.p(12)),
                onTap: () => _handleDocumentDoubleTap(doc),
                child: Padding(
                  padding: EdgeInsets.all(r.p(10)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: r.p(40),
                        height: r.p(40),
                        decoration: BoxDecoration(
                          color: color.withAlpha(18),
                          borderRadius: BorderRadius.circular(r.p(10)),
                        ),
                        child: Icon(iconData, color: color),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Documents',
          style: TextStyle(fontSize: r.sp(16), fontWeight: FontWeight.bold),
        ),
        SizedBox(height: r.p(8)),
        content,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;

    if (_isLoading) {
      return DismissKeyboard(
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: _goBack,
            ),
            title: Text(
              widget.folderName,
              style: TextStyle(fontSize: r.sp(19)),
            ),
            backgroundColor: const Color.fromARGB(255, 43, 65, 189),
            actions: [
              _buildLayoutSelector(),
              SizedBox(width: r.p(8)),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: _loadFolderContents,
              ),
            ],
          ),
          body: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return DismissKeyboard(
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: _goBack,
            ),
            title: Text(
              widget.folderName,
              style: TextStyle(fontSize: r.sp(19)),
            ),
            backgroundColor: const Color.fromARGB(255, 43, 65, 189),
            actions: [
              _buildLayoutSelector(),
              SizedBox(width: r.p(8)),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: _loadFolderContents,
              ),
            ],
          ),
          body: Center(child: Text(_errorMessage)),
        ),
      );
    }

    final filteredDocuments = _getFilteredDocuments();

    return DismissKeyboard(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: _goBack,
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.folderName,
                style: TextStyle(
                  fontSize: r.sp(18),
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              if (widget.parentFolderName != null)
                Text(
                  'In: ${widget.parentFolderName}',
                  style: TextStyle(fontSize: r.sp(12), color: Colors.white70),
                ),
            ],
          ),
          backgroundColor: const Color.fromARGB(255, 43, 65, 189),
          elevation: 0,
          actions: [
            _buildLayoutSelector(),
            SizedBox(width: r.p(8)),
            IconButton(
              icon: const Icon(
                Icons.notifications_active_outlined,
                color: Colors.white,
              ),
              tooltip: 'Folder alerts',
              onPressed: () => FolderAlertSheet.show(
                context: context,
                folderId: widget.folderId,
                folderName: widget.folderName,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _loadFolderContents,
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: EdgeInsets.all(r.p(12)),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'Search in folder...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.all(r.p(12)),
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: r.isDesktop ? 800 : double.infinity,
                    ),
                    child: _buildSubfoldersSection(subfolders),
                  ),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: r.isDesktop ? 800 : double.infinity,
                    ),
                    child: _buildDocumentsSection(filteredDocuments),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Original Document Card with Collapse/Expand (same as HomePage)
  Widget _buildDocumentCard(Document document, int index) {
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

    // Get document opener service instance
    final documentOpener = DocumentOpenerService();

    // Check if this specific document is expanded using its ID
    bool isExpanded = _expandedStates[document.id] ?? false;

    return InkWell(
      onTap: () =>
          documentOpener.openViewer(context: context, document: document),
      borderRadius: BorderRadius.circular(r.p(12)),
      child: Card(
        margin: EdgeInsets.only(bottom: r.p(16)),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(r.p(12)),
        ),
        child: Padding(
          padding: EdgeInsets.all(r.p(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row with icon, document info, and expand/collapse button
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.all(r.p(12)),
                    decoration: BoxDecoration(
                      color: color.withAlpha(10),
                      borderRadius: BorderRadius.circular(r.p(8)),
                    ),
                    child: Icon(icon, color: color, size: r.sp(32)),
                  ),
                  SizedBox(width: r.p(16)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                document.name,
                                style: TextStyle(
                                  fontSize: r.sp(16),
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: isExpanded ? 2 : 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // EXPAND/COLLAPSE BUTTON (same as HomePage)
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  // Toggle only this specific document using its ID
                                  _expandedStates[document.id] = !isExpanded;
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
                            SizedBox(width: r.p(8)),
                            // Vertical More Options Button (Three Dots)
                            IconButton(
                              onPressed: () => _toggleFavorite(document),
                              icon: Icon(
                                _isFavorite(document.id)
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: _isFavorite(document.id)
                                    ? Colors.red
                                    : Colors.white,
                              ),
                              tooltip: 'Favorite',
                            ),
                            IconButton(
                              onPressed: () =>
                                  _showDocumentActions(document, index),
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
                        SizedBox(height: r.p(4)),
                        Text(
                          'Type: ${document.type} • $formattedDate',
                          style: TextStyle(
                            fontSize: r.sp(11),
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
                      SizedBox(height: r.p(12)),
                      const Divider(height: 1),
                      SizedBox(height: r.p(8)),

                      Wrap(
                        spacing: r.p(12),
                        runSpacing: r.p(8),
                        children: [
                          _buildDetailRow(
                            'Keyword',
                            document.keyword,
                            Icons.label,
                          ),
                          _buildDetailRow(
                            'Owner',
                            document.owner,
                            Icons.person,
                          ),
                          _buildDetailRow(
                            'Folder',
                            document.folder,
                            Icons.folder,
                          ),
                          _buildDetailRow(
                            'Classification',
                            document.classification,
                            Icons.security,
                          ),
                          _buildDetailRow(
                            'Sharing',
                            document.sharingType,
                            Icons.share,
                          ),
                          if (document.details.isNotEmpty)
                            _buildDetailRow(
                              'Details',
                              document.details,
                              Icons.info_outline,
                            ),
                        ],
                      ),
                      SizedBox(height: r.p(16)),

                      // ACTION BUTTONS ROW
                      Row(
                      //   spacing: r.p(8),
                      //   runSpacing: r.p(8),
                      //   alignment: WrapAlignment.spaceEvenly,
                        children: [
                          // VIEW BUTTON
                          SizedBox(
                            width: r.wp(0.25),
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  DocumentOpenerService().openViewer(
                                    context: context,
                                    document: document,
                                  ),
                              icon: Icon(Icons.visibility, size: r.sp(16)),
                              label: Text(
                                'View',
                                style: TextStyle(fontSize: r.sp(12)),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.purple,
                                side: const BorderSide(color: Colors.purple),
                                padding: EdgeInsets.symmetric(vertical: r.p(8)),
                              ),
                            ),
                          ),
                          SizedBox(width: r.p(8)),
                          // SHARE BUTTON (UPDATED - now opens user list dialog)
                          SizedBox(
                            width: r.wp(0.28),
                            child: OutlinedButton.icon(
                              onPressed: () => _showShareDialog(document),
                              icon: Icon(Icons.share, size: r.sp(16)),
                              label: Text(
                                'Share',
                                style: TextStyle(fontSize: r.sp(12)),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.blue,
                                side: const BorderSide(color: Colors.blue),
                                padding: EdgeInsets.symmetric(vertical: r.p(8)),
                              ),
                            ),
                          ),
                          SizedBox(width: r.p(8)),

                          // DOWNLOAD BUTTON
                          SizedBox(
                            width: r.wp(0.28),
                            child: OutlinedButton.icon(
                              onPressed: () => _downloadDocument(document),
                              icon: Icon(Icons.download, size: r.sp(16)),
                              label: Text(
                                document.allowDownload
                                    ? 'Download'
                                    : 'Request Download',
                                style: TextStyle(fontSize: r.sp(12)),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.green,
                                side: const BorderSide(color: Colors.green),
                                padding: EdgeInsets.symmetric(vertical: r.p(8)),
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

  // Helper method for document icons
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

  // Helper method for document colors
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

  // Helper method for detail rows
  Widget _buildDetailRow(String label, String value, IconData icon) {
    final r = context.r;
    return Padding(
      padding: EdgeInsets.only(bottom: r.p(8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: r.sp(16), color: Colors.indigo),
          SizedBox(width: r.p(8)),
          Flexible(
            child: Text(
              '$label:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: r.sp(13)),
            ),
          ),
          SizedBox(width: r.p(8)),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: r.sp(13), color: Colors.grey.shade700),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to format dates to DD MM YYYY
  String _formatToDDMMYYYY(String dateString) {
    try {
      DateTime date = DateTime.parse(dateString);
      String day = date.day.toString().padLeft(2, '0');
      String month = date.month.toString().padLeft(2, '0');
      String year = date.year.toString();
      return '$day $month $year';
    } catch (e) {
      return dateString;
    }
  }

  Widget _buildEmptyState() {
    final r = context.r;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(r.p(32)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_open,
              size: r.sp(80),
              color: Colors.grey.shade400,
            ),
            SizedBox(height: r.p(20)),
            Text(
              'No Documents in This Folder',
              style: TextStyle(
                fontSize: r.sp(20),
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: r.p(10)),
            Text(
              'Upload documents or check subfolders',
              style: TextStyle(fontSize: r.sp(14), color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  List<Document> _getFilteredDocuments() {
    List<Document> allDocs = List.from(documents);

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
          doc.owner.toLowerCase().contains(searchTerm);
    }).toList();
  }
}
