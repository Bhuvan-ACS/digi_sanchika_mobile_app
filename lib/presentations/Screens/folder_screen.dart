import 'package:digi_sanchika/utils/app_fonts.dart';
import 'package:digi_sanchika/controllers/multi_select_controller.dart';
import 'package:digi_sanchika/widgets/file_type_icon.dart';
import 'package:digi_sanchika/widgets/folder_illustration.dart';
import 'package:digi_sanchika/widgets/responsive_document_gallery.dart';
import 'package:digi_sanchika/utils/app_theme.dart';
import 'package:digi_sanchika/theme/ui_theme.dart';
import 'package:digi_sanchika/widgets/section_panel.dart';
import 'package:flutter/material.dart';
import 'package:digi_sanchika/utils/responsive_helper.dart';
import 'package:digi_sanchika/services/folder_service.dart';
import 'package:digi_sanchika/services/api_service.dart';
import 'package:digi_sanchika/models/folder.dart';
import 'package:digi_sanchika/models/document.dart';
import 'package:digi_sanchika/presentations/Screens/home_page.dart';
import 'package:digi_sanchika/services/document_opener_service.dart';
import 'package:digi_sanchika/services/favorites_store.dart';
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
import 'package:digi_sanchika/widgets/ai_sparkle_button.dart';
import 'package:digi_sanchika/widgets/home_components.dart';

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

class _DocumentActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _DocumentActionItem(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 22, color: color),
      const SizedBox(width: 14),
      Expanded(
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    ],
  );
}

/// One level of the folder hierarchy shown in the breadcrumb.
class FolderCrumb {
  final String id;
  final String name;
  const FolderCrumb(this.id, this.name);
}

class FolderScreen extends StatefulWidget {
  final String folderId;
  final String folderName;
  final String? parentFolderId;
  final String? parentFolderName;
  final String? userName;

  /// Folders above this one (root first), used to build the breadcrumb.
  final List<FolderCrumb> ancestors;

  const FolderScreen({
    super.key,
    required this.folderId,
    required this.folderName,
    this.parentFolderId,
    this.parentFolderName,
    this.userName,
    this.ancestors = const [],
  });

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  List<Document> documents = [];
  List<Folder> subfolders = [];
  bool _isLoading = true;
  bool isDownloading = false;
  String _errorMessage = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final bool _showRecent = false;

  // Add these variables for layout modes (same as HomePage)
  AppViewMode _currentViewMode = AppViewMode.list;

  // Document-type filter: 'all' | 'pdf' | 'doc' | 'xls' | 'ppt' | 'image'
  String _typeFilter = 'all';
  final Map<String, bool> _expandedStates = {};

  final FavoritesStore _favorites = FavoritesStore.instance;

  // Users for sharing
  List<ShareUser> _shareUsers = [];

  // ── Multi-select ───────────────────────────────────────────────────────────
  final MultiSelectController _selection = MultiSelectController();
  Set<String> get _selectedIds => _selection.documentIds;
  Set<String> get _selectedFolderIds => _selection.folderIds;
  bool get _selecting => _selection.isSelecting;
  int get _selectedCount => _selection.count;

  void _toggleFolderSelected(Folder folder) {
    setState(() => _selection.toggleFolder(folder.id));
  }

  List<Folder> get _selectedFolders => subfolders
      .where((folder) => _selectedFolderIds.contains(folder.id))
      .toList();

  void _toggleSelected(Document doc) {
    setState(() => _selection.toggleDocument(doc.id));
  }

  void _clearSelection() => setState(_selection.clear);

  List<Document> get _selectedDocs =>
      documents.where((d) => _selectedIds.contains(d.id)).toList();

  Future<void> _shareSelected() async {
    final docs = _selectedDocs;
    final selectedFolders = _selectedFolders;
    if (docs.length + selectedFolders.length != 1) {
      _showTopMessage('Select a single item to share');
      return;
    }
    if (selectedFolders.isNotEmpty) {
      await _showFolderShareSheet(selectedFolders.first);
    } else {
      await _showShareDialog(docs.first);
    }
  }

  Future<void> _downloadSelected() async {
    final docs = _selectedDocs;
    _clearSelection();
    for (final d in docs) {
      await _downloadDocument(d);
    }
  }

  Future<void> _favouriteSelected() async {
    final docs = _selectedDocs;
    final allFav = docs.every((d) => _isFavorite(d.id));
    _clearSelection();
    for (final d in docs) {
      if (_isFavorite(d.id) == allFav) await _toggleFavorite(d);
    }
  }

