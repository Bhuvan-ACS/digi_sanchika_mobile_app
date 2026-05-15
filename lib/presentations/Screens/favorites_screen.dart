import 'package:flutter/material.dart';
import 'package:digi_sanchika/services/favorites_service.dart';
import 'package:digi_sanchika/models/favorite_item.dart';
import 'package:digi_sanchika/services/document_library_service.dart';
import 'package:digi_sanchika/local_storage.dart';
import 'package:digi_sanchika/models/document.dart';
import 'package:digi_sanchika/services/document_opener_service.dart';
import 'package:digi_sanchika/services/my_documents_service.dart';
import 'package:digi_sanchika/services/api_service.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:digi_sanchika/services/download_requests_service.dart';
import 'package:digi_sanchika/widgets/share_access_sheet.dart';
import 'package:digi_sanchika/services/download_access_service.dart';
import 'package:digi_sanchika/models/app_view_mode.dart';
import 'package:digi_sanchika/widgets/view_mode_popup_button.dart';
import 'package:digi_sanchika/widgets/download_feedback.dart';
import 'package:digi_sanchika/widgets/responsive_page.dart';

class FavoriteEntry {
  final FavoriteItem favorite;
  final Document document;

  FavoriteEntry({required this.favorite, required this.document});
}

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final FavoritesService _service = FavoritesService();
  bool _isLoading = true;
  List<FavoriteEntry> _documents = [];
  AppViewMode _currentViewMode = AppViewMode.list;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final items = await _service.listFavorites();
      final docFavorites =
          items
              .where((i) => i.entityType.toLowerCase().contains('doc'))
              .toList();

      final localDocs = await LocalStorageService.loadDocuments();
      final localMap = {for (final doc in localDocs) doc.id: doc};

      final List<FavoriteEntry?> entries =
          List<FavoriteEntry?>.filled(docFavorites.length, null);
      final List<Future<void>> fetches = [];

      for (int i = 0; i < docFavorites.length; i++) {
        final fav = docFavorites[i];
        final localDoc = localMap[fav.entityId];
        if (localDoc != null) {
          entries[i] = FavoriteEntry(favorite: fav, document: localDoc);
        } else {
          fetches.add(
            _fetchDocumentForFavorite(fav).then((doc) {
              entries[i] = FavoriteEntry(favorite: fav, document: doc);
            }),
          );
        }
      }

      if (fetches.isNotEmpty) {
        await Future.wait(fetches);
      }

      if (!mounted) return;
      setState(() {
        _documents = entries.whereType<FavoriteEntry>().toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _documents = [];
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load favorites: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<Document> _fetchDocumentForFavorite(FavoriteItem favorite) async {
    try {
      final preferLibrary = _isLibraryFavorite(favorite.entityType);

      if (preferLibrary) {
        final libResult =
            await DocumentLibraryService().getDocumentDetails(favorite.entityId);
        if (libResult['success'] == true) {
          final details =
              libResult['data'] is Map<String, dynamic>
                  ? libResult['data'] as Map<String, dynamic>
                  : <String, dynamic>{};
          if (details.isNotEmpty) {
            final doc = _documentFromDetails(
              details,
              fallbackName: favorite.name,
              forcePublic: true,
            );
            return doc;
          }
        }
      }

      final result =
          await MyDocumentsService.getDocumentDetails(favorite.entityId);
      if (result['success'] == true) {
        final details =
            result['details'] is Map<String, dynamic>
                ? result['details'] as Map<String, dynamic>
                : <String, dynamic>{};
        if (details.isNotEmpty) {
          return _documentFromDetails(
            details,
            fallbackName: favorite.name,
          );
        }
      }

      if (!preferLibrary) {
        final libResult =
            await DocumentLibraryService().getDocumentDetails(favorite.entityId);
        if (libResult['success'] == true) {
          final details =
              libResult['data'] is Map<String, dynamic>
                  ? libResult['data'] as Map<String, dynamic>
                  : <String, dynamic>{};
          if (details.isNotEmpty) {
            return _documentFromDetails(
              details,
              fallbackName: favorite.name,
              forcePublic: true,
            );
          }
        }
      }
    } catch (_) {}

    final fallbackName =
        (favorite.name != null && favorite.name!.trim().isNotEmpty)
            ? favorite.name!.trim()
            : favorite.entityId;
    final fallbackType = _extractFileType(fallbackName);
    final fallbackIsPublic = _isLibraryFavorite(favorite.entityType);

    return Document(
      id: favorite.entityId,
      name: fallbackName,
      type: fallbackType,
      size: 'Unknown',
      keyword: '',
      uploadDate: DateTime.now().toString(),
      owner: '',
      details: '',
      classification: 'internal',
      allowDownload: true,
      sharingType: fallbackIsPublic ? 'Public' : 'Private',
      folder: 'Home',
      path: fallbackName,
      fileType: fallbackType,
    );
  }

  Document _documentFromDetails(
    Map<String, dynamic> doc, {
    String? fallbackName,
    bool forcePublic = false,
  }) {
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

    String extractFileName(Map<String, dynamic> docData) {
      return safeString(
        docData['name'] ??
            docData['original_filename'] ??
            docData['original_name'] ??
            docData['file_name'] ??
            docData['fileName'] ??
            docData['filename'],
        fallback: fallbackName ?? 'Unknown',
      );
    }

    final fileName = extractFileName(doc);
    final mimeType = doc['mime_type']?.toString();
    final fileType = mimeType != null && mimeType.isNotEmpty
        ? _extractFileTypeFromMime(mimeType, fileName)
        : _extractFileType(fileName);

    final classification = safeString(
      doc['classification'] ?? doc['doc_class'],
      fallback: 'internal',
    );
    final isPublic =
        forcePublic ||
        doc['is_public'] == true ||
        classification.toLowerCase() == 'public';

    return Document(
      id: safeString(doc['id']),
      name: fileName,
      type: fileType,
      size:
          '${safeString(doc['file_size_bytes'] ?? doc['file_size'], fallback: 'Unknown')} bytes',
      keyword: safeString(doc['keywords']),
      uploadDate: safeString(
        doc['created_at'] ?? doc['updated_at'] ?? doc['upload_date'],
        fallback: DateTime.now().toString(),
      ),
      owner: extractOwnerName(doc['owner']),
      details: safeString(doc['remarks']),
      classification: classification,
      allowDownload: doc['allow_download'] ?? true,
      sharingType: isPublic ? 'Public' : 'Private',
      folder: safeString(doc['folder_path'], fallback: 'Home'),
      folderId: doc['folder_id']?.toString(),
      path: fileName,
      fileType: fileType,
    );
  }

  bool _isLibraryFavorite(String rawType) {
    final value = rawType.toLowerCase();
    return value.contains('library') ||
        value.contains('public') ||
        value.contains('hub');
  }

  String _extractFileType(String filename) {
    if (filename.isEmpty) return 'UNKNOWN';
    final parts = filename.split('.');
    if (parts.length < 2) return 'UNKNOWN';
    final extension = parts.last.toLowerCase();
    final typeMap = {
      'pdf': 'PDF',
      'doc': 'DOC',
      'docx': 'DOCX',
      'xls': 'XLS',
      'xlsx': 'XLSX',
      'ppt': 'PPT',
      'pptx': 'PPTX',
      'txt': 'TXT',
      'csv': 'CSV',
      'jpg': 'JPG',
      'jpeg': 'JPEG',
      'jfif': 'JPG',
      'png': 'PNG',
      'zip': 'ZIP',
      'rar': 'RAR',
    };
    return typeMap[extension] ?? extension.toUpperCase();
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

  IconData _getDocumentIcon(String fileType) {
    final icons = {
      'PDF': Icons.picture_as_pdf,
      'DOC': Icons.description,
      'DOCX': Icons.description,
      'XLS': Icons.table_chart,
      'XLSX': Icons.table_chart,
      'PPT': Icons.slideshow,
      'PPTX': Icons.slideshow,
      'CSV': Icons.table_chart,
      'TXT': Icons.text_snippet,
      'JPG': Icons.image,
      'JPEG': Icons.image,
      'PNG': Icons.image,
      'IMAGE': Icons.image,
      'ZIP': Icons.archive,
      'RAR': Icons.archive,
    };
    return icons[fileType.toUpperCase()] ?? Icons.insert_drive_file;
  }

  Color _getDocumentColor(String fileType) {
    final colors = {
      'PDF': Colors.red,
      'DOC': Colors.blue,
      'DOCX': Colors.blue,
      'XLS': Colors.green,
      'XLSX': Colors.green,
      'PPT': Colors.orange,
      'PPTX': Colors.orange,
      'CSV': Colors.green,
      'TXT': Colors.grey,
      'JPG': Colors.deepOrange,
      'JPEG': Colors.deepOrange,
      'JFIF': Colors.deepOrange,
      'PNG': Colors.deepOrange,
      'IMAGE': Colors.deepOrange,
    };
    return colors[fileType.toUpperCase()] ?? Colors.indigo;
  }

  String _normalizeEntityType(String raw) {
    final value = raw.toLowerCase();
    if (value.contains('doc')) return 'document';
    if (value.contains('folder')) return 'folder';
    return raw;
  }

  String _displayName(FavoriteEntry entry) {
    final name = entry.document.name.trim();
    if (name.isNotEmpty && name.toLowerCase() != 'unknown') return name;
    final fallback = entry.favorite.name?.trim() ?? '';
    if (fallback.isNotEmpty) return fallback;
    return entry.favorite.entityId;
  }

  String _formatDateDDMMYYYY(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      final year = date.year.toString();
      return '$day $month $year';
    } catch (_) {
      return '';
    }
  }

  Widget _buildFavoriteCard(FavoriteEntry entry) {
    final doc = entry.document;
    final displayName = _displayName(entry);
    final docType =
        (doc.type.isNotEmpty ? doc.type : doc.fileType).toUpperCase();
    final icon = _getDocumentIcon(docType);
    final color = _getDocumentColor(docType);
    final formattedDate = _formatDateDDMMYYYY(doc.uploadDate);
    final subtitle =
        formattedDate.isNotEmpty
            ? 'Type: $docType • $formattedDate'
            : 'Type: $docType';

    return InkWell(
      onTap: () =>
          DocumentOpenerService().openPreviewDialog(context: context, document: doc),
      borderRadius: BorderRadius.circular(12),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () => _showDocumentActions(entry),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDocumentActions(FavoriteEntry entry) {
    final document = entry.document;
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
                  DocumentOpenerService().openPreviewDialog(
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
                leading: const Icon(Icons.star, color: Colors.amber),
                title: const Text('Remove from Favorites'),
                onTap: () async {
                  Navigator.pop(context);
                  await _service.removeFavorite(
                    entityId: entry.favorite.entityId,
                    entityType: _normalizeEntityType(entry.favorite.entityType),
                  );
                  if (!mounted) return;
                  setState(() {
                    _documents.remove(entry);
                  });
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
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

    try {
      final result = await DownloadAccessService.downloadBytesWithAccess(
        documentId: document.id,
      );
      if (result['success'] == true) {
        final directory = await getApplicationDocumentsDirectory();
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
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              reqResult['success'] == true
                  ? 'Download request sent for approval'
                  : (reqResult['message'] ?? 'Download request failed'),
            ),
            backgroundColor:
                reqResult['success'] == true ? Colors.orange : Colors.red,
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

  Widget _buildFavoritesContent() {
    switch (_currentViewMode) {
      case AppViewMode.list:
      case AppViewMode.detailed:
        return ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          itemCount: _documents.length,
          itemBuilder: (context, index) => _buildFavoriteCard(_documents[index]),
        );
      case AppViewMode.compact:
        return ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          itemCount: _documents.length,
          itemBuilder: (context, index) =>
              _buildFavoriteCompactItem(_documents[index], index),
        );
      case AppViewMode.grid2x2:
      case AppViewMode.grid3x3:
        final crossAxisCount = _currentViewMode == AppViewMode.grid3x3 ? 3 : 2;
        final spacing = _currentViewMode == AppViewMode.grid3x3 ? 8.0 : 12.0;
        final aspect = _currentViewMode == AppViewMode.grid3x3 ? 0.90 : 0.96;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: aspect,
          ),
          itemCount: _documents.length,
          itemBuilder: (context, index) =>
              _buildFavoriteGridItem(_documents[index], index),
        );
    }
  }

  Widget _buildFavoriteCompactItem(FavoriteEntry entry, int index) {
    final doc = entry.document;
    final name = _displayName(entry);
    final type = (doc.type.isNotEmpty ? doc.type : doc.fileType).toUpperCase();
    final icon = _getDocumentIcon(type);
    final color = _getDocumentColor(type);

    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -2),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withAlpha(18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(type, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: IconButton(
        icon: const Icon(Icons.more_vert),
        onPressed: () => _showDocumentActions(entry),
      ),
      onTap: () => DocumentOpenerService()
          .openPreviewDialog(context: context, document: doc),
    );
  }

  Widget _buildFavoriteGridItem(FavoriteEntry entry, int index) {
    final doc = entry.document;
    final name = _displayName(entry);
    final type = (doc.type.isNotEmpty ? doc.type : doc.fileType).toUpperCase();
    final icon = _getDocumentIcon(type);
    final color = _getDocumentColor(type);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => DocumentOpenerService()
            .openPreviewDialog(context: context, document: doc),
        onLongPress: () => _showDocumentActions(entry),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withAlpha(18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.black38),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              const Spacer(),
              Text(
                type,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Favorites'),
        actions: [
          ViewModePopupButton(
            value: _currentViewMode,
            iconColor: Colors.white,
            onSelected: (mode) => setState(() => _currentViewMode = mode),
          ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ResponsivePage(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _documents.isEmpty
                ? const Center(child: Text('No favorites'))
                : RefreshIndicator(onRefresh: _load, child: _buildFavoritesContent()),
      ),
    );
  }
}