  Future<void> _deleteSelected() async {
    final docs = _selectedDocs;
    final selectedFolders = _selectedFolders;
    if (docs.isEmpty && selectedFolders.isEmpty) return;
    if (docs.length + selectedFolders.length == 1) {
      _clearSelection();
      if (docs.isNotEmpty) {
        final idx = documents.indexWhere((d) => d.id == docs.first.id);
        _showDeleteOptions(context, idx, docs.first);
      } else {
        await _deleteFolder(selectedFolders.first);
      }
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete'),
        content: Text(
          'Move ${docs.length + selectedFolders.length} selected item(s) to the Recycle Bin?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text(
              'Move to Recycle Bin',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    _clearSelection();
    for (final folder in selectedFolders) {
      await _deleteFolder(folder);
    }
    for (final d in docs) {
      final idx = documents.indexWhere((x) => x.id == d.id);
      if (idx >= 0) await _deleteDocument(idx);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadFolderContents();
    _loadShareUsers();
    _favorites.addListener(_onFavoritesChanged);
    _loadFavorites();
  }

  @override
  void dispose() {
    _favorites.removeListener(_onFavoritesChanged);
    _searchFocusNode.dispose();
    _selection.dispose();
    super.dispose();
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

  Future<void> _showCreateFolderDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create New Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Enter folder name...',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || name == null || name.isEmpty) return;

    try {
      final result = await MyDocumentsService.createFolder(
        folderName: name,
        parentFolderId: widget.folderId,
      );
      if (!mounted) return;
      if (result['success'] == true) {
        await _loadFolderContents();
        _showTopMessage('Folder created');
      } else {
        _showTopMessage(
          result['error']?.toString() ?? 'Unable to create folder',
        );
      }
    } catch (error) {
      if (mounted) _showTopMessage('Unable to create folder: $error');
    }
  }

  Future<void> _loadShareUsers() async {
    try {
      final users = await FolderService.getUsersForSharing();
      if (users.isNotEmpty) {
        setState(() {
          _shareUsers = users
              .map(
                (user) => ShareUser(
                  id: user.id.isNotEmpty == true ? user.id : 'unknown',
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
      await _favorites.load();
    } catch (_) {}
  }

  /// Redraws stars when any page changes a favourite.
  void _onFavoritesChanged() {
    if (mounted) setState(() {});
  }

  bool _isFavorite(String documentId) => _favorites.isFavorite(documentId);

  Future<void> _toggleFavorite(Document document) async {
    final wasFavorite = _isFavorite(document.id);
    final ok = await _favorites.toggleDocument(document.id);
    if (!mounted) return;
    if (ok) {
      if (!wasFavorite) _showTopMessage('File added to favorites');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasFavorite ? 'Failed to remove favorite' : 'Failed to add favorite',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _showTopMessage(String message) {
    if (!mounted) return;
    final overlay = Overlay.of(context);

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
          ancestors: [
            ...widget.ancestors,
            FolderCrumb(widget.folderId, widget.folderName),
          ],
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
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
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
    final dialogContext = context;
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('"${document.name}" permanently deleted'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                } else {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        (direct['error'] ??
                                direct['message'] ??
                                'Permanent delete failed')
                            .toString(),
                      ),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: AppColors.error,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
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
            backgroundColor: AppColors.warning,
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
            backgroundColor: AppColors.error,
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
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() {
      isDownloading = true;
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
                ? AppColors.warning
                : AppColors.error,
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
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isDownloading = false;
        });
      }
    }
  }

  Future<void> _downloadFolderZip(Folder folder) async {
    if (!ApiService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot download while offline'),
          backgroundColor: AppColors.warning,
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
                ? AppColors.warning
                : AppColors.error,
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
          backgroundColor: AppColors.error,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _downloadFolderFiles(Folder folder) async {
    if (!ApiService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot download while offline'),
          backgroundColor: AppColors.warning,
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
                ? AppColors.warning
                : AppColors.error,
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
          backgroundColor: AppColors.error,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _showDocumentActions(
    Document document,
    int index, [
    BuildContext? anchorContext,
  ]) async {
    final isFav = _isFavorite(document.id);

    final anchor = (anchorContext ?? context).findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (anchor == null || overlay == null || !anchor.attached) return;

    final anchorRect = Rect.fromPoints(
      anchor.localToGlobal(Offset.zero, ancestor: overlay),
      anchor.localToGlobal(
        anchor.size.bottomRight(Offset.zero),
        ancestor: overlay,
      ),
    );
    final viewport = overlay.size;
    const menuWidth = 260.0;
    // PopupMenuItem uses a 48dp minimum height. This estimate is only used
    // to choose whether the menu opens above or below the anchor; Flutter
    // still performs the final viewport adjustment for the actual menu.
    const menuHeight = 7 * 48.0 + 16.0;
    const gap = 8.0;
    const edge = 8.0;

    final opensRight =
        anchorRect.right + gap + menuWidth <= viewport.width - edge;
    final left = opensRight
        ? anchorRect.right + gap
        : (anchorRect.left - gap - menuWidth)
              .clamp(edge, viewport.width - menuWidth - edge)
              .toDouble();
    final top = (anchorRect.bottom + menuHeight <= viewport.height - edge)
        ? anchorRect.top
        : (anchorRect.top - menuHeight >= edge
              ? anchorRect.top - menuHeight
              : (viewport.height - menuHeight - edge)
                    .clamp(edge, viewport.height)
                    .toDouble());

    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        left,
        top,
        viewport.width - left - menuWidth,
        viewport.height - top - menuHeight,
      ),
      constraints: const BoxConstraints.tightFor(width: menuWidth),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 8,
      items: [
        const PopupMenuItem(
          value: 'view',
          child: _DocumentActionItem(Icons.visibility, 'View', Colors.purple),
        ),
        const PopupMenuItem(
          value: 'tools',
          child: _DocumentActionItem(
            Icons.build,
            'Tools',
            AppColors.textSecondary,
          ),
        ),
        const PopupMenuItem(
          value: 'share',
          child: _DocumentActionItem(Icons.share, 'Share', AppColors.info),
        ),
        PopupMenuItem(
          value: 'download',
          child: _DocumentActionItem(
            Icons.download,
            document.allowDownload ? 'Download' : 'Request Download',
            AppColors.success,
          ),
        ),
        PopupMenuItem(
          value: 'favorite',
          child: _DocumentActionItem(
            isFav ? Icons.star : Icons.star_border,
            isFav ? 'Remove from Favorites' : 'Add to Favorites',
            Colors.amber,
          ),
        ),
        PopupMenuItem(
          value: 'publish',
          child: _DocumentActionItem(
            document.isPublishedToLibrary ? Icons.unpublished : Icons.publish,
            document.isPublishedToLibrary
                ? 'Unpublish from Library'
                : 'Publish to Library',
            document.isPublishedToLibrary ? Colors.orange : AppColors.primary,
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: _DocumentActionItem(Icons.delete, 'Delete', AppColors.error),
        ),
      ],
    );

    if (!mounted || action == null) return;
    switch (action) {
      case 'view':
        DocumentOpenerService().openPreviewDialog(
          context: context,
          document: document,
        );
      case 'tools':
        _openDocumentTools(document);
      case 'share':
        _showShareDialog(document);
      case 'download':
        _downloadDocument(document);
      case 'favorite':
        _toggleFavorite(document);
      case 'publish':
        final wasPublished = document.isPublishedToLibrary;
        final result = wasPublished
            ? await DocumentLibraryService().unpublishDocument(document.id)
            : await DocumentLibraryService().publishDocument(document.id);
        if (!mounted) return;
        if (result['success'] == true) {
          setState(() => document.isPublishedToLibrary = !wasPublished);
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
                ? AppColors.success
                : AppColors.error,
          ),
        );
      case 'delete':
        _showDeleteOptions(context, index, document);
    }
  }

  Future<void> _showFolderShareSheet(Folder folder) async {
    if (!ApiService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot share while offline'),
          backgroundColor: AppColors.warning,
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
    final result = await DocumentLibraryService().publishFolder(folder.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          (result['message'] ??
                  (result['success'] == true
                      ? 'Folder published to library'
                      : 'Folder publish failed'))
              .toString(),
        ),
        backgroundColor: result['success'] == true ? Colors.green : Colors.red,
      ),
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
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
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
            backgroundColor: AppColors.warning,
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
            backgroundColor: AppColors.error,
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
          backgroundColor: AppColors.error,
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
      AppColors.primary,
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
          backgroundColor: AppColors.warning,
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
                      color: AppColors.primary,
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
                    style: const TextStyle(fontSize: 14, color: AppColors.info),
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
                          color: AppColors.success,
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
                        style: TextStyle(color: AppColors.error, fontSize: 12),
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
                              color: AppColors.info,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$selectedCount selected',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.info,
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
                              // backgroundcolor: AppColors.info,
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
                                backgroundColor: AppColors.success,
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
                                backgroundColor: AppColors.error,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.info,
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
              color: user.isSelected ? Colors.blue : AppColors.borderLight,
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
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                if (user.department != null)
                  Text(user.department!, style: TextStyle(fontSize: 11)),
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
  // ── Search card, type filter and layout toggle ────────────────────────────
  bool get _isFiltering =>
      _typeFilter != 'all' || _searchController.text.trim().isNotEmpty;

  void _resetFilters() {
    setState(() {
      _typeFilter = 'all';
      _searchController.clear();
    });
  }

  Widget _buildEmptyDocuments() {
    final r = context.r;
    if (!_isFiltering) {
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: r.p(24)),
          child: Text(
            subfolders.isEmpty ? 'This folder is empty' : 'No documents found',
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.symmetric(vertical: r.p(24)),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: r.sp(40), color: Colors.grey),
          SizedBox(height: r.p(8)),
          Text(
            _typeFilter != 'all'
                ? 'No ${_typeFilterLabels[_typeFilter]} files match your search'
                : 'No files match your search',
            textAlign: TextAlign.center,
          ),
          TextButton(
            onPressed: _resetFilters,
            child: const Text('Clear search & filter'),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchRow() {
    final r = context.r;
    return Padding(
      padding: EdgeInsets.fromLTRB(r.p(12), r.p(4), r.p(12), 0),
      child: Row(
        children: [
          Expanded(
            child: PillSearchField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              hint: 'Search in folder...',
              loading: _aiSearching,
              onChanged: (_) => setState(() => _aiResultIds = null),
              onSubmitted: (_) => setState(() => _aiResultIds = null),
              onClear: () => setState(() {
                _searchController.clear();
                _aiResultIds = null;
              }),
              trailing: AiSparkleButton(size: 36, onTap: _handleAiSearch),
            ),
          ),
          const SizedBox(width: 8),
          _buildViewToggle(),
        ],
      ),
    );
  }

  Widget _buildFilterButton() {
    final active = _typeFilter != 'all';
    PopupMenuItem<String> item(String value, String label, IconData icon) {
      final selected = _typeFilter == value;
      return PopupMenuItem<String>(
        value: value,
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.primary : null,
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check, size: 18, color: AppColors.primary),
          ],
        ),
      );
    }

    return PopupMenuButton<String>(
      tooltip: 'Filter by type',
      padding: EdgeInsets.zero,
      offset: const Offset(0, 42),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (v) => setState(() => _typeFilter = v),
      itemBuilder: (_) => [
        item(
          'all',
          active ? 'Reset filter (show all)' : 'All files',
          active ? Icons.filter_alt_off_outlined : Icons.apps_rounded,
        ),
        const PopupMenuDivider(height: 1),
        item('pdf', 'PDF', Icons.picture_as_pdf_outlined),
        item('doc', 'DOC / DOCX', Icons.description_outlined),
        item('xls', 'XLS / XLSX', Icons.table_chart_outlined),
        item('ppt', 'PPT / PPTX', Icons.slideshow_outlined),
        item('image', 'Images', Icons.image_outlined),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary.withAlpha(22)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? AppColors.primary.withAlpha(70)
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_list_rounded,
              size: 17,
              color: active ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              active ? (_typeFilterLabels[_typeFilter] ?? 'Filter') : 'Filter',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: active ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: active ? AppColors.primary : AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  /// Document ids from the last AI search, in relevance order; null when the
  /// list is filtered by plain text instead.
  List<String>? _aiResultIds;
  bool _aiSearching = false;

  /// AI assistant search (POST /search/semantic), narrowed to this folder's
  /// documents. Falls back to the name filter if the request fails.
  Future<void> _handleAiSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      _showTopMessage('Enter a search query first.');
      FocusScope.of(context).requestFocus(_searchFocusNode);
      return;
    }
    _searchFocusNode.unfocus();
    setState(() => _aiSearching = true);
    final result = await MyDocumentsService.semanticSearch(
      query: query,
      scope: 'all',
      limit: 50,
    );
    if (!mounted) return;
    final results = result['results'];
    setState(() {
      _aiSearching = false;
      _aiResultIds = result['success'] == true && results is List
          ? results.map((r) => r['documentId'].toString()).toList()
          : null;
    });
    if (result['success'] != true) {
      _showTopMessage(
        '${result['error'] ?? 'AI search failed'}. Showing name matches.',
      );
    }
  }

  Widget _buildViewToggle() {
    Widget seg(AppViewMode mode, IconData icon, String tip) {
      final active = _currentViewMode == mode;
      return Tooltip(
        message: tip,
        child: GestureDetector(
          onTap: () => setState(() => _currentViewMode = mode),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: active ? const Color(0xFF4F9BFF) : Colors.transparent,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              icon,
              size: 20,
              color: active ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDE3F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg(AppViewMode.list, Icons.view_list_rounded, 'List'),
          seg(AppViewMode.grid2x2, Icons.grid_view_rounded, '2 columns'),
          seg(AppViewMode.grid3x3, Icons.apps_rounded, '3 columns'),
        ],
      ),
    );
  }

  Widget _buildCountRow(int count) {
    final r = context.r;
    return Padding(
      padding: EdgeInsets.fromLTRB(r.p(16), r.p(8), r.p(12), 0),
      child: Row(
        children: [
          Text(
            '$count ${count == 1 ? 'item' : 'items'}',
            style: TextStyle(
              fontSize: r.sp(13),
              color: AppColors.textSecondary,
            ),
          ),
          if (_typeFilter != 'all') ...[
            const SizedBox(width: 8),
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => setState(() => _typeFilter = 'all'),
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 3, 6, 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _typeFilterLabels[_typeFilter] ?? '',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ),
          ],
          const Spacer(),
          _buildFilterButton(),
        ],
      ),
    );
  }

  String _folderMetadata(Folder folder) {
    final age = DateTime.now().difference(folder.createdAt);
    final days = age.inDays;
    final label = days <= 0
        ? 'today'
        : days == 1
        ? '1d ago'
        : '${days}d ago';
    return '${folder.documents.length} files • 0 KB • $label';
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
                  color: _selectedFolderIds.contains(folder.id)
                      ? const Color(0xFFE3F1FF)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(r.p(16)),
                  elevation: 1,
                  child: InkWell(
                    onTap: () => _navigateToSubfolder(folder),
                    onLongPress: () => _toggleFolderSelected(folder),
                    borderRadius: BorderRadius.circular(r.p(16)),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: r.p(16),
                        vertical: r.p(14),
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(r.p(16)),
                        border: Border.all(
                          color: AppColors.borderLight,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: r.p(52),
                            height: r.p(52),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F3FF),
                              borderRadius: BorderRadius.circular(r.p(12)),
                            ),
                            child: FolderIllustration(size: r.p(36)),
                          ),
                          SizedBox(width: r.p(16)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  folder.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: r.sp(16),
                                    color: const Color(0xFF1E293B),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                SizedBox(height: r.p(4)),
                                Text(
                                  _folderMetadata(folder),
                                  style: TextStyle(
                                    fontSize: r.sp(12),
                                    fontWeight: FontWeight.w400,
                                    color: const Color(0xFF64748B),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          if (_selectedFolderIds.contains(folder.id))
                            _selectionCheckbox(true),
                          PopupMenuButton<String>(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 48,
                              minHeight: 48,
                            ),
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'download',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.download_rounded,
                                      color: AppColors.success,
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
                                      color: AppColors.success,
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
                                    Icon(Icons.share, color: AppColors.info),
                                    SizedBox(width: 8),
                                    Text('Share'),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'publish',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.library_add,
                                      color: AppColors.primary,
                                    ),
                                    SizedBox(width: 8),
                                    Text('Publish to Library'),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete, color: AppColors.error),
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
                              } else if (v == 'publish') {
                                _publishFolder(folder);
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
                selected: _selectedFolderIds.contains(folder.id),
                selectedTileColor: const Color(0xFFE3F1FF),
                visualDensity: const VisualDensity(vertical: -2),
                leading: Container(
                  width: r.p(36),
                  height: r.p(36),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F3FF),
                    borderRadius: BorderRadius.circular(r.p(10)),
                  ),
                  child: FolderIllustration(size: r.p(26)),
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
                          Icon(
                            Icons.download_rounded,
                            color: AppColors.success,
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
                          Icon(Icons.archive_rounded, color: AppColors.success),
                          SizedBox(width: 8),
                          Text('ZIP'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'share',
                      child: Row(
                        children: [
                          Icon(Icons.share, color: AppColors.info),
                          SizedBox(width: 8),
                          Text('Share'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'publish',
                      child: Row(
                        children: [
                          Icon(Icons.library_add, color: AppColors.primary),
                          SizedBox(width: 8),
                          Text('Publish to Library'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, color: AppColors.error),
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
                    } else if (v == 'publish') {
                      _publishFolder(folder);
                    } else if (v == 'delete') {
                      _confirmDeleteFolder(folder);
                    }
                  },
                ),
                onTap: () => _navigateToSubfolder(folder),
                onLongPress: () => _toggleFolderSelected(folder),
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
        final dense = _currentViewMode == AppViewMode.grid3x3;
        final tileHeight = dense ? 112.0 : 150.0;
        content = GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: folders.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            mainAxisExtent: tileHeight,
          ),
          itemBuilder: (context, index) {
            final folder = folders[index];
            final picked = _selectedFolderIds.contains(folder.id);
            return Card(
              elevation: 1,
              clipBehavior: Clip.antiAlias,
              color: picked ? const Color(0xFFE3F1FF) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(dense ? r.p(16) : r.p(22)),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(dense ? r.p(16) : r.p(22)),
                onTap: () => _navigateToSubfolder(folder),
                onLongPress: () => _toggleFolderSelected(folder),
                child: Stack(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        dense ? r.p(10) : r.p(14),
                        dense ? r.p(10) : r.p(14),
                        dense ? r.p(10) : r.p(14),
                        dense ? r.p(8) : r.p(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Container(
                            width: dense ? 32 : 46,
                            height: dense ? 32 : 46,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F3FF),
                              borderRadius: BorderRadius.circular(r.p(12)),
                            ),
                            child: FolderIllustration(
                              size: dense ? r.p(25) : r.p(34),
                            ),
                          ),
                          SizedBox(height: dense ? 4 : 6),
                          Text(
                            folder.name,
                            maxLines: dense ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: _currentViewMode == AppViewMode.grid3x3
                                  ? r.sp(11.5)
                                  : r.sp(14.5),
                            ),
                          ),
                          SizedBox(height: dense ? 3 : 5),
                          Text(
                            '${folder.documents.length} files',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: dense ? r.sp(9.5) : r.sp(12),
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _folderMetadata(folder),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: dense ? r.sp(9) : r.sp(11),
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: dense ? 4 : 8,
                      right: dense ? 4 : 8,
                      child: PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        iconSize: _currentViewMode == AppViewMode.grid3x3
                            ? 16
                            : 20,
                        constraints: const BoxConstraints(),
                        style: _currentViewMode == AppViewMode.grid3x3
                            ? const ButtonStyle(
                                minimumSize: WidgetStatePropertyAll(
                                  Size(24, 24),
                                ),
                                padding: WidgetStatePropertyAll(
                                  EdgeInsets.zero,
                                ),
                              )
                            : null,
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'download',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.download_rounded,
                                  color: AppColors.success,
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
                                  color: AppColors.success,
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
                                Icon(Icons.share, color: AppColors.info),
                                SizedBox(width: 8),
                                Text('Share'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'publish',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.library_add,
                                  color: AppColors.primary,
                                ),
                                SizedBox(width: 8),
                                Text('Publish to Library'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, color: AppColors.error),
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
                          } else if (v == 'publish') {
                            _publishFolder(folder);
                          } else if (v == 'delete') {
                            _confirmDeleteFolder(folder);
                          }
                        },
                      ),
                    ),
                    if (picked)
                      Positioned(
                        right: r.p(8),
                        bottom: r.p(8),
                        child: _selectionCheckbox(true),
                      ),
                  ],
                ),
              ),
            );
          },
        );
        break;
    }

    // Same bordered panel as the Folders / Documents sections on My Files.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionPanel(
          margin: EdgeInsets.zero,
          header: _panelTitle('Subfolders'),
          child: content,
        ),
        SizedBox(height: r.p(16)),
      ],
    );
  }

  Widget _panelTitle(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: Color(0xFF0F172A),
    ),
  );

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
        return AppColors.filePdf;
      case 'doc':
      case 'docx':
        return AppColors.fileWord;
      case 'xls':
      case 'xlsx':
        return AppColors.fileExcel;
      case 'ppt':
      case 'pptx':
        return AppColors.filePpt;
      case 'txt':
        return AppColors.fileText;
      case 'image':
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Colors.purple;
      case 'csv':
        return AppColors.fileExcel;
      default:
        return AppColors.primary;
    }
  }

  void _handleDocumentDoubleTap(Document document) {
    DocumentOpenerService().openViewer(context: context, document: document);
  }

  Widget _buildDocumentsSection(List<Document> documents) {
    if (documents.isEmpty) {
      return _buildEmptyDocuments();
    }

    final galleryMode = switch (_currentViewMode) {
      AppViewMode.grid2x2 => ResponsiveDocumentViewMode.grid2,
      AppViewMode.grid3x3 => ResponsiveDocumentViewMode.grid3,
      _ => ResponsiveDocumentViewMode.list,
    };
    return SectionPanel(
      margin: EdgeInsets.zero,
      header: _panelTitle('Documents'),
      child: ResponsiveDocumentGallery(
        documents: documents,
        mode: galleryMode,
        shrinkWrap: true,
        onView: (document) => _selecting
            ? _toggleSelected(document)
            : _handleDocumentDoubleTap(document),
        onOverflow: (document, anchorContext, _) => _showDocumentActions(
          document,
          documents.indexOf(document),
          anchorContext,
        ),
        onVersions: (document) =>
            _showDocumentActions(document, documents.indexOf(document)),
        onDownload: _downloadDocument,
        onShare: _showShareDialog,
        canDownload: (document) => document.allowDownload,
      ),
    );

    /*
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
                selected: _selectedIds.contains(doc.id),
                selectedTileColor: const Color(0xFFE3F1FF),
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_selecting) ...[
                      _selectionCheckbox(_selectedIds.contains(doc.id)),
                      const SizedBox(width: 12),
                    ],
                    FileTypeIcon.orElse(
                      doc.type,
                      26,
                      Icon(
                        _getFileIcon(doc.type),
                        color: _getFileColor(doc.type),
                      ),
                    ),
                  ],
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
                onTap: () => _selecting
                    ? _toggleSelected(doc)
                    : _handleDocumentDoubleTap(doc),
                onLongPress: () => _toggleSelected(doc),
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
        final dense = _currentViewMode == AppViewMode.grid3x3;
        final tileHeight = dense ? 124.0 : 132.0;
        content = GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: documents.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            mainAxisExtent: tileHeight,
          ),
          itemBuilder: (context, index) {
            final doc = documents[index];
            final iconData = _getFileIcon(doc.type);
            final color = _getFileColor(doc.type);
            final picked = _selectedIds.contains(doc.id);
            return Card(
              elevation: picked ? 0 : 1,
              color: picked ? const Color(0xFFE3F1FF) : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(r.p(12)),
                side: picked
                    ? const BorderSide(color: AppColors.primary, width: 1.5)
                    : BorderSide.none,
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(r.p(12)),
                onTap: () => _selecting
                    ? _toggleSelected(doc)
                    : _handleDocumentDoubleTap(doc),
                onLongPress: () => _toggleSelected(doc),
                child: Padding(
                  padding: EdgeInsets.all(r.p(10)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            width: dense ? 36 : 44,
                            height: dense ? 36 : 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: color.withAlpha(18),
                              borderRadius: BorderRadius.circular(r.p(10)),
                            ),
                            child: FileTypeIcon.orElse(
                              doc.type,
                              dense ? 24 : 30,
                              Icon(iconData, color: color),
                            ),
                          ),
                          if (_selecting) _selectionCheckbox(picked),
                        ],
                      ),
                      SizedBox(height: dense ? 6 : 8),
                      Text(
                        doc.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: _currentViewMode == AppViewMode.grid3x3
                              ? r.sp(10.5)
                              : r.sp(13),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        doc.type.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: dense ? r.sp(10) : r.sp(11),
                          color: AppColors.textSecondary,
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
    */
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;

    if (_isLoading) {
      return DismissKeyboard(
        child: Scaffold(
          backgroundColor: const Color(0xFFF4F9FF),

          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black87),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
            title: Text(widget.folderName, style: w500_14Poppins()),
            backgroundColor: const Color(0xFFF4F9FF),
          ),
          body: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return DismissKeyboard(
        child: Scaffold(
          backgroundColor: const Color(0xFFF4F9FF),

          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black87),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
            title: Text(widget.folderName, style: w500_14Poppins()),
            backgroundColor: const Color(0xFFF4F9FF),
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.cloud_off_rounded,
                    size: 40,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 12),
                  Text(_errorMessage, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _loadFolderContents,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final filteredDocuments = _getFilteredDocuments();
    final filteredFolders = _getFilteredFolders();

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting) _clearSelection();
      },
      child: DismissKeyboard(
        child: Scaffold(
          backgroundColor: const Color(0xFFF4F9FF),
          appBar: _selecting ? _buildSelectionAppBar() : _buildNormalAppBar(r),
          floatingActionButton: _selecting
              ? null
              : FloatingActionButton(
                  onPressed: _showCreateFolderDialog,
                  backgroundColor: UiColors.primaryActive,
                  foregroundColor: Colors.white,
                  child: const Icon(Icons.add_rounded),
                ),
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
          body: Column(
            children: [
              _buildBreadcrumb(),
              _buildSearchRow(),
              _buildCountRow(filteredDocuments.length + filteredFolders.length),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadFolderContents,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      r.p(12),
                      r.p(4),
                      r.p(12),
                      r.p(88),
                    ),
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: r.isDesktop ? 800 : double.infinity,
                        ),
                        child: _buildSubfoldersSection(filteredFolders),
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  AppBar _buildNormalAppBar(ResponsiveHelper r) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.black87),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(widget.folderName, style: w500_14Poppins()),
      backgroundColor: const Color(0xFFF4F9FF),
      elevation: 0,
      actions: [
        IconButton(
          icon: const Icon(
            Icons.notifications_active_outlined,
            color: Colors.black87,
          ),
          tooltip: 'Folder alerts',
          onPressed: () => FolderAlertSheet.show(
            context: context,
            folderId: widget.folderId,
            folderName: widget.folderName,
          ),
        ),
      ],
    );
  }

  AppBar _buildSelectionAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFFF4F9FF),
      elevation: 0,
      centerTitle: true,
      leading: IconButton(
        icon: const Icon(Icons.close, color: Colors.black87),
        tooltip: 'Cancel selection',
        onPressed: _clearSelection,
      ),
      title: Text(
        '$_selectedCount selected',
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Share selected',
          icon: const Icon(Icons.share_outlined),
          onPressed: _shareSelected,
        ),
        IconButton(
          tooltip: 'Delete selected',
          icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
          onPressed: _deleteSelected,
        ),
      ],
    );
  }

  /// Connected directory-line breadcrumb: Home > My Documents > ... > current.
  Widget _buildBreadcrumb() {
    final r = context.r;
    final ancestors = widget.ancestors;

    void popLevels(int n) {
      var c = 0;
      Navigator.popUntil(context, (_) => c++ >= n);
    }

    void toRoot() => Navigator.popUntil(context, (route) => route.isFirst);

    Widget chevron() => Padding(
      padding: EdgeInsets.symmetric(horizontal: r.p(4)),
      child: Icon(
        Icons.chevron_right_rounded,
        size: r.sp(18),
        color: AppColors.textTertiary,
      ),
    );

    Widget crumb(String label, {VoidCallback? onTap, bool current = false}) {
      return InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: r.p(8), vertical: r.p(5)),
          decoration: BoxDecoration(
            color: current ? AppColors.primary.withAlpha(18) : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: r.sp(13),
              fontWeight: current ? FontWeight.w600 : FontWeight.w500,
              color: current ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(r.p(8), r.p(2), r.p(8), r.p(2)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: toRoot,
              child: Padding(
                padding: EdgeInsets.all(r.p(5)),
                child: Icon(
                  Icons.home_outlined,
                  size: r.sp(20),
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            chevron(),
            crumb('My Documents', onTap: toRoot),
            for (var i = 0; i < ancestors.length; i++) ...[
              chevron(),
              crumb(
                ancestors[i].name,
                onTap: () => popLevels(ancestors.length - i),
              ),
            ],
            chevron(),
            crumb(widget.folderName, current: true),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionBar() {
    final docs = _selectedDocs;
    final allFav = docs.isNotEmpty && docs.every((d) => _isFavorite(d.id));

    Widget item(
      IconData icon,
      String label,
      VoidCallback onTap, {
      Color color = Colors.black87,
    }) {
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(20),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            item(Icons.share_outlined, 'Share', _shareSelected),
            item(Icons.file_download_outlined, 'Download', _downloadSelected),
            item(
              Icons.delete_outline,
              'Delete',
              _deleteSelected,
              color: AppColors.error,
            ),
            item(
              allFav ? Icons.star : Icons.star_border,
              'Favourite',
              _favouriteSelected,
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
      'PDF': AppColors.filePdf,
      'DOCX': AppColors.fileWord,
      'XLSX': AppColors.fileExcel,
      'PPTX': AppColors.filePpt,
      'TXT': AppColors.fileText,
      'PPT': AppColors.filePpt,
      'XLS': AppColors.fileExcel,
      'DOC': AppColors.fileWord,
    };

    String fileType = document.type.toUpperCase();
    IconData icon = docIcons[fileType] ?? Icons.insert_drive_file;
    Color color = docColors[fileType] ?? AppColors.primary;

    // Format the date to DD MM YYYY
    String formattedDate = _formatToDDMMYYYY(document.uploadDate);

    // Get document opener service instance
    final documentOpener = DocumentOpenerService();

    // Check if this specific document is expanded using its ID
    bool isExpanded = _expandedStates[document.id] ?? false;

    final isSelected = _selectedIds.contains(document.id);

    return InkWell(
      onTap: () => _selecting
          ? _toggleSelected(document)
          : documentOpener.openViewer(context: context, document: document),
      onLongPress: () => _toggleSelected(document),
      borderRadius: BorderRadius.circular(r.p(12)),
      child: Card(
        margin: EdgeInsets.only(bottom: r.p(16)),
        elevation: isSelected ? 0 : 2,
        color: isSelected ? const Color(0xFFE3F1FF) : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(r.p(12)),
          side: isSelected
              ? const BorderSide(color: AppColors.primary, width: 1.5)
              : BorderSide.none,
        ),
        child: Padding(
          padding: EdgeInsets.all(r.p(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Checkbox | icon | name + meta | actions (all vertically centred)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (_selecting) ...[
                    _selectionCheckbox(isSelected),
                    SizedBox(width: r.p(12)),
                  ],
                  Container(
                    width: r.p(52),
                    height: r.p(52),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withAlpha(10),
                      borderRadius: BorderRadius.circular(r.p(8)),
                    ),
                    child: FileTypeIcon.orElse(
                      document.type,
                      r.sp(32),
                      Icon(icon, color: color, size: r.sp(32)),
                    ),
                  ),
                  SizedBox(width: r.p(14)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
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
                        SizedBox(height: r.p(2)),
                        Text(
                          'Type: ${document.type} \u2022 $formattedDate',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: r.sp(11),
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: r.p(8)),
                  // Expand / collapse details
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _expandedStates[document.id] = !isExpanded;
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: r.p(34),
                      height: r.p(34),
                      decoration: BoxDecoration(
                        color: isExpanded
                            ? color.withAlpha(20)
                            : AppColors.surfaceVariant,
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
                            color: isExpanded ? color : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // File actions: only while this document is selected
                  if (isSelected) ...[
                    SizedBox(width: r.p(4)),
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _toggleFavorite(document),
                      child: Padding(
                        padding: EdgeInsets.all(r.p(6)),
                        child: Icon(
                          _isFavorite(document.id)
                              ? Icons.favorite
                              : Icons.favorite_border,
                          size: r.sp(22),
                          color: _isFavorite(document.id)
                              ? AppColors.error
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _showDocumentActions(document, index),
                      child: Padding(
                        padding: EdgeInsets.all(r.p(6)),
                        child: Icon(
                          Icons.more_vert,
                          size: r.sp(22),
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
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
                            Icons.label_important_outline,
                          ),
                          _buildDetailRow(
                            'Owner',
                            document.owner,
                            Icons.person_2_outlined,
                          ),
                          _buildDetailRow(
                            'Folder',
                            document.folder,
                            Icons.folder_copy_outlined,
                          ),
                          _buildDetailRow(
                            'Classification',
                            document.classification,
                            Icons.security_outlined,
                          ),
                          _buildDetailRow(
                            'Sharing',
                            document.sharingType,
                            Icons.share_location_outlined,
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
                                foregroundColor: AppColors.info,
                                side: const BorderSide(color: AppColors.info),
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
                                foregroundColor: AppColors.success,
                                side: const BorderSide(
                                  color: AppColors.success,
                                ),
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

  Widget _selectionCheckbox(bool selected) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: selected ? AppColors.primary : Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.textTertiary,
          width: 1.5,
        ),
      ),
      child: selected
          ? const Icon(Icons.check, size: 16, color: Colors.white)
          : null,
    );
  }

  // Helper method for detail rows
  Widget _buildDetailRow(String label, String value, IconData icon) {
    final r = context.r;
    return Padding(
      padding: EdgeInsets.only(bottom: r.p(8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: r.sp(16), color: AppColors.textTertiary),
          SizedBox(width: r.p(8)),
          SizedBox(
            width: r.p(90),
            child: Text(
              '$label:',
              style: w400_14Poppins(color: AppColors.textTertiary),
            ),
          ),
          SizedBox(width: r.p(8)),
          Expanded(
            child: Text(
              value,
              style: w500_14Poppins(),
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

  static const _typeFilterLabels = <String, String>{
    'pdf': 'PDF',
    'doc': 'DOC / DOCX',
    'xls': 'XLS / XLSX',
    'ppt': 'PPT / PPTX',
    'image': 'Images',
  };

  static const _typeFilterExts = <String, Set<String>>{
    'pdf': {'pdf'},
    'doc': {'doc', 'docx'},
    'xls': {'xls', 'xlsx', 'csv'},
    'ppt': {'ppt', 'pptx'},
    'image': {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'image'},
  };

  String _extOf(String raw) {
    var e = raw.toLowerCase().trim();
    if (e.contains('/')) e = e.split('/').last;
    if (e.contains('.')) e = e.split('.').last;
    return e;
  }

  bool _matchesTypeFilter(Document d) {
    if (_typeFilter == 'all') return true;
    final exts = _typeFilterExts[_typeFilter] ?? const <String>{};
    return exts.contains(_extOf(d.type)) || exts.contains(_extOf(d.name));
  }

  List<Folder> _getFilteredFolders() {
    // Folders have no document type, so a type filter hides them.
    if (_typeFilter != 'all') return const <Folder>[];
    final term = _searchController.text.trim().toLowerCase();
    if (term.isEmpty) return subfolders;
    return subfolders
        .where((f) => f.name.toLowerCase().contains(term))
        .toList();
  }

  List<Document> _getFilteredDocuments() {
    final base = _searchFilteredDocuments();
    if (_typeFilter == 'all') return base;
    return base.where(_matchesTypeFilter).toList();
  }

  List<Document> _searchFilteredDocuments() {
    List<Document> allDocs = List.from(documents);

    if (_showRecent) {
      allDocs.sort((a, b) => b.uploadDate.compareTo(a.uploadDate));
      return allDocs.take(10).toList();
    }

    final aiIds = _aiResultIds;
    if (aiIds != null) {
      return allDocs.where((d) => aiIds.contains(d.id)).toList()
        ..sort((a, b) => aiIds.indexOf(a.id).compareTo(aiIds.indexOf(b.id)));
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
