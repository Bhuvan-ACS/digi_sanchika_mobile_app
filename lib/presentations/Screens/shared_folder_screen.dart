// screens/shared_folder_screen.dart
import 'dart:convert';
import 'package:digi_sanchika/utils/app_fonts.dart';
import 'package:flutter/material.dart';
import 'package:digi_sanchika/services/shared_browse_service.dart';
import 'package:digi_sanchika/models/document.dart';
import 'package:digi_sanchika/services/api_service.dart';
import 'package:digi_sanchika/services/document_opener_service.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:digi_sanchika/services/shared_documents_service.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:digi_sanchika/services/download_requests_service.dart';
import 'package:digi_sanchika/services/download_access_service.dart';
import 'package:digi_sanchika/services/folder_download_service.dart';
import 'package:digi_sanchika/widgets/download_feedback.dart';
import 'package:digi_sanchika/widgets/version_history_dialog.dart';
import 'package:digi_sanchika/widgets/dismiss_keyboard.dart';

// Add enum for layout modes
enum SharedFolderViewMode { list, grid2x2, grid3x3, compact, detailed }

class SharedFolderScreen extends StatefulWidget {
  final String? folderId;
  final String folderName;
  final String? userName;

  const SharedFolderScreen({
    super.key,
    this.folderId,
    required this.folderName,
    this.userName,
  });

  @override
  State<SharedFolderScreen> createState() => _SharedFolderScreenState();
}

class _SharedFolderScreenState extends State<SharedFolderScreen> {
  List<Document> _documents = [];
  List<Map<String, dynamic>> _subfolders = [];
  final Map<String, int> _subfolderItemCounts = {}; // folderId -> immediate child count
  Map<String, dynamic>? _shareMeta;

  bool _isLoading = true;
  bool _hasError = false;
  bool _isDownloading = false;
  String _errorMessage = '';

  final TextEditingController _searchController = TextEditingController();
  final DocumentOpenerService _documentOpener = DocumentOpenerService();
  final SharedDocumentsService _sharedService = SharedDocumentsService();

  // NEW: Layout mode, file type filter, and collapsible states
  SharedFolderViewMode _currentViewMode = SharedFolderViewMode.list;
  String _selectedFileType = 'All';
  List<String> _availableFileTypes = ['All'];
  Map<String, bool> _expandedStates = {};

  @override
  void initState() {
    super.initState();
    _loadSharedFolderContents();
  }

  Future<void> _loadSharedFolderContents() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = '';
    });

    try {
      final result = await SharedBrowseService.getSharedFolderContents(
        folderId: widget.folderId,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        final documents = (result['documents'] as List).cast<Document>();
        final fileTypes = documents
            .map((doc) => doc.type.toUpperCase())
            .toSet()
            .toList();
        fileTypes.sort();

        setState(() {
          _documents = documents;
          _subfolders = (result['folders'] as List)
              .cast<Map<String, dynamic>>();
          _shareMeta = result['share'] is Map<String, dynamic>
              ? (result['share'] as Map<String, dynamic>)
              : null;
          _availableFileTypes = ['All', ...fileTypes];
          _isLoading = false;
        });

        // Load subfolder item counts in the background so the UI doesn't stay at 0.
        _loadSubfolderItemCounts(_subfolders);
      } else {
        setState(() {
          _hasError = true;
          _errorMessage =
              result['error']?.toString() ?? 'Failed to load folder';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _hasError = true;
        _errorMessage = 'Error: $e';
        _isLoading = false;
      });
      debugPrint('Error loading shared folder: $e');
    }
  }

  void _navigateToSubfolder(Map<String, dynamic> folder) {
    final sharedBy = _resolveSharedBy(folder);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SharedFolderScreen(
          folderId: folder['id']?.toString(),
          folderName: folder['name']?.toString() ?? 'Shared Folder',
          userName: sharedBy,
        ),
      ),
    );
  }

 

  // ============ FILTERING ============
  List<Document> _filterDocuments() {
    final searchTerm = _searchController.text.toLowerCase();
    final filteredBySearch = searchTerm.isEmpty
        ? _documents
        : _documents.where((doc) {
            return doc.name.toLowerCase().contains(searchTerm) ||
                doc.keyword.toLowerCase().contains(searchTerm) ||
                doc.owner.toLowerCase().contains(searchTerm) ||
                doc.type.toLowerCase().contains(searchTerm);
          }).toList();

    // Apply file type filter
    if (_selectedFileType == 'All') return filteredBySearch;

    return filteredBySearch
        .where((doc) => doc.type.toUpperCase() == _selectedFileType)
        .toList();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {});
  }

  // ============ DOWNLOAD FUNCTIONALITY ============
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
        'Starting download for document: ${document.id} - ${document.name}',
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

      if (result['success'] == true) {
        final fileData = result['bytes'] ?? result['fileData'];
        List<int> bytesToSave;

        if (fileData is List<int>) {
          bytesToSave = fileData;
        } else if (fileData is List<dynamic>) {
          bytesToSave = fileData.cast<int>();
        } else if (fileData is String) {
          bytesToSave = utf8.encode(fileData);
        } else {
          throw Exception('Invalid file data format');
        }

        if (bytesToSave.isEmpty) {
          throw Exception('Downloaded file data is empty');
        }

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
        final file = File(filePath);
        await file.writeAsBytes(bytesToSave);

        if (await file.exists()) {
          final fileSize = await file.length(); // Get file size FIRST

          if (document.size == '0' ||
              document.size == '0 KB' ||
              document.size == '0 B') {
            final docIndex = _documents.indexWhere((d) => d.id == document.id);
            if (docIndex != -1) {
              setState(() {
                _documents[docIndex] = document.copyWith(
                  size: fileSize.toString(),
                ); // Use the variable
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

          try {
            final uriToOpen = Platform.isAndroid
                ? _getFileProviderUri(filePath)
                : filePath;
            final openResult = await OpenFilex.open(uriToOpen);

            if (openResult.type != ResultType.done && Platform.isAndroid) {
              try {
                await OpenFilex.open(filePath);
              } catch (e) {
                debugPrint('Fallback also failed: $e');
              }
              _showSnackBar(
                'File downloaded. Could not open automatically.',
                Colors.orange,
              );
            }
          } catch (e) {
            debugPrint('Error opening file: $e');
            _showSnackBar(
              'File downloaded. Use a compatible app to open it.',
              Colors.blue,
            );
          }
        } else {
          throw Exception('Failed to save file to disk');
        }
      } else {
        throw Exception(
          result['error'] ?? result['message'] ?? 'Download failed',
        );
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

  Future<Directory> getDownloadDirectory() async {
    if (Platform.isAndroid || Platform.isIOS) {
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
        debugPrint('Error creating FileProvider URI: $e');
      }
    }
    return filePath;
  }

  void _showFileContent(List<int> fileBytes, String filename) {
    try {
      final content = utf8.decode(fileBytes);

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              _getFileIcon('py', 24),
              const SizedBox(width: 12),
              Expanded(child: Text(filename, overflow: TextOverflow.ellipsis)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: MediaQuery.of(context).size.height * 0.6,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.code, size: 16, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Python file (${fileBytes.length} bytes)',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color.fromRGBO(224, 224, 224, 1),
                      ),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        content,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
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
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy'),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('Error showing file content: $e');
      _showSnackBar('Cannot display file content', Colors.red);
    }
  }

  // ============ DOCUMENT HANDLING ============
  void _handleDocumentDoubleTap(Document document) {
    _documentOpener.openPreviewDialog(context: context, document: document);
  }

  String _resolveSharedBy(Map<String, dynamic> folder) {
    String? from(dynamic v) {
      if (v == null) return null;
      if (v is String) {
        final s = v.trim();
        return s.isEmpty ? null : s;
      }
      if (v is Map) {
        final name = v['name'] ?? v['full_name'] ?? v['username'];
        if (name is String && name.trim().isNotEmpty) return name.trim();
      }
      return null;
    }

    return from(folder['shared_by']) ??
        from(folder['sharedBy']) ??
        from(folder['owner']) ??
        from(folder['owner_name']) ??
        from(folder['shared_by_name']) ??
        from(_shareMeta?['shared_by']) ??
        from(_shareMeta?['sharedBy']) ??
        (widget.userName?.trim().isNotEmpty == true ? widget.userName!.trim() : 'Unknown');
  }

  String _displayOwner(Document document) {
    final o = document.owner.trim();
    if (o.isNotEmpty && o.toLowerCase() != 'unknown') return o;
    final sharedBy = widget.userName?.trim() ?? '';
    return sharedBy.isNotEmpty ? sharedBy : 'Unknown';
  }

  Future<void> _downloadFolderZip(Map<String, dynamic> folder) async {
    final folderId = folder['id']?.toString();
    final folderName = folder['name']?.toString() ?? 'Folder';
    if (folderId == null || folderId.isEmpty) return;

    if (!ApiService.isConnected) {
      _showSnackBar('Cannot download while offline', Colors.orange);
      return;
    }

    try {
      final svc = FolderDownloadService();
      final result = await svc.downloadFolderAsZipWithAccess(
        folderId: folderId,
        reason: 'Need offline copy',
        folderNameHint: folderName,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        await DownloadFeedback.showDownloadedDialog(
          context,
          filename: (result['filename'] ?? '$folderName.zip').toString(),
          filePath: (result['filePath'] ?? '').toString(),
        );
        return;
      }

      if (result['requiresApproval'] == true) {
        _showSnackBar(
          (result['requestCreated'] == true)
              ? 'Download request sent for approval'
              : (result['message']?.toString() ?? 'Download requires approval'),
          (result['requestCreated'] == true) ? Colors.orange : Colors.red,
        );
        return;
      }

      _showSnackBar(() {
        final err = result['error']?.toString() ?? 'Download failed';
        final d = result['downloaded'];
        final f = result['failed'];
        if (d is int || f is int) {
          return '$err (downloaded: ${d ?? 0}, failed: ${f ?? 0})';
        }
        return err;
      }(), Colors.red);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Download failed: $e', Colors.red);
    }
  }

  Future<void> _loadSubfolderItemCounts(List<Map<String, dynamic>> folders) async {
    // Fetch immediate child counts for each folder (documents + subfolders).
    for (final folder in folders) {
      final id = folder['id']?.toString();
      if (id == null || id.isEmpty) continue;
      if (_subfolderItemCounts.containsKey(id)) continue;

      // Mark as loading (sentinel) so UI can show a placeholder.
      _subfolderItemCounts[id] = -1;
      if (mounted) setState(() {});

      try {
        final res = await SharedBrowseService.getSharedFolderContents(
          folderId: id,
        );

        if (!mounted) return;

        if (res['success'] == true) {
          final docs = (res['documents'] as List?)?.length ?? 0;
          final subs = (res['folders'] as List?)?.length ?? 0;
          _subfolderItemCounts[id] = docs + subs;
        } else {
          // Fallback to API-provided count if any, otherwise 0.
          _subfolderItemCounts.remove(id);
        }
      } catch (_) {
        if (!mounted) return;
        _subfolderItemCounts.remove(id);
      }

      if (mounted) setState(() {});
    }
  }

  Future<void> _downloadFolderFiles(Map<String, dynamic> folder) async {
    final folderId = folder['id']?.toString();
    final folderName = folder['name']?.toString() ?? 'Folder';
    if (folderId == null || folderId.isEmpty) return;

    if (!ApiService.isConnected) {
      _showSnackBar('Cannot download while offline', Colors.orange);
      return;
    }

    try {
      final svc = FolderDownloadService();
      final result = await svc.downloadFolderFilesWithAccess(
        folderId: folderId,
        reason: 'Need offline copy',
        folderNameHint: folderName,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        await DownloadFeedback.showDownloadedDialog(
          context,
          filename: (result['rootName'] ?? folderName).toString(),
          filePath: (result['folderPath'] ?? '').toString(),
        );
        return;
      }

      if (result['requiresApproval'] == true) {
        _showSnackBar(
          (result['requestCreated'] == true)
              ? 'Download request sent for approval'
              : (result['message']?.toString() ?? 'Download requires approval'),
          (result['requestCreated'] == true) ? Colors.orange : Colors.red,
        );
        return;
      }

      _showSnackBar(() {
        final err = result['error']?.toString() ?? 'Download failed';
        final d = result['downloaded'];
        final f = result['failed'];
        if (d is int || f is int) {
          return '$err (downloaded: ${d ?? 0}, failed: ${f ?? 0})';
        }
        return err;
      }(), Colors.red);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Download failed: $e', Colors.red);
    }
  }

  void _showDocumentActions(Document document) {
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
                leading: const Icon(Icons.download, color: Colors.green),
                title: Text(
                  document.allowDownload ? 'Download' : 'Request Download',
                ),
                onTap: () {
                  Navigator.pop(context);
                  _downloadDocument(document);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showDocumentDetails(Document document) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            _getFileIcon(document.type, 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(document.name, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDialogDetailRow('File Name', document.name),
              _buildDialogDetailRow('File Type', document.type.toUpperCase()),
              _buildDialogDetailRow('Size', _formatFileSize(document.size)),
              _buildDialogDetailRow('Owner', _displayOwner(document)),
              _buildDialogDetailRow('Upload Date', document.uploadDate),
              _buildDialogDetailRow('Folder', document.folder),
              _buildDialogDetailRow('Classification', document.classification),
              _buildDialogDetailRow('Keywords', document.keyword),
              _buildDialogDetailRow('Remarks', document.details),
              _buildDialogDetailRow(
                'Download Allowed',
                document.allowDownload ? 'Yes' : 'No',
              ),
              _buildDialogDetailRow('Sharing Type', document.sharingType),
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
              _downloadDocument(document);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.download, size: 18),
                const SizedBox(width: 6),
                Text(
                  document.allowDownload ? 'Download' : 'Request Download',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDocumentVersions(Document document) async {
    await VersionHistoryDialog.show(context, document: document);
  }

  // ============ FEATURE 1: COLLAPSIBLE DOCUMENT CARDS ============
  Widget _buildDocumentCard(Document document) {
    final iconData = _getFileIconData(document.type);
    final color = _getFileColor(document.type);
    final bool isExpanded = _expandedStates[document.id] ?? false;
    final formattedDate = _formatDateDDMMYYYY(document.uploadDate);

    return InkWell(
      onTap: () => _handleDocumentDoubleTap(document),
      borderRadius: BorderRadius.circular(12),
      child: Card(
        margin: const EdgeInsets.symmetric( vertical: 4),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withAlpha(10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(iconData, color: color, size: 32),
                  ),
                  const SizedBox(width: 16),
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
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: isExpanded ? 2 : 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  height5,
                                     Text(
                                                        'Type: ${document.type} • $formattedDate',
                                                        style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                                                        ),
                                                      ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _expandedStates[document.id] = !isExpanded;
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                width: 25,
                                height: 25,
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
                                      size: 22,
                                      color: isExpanded
                                          ? color
                                          : Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: () =>
                                  _showDocumentActions(document),
                              icon: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.more_vert,
                                    size: 20,
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
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: SizedBox(
                  height: isExpanded ? null : 0,
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      if (document.keyword.isNotEmpty)
                        _buildDetailRow(
                          'Keyword',
                          document.keyword,
                          Icons.label,
                        ),
                      _buildDetailRow(
                        'Owner',
                        _displayOwner(document),
                        Icons.person,
                      ),
                      _buildDetailRow('Folder', document.folder, Icons.folder),
                      _buildDetailRow(
                        'Classification',
                        document.classification,
                        Icons.security,
                      ),
                      if (document.details.isNotEmpty)
                        _buildDetailRow(
                          'Details',
                          document.details,
                          Icons.info_outline,
                        ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  _handleDocumentDoubleTap(document),
                              icon: const Icon(Icons.visibility, size: 18),
                              label: const Text('View'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.purple,
                                side: const BorderSide(color: Colors.purple),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _showDocumentVersions(document),
                              icon: const Icon(Icons.history, size: 18),
                              label: const Text('Versions'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.blue,
                                side: const BorderSide(color: Colors.blue),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
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

  // ============ FEATURE 2: LAYOUT MODES ============
  Widget _buildLayoutSelector() {
    return PopupMenuButton<SharedFolderViewMode>(
      tooltip: 'Change Layout',
      icon: Icon(
        _getViewModeIcon(_currentViewMode),
        color: Colors.indigo,
        size: 24,
      ),
      onSelected: (SharedFolderViewMode mode) {
        setState(() {
          _currentViewMode = mode;
        });
      },
      itemBuilder: (context) => <PopupMenuEntry<SharedFolderViewMode>>[
        PopupMenuItem(
          value: SharedFolderViewMode.list,
          child: Row(
            children: [
              Icon(Icons.list, color: Colors.indigo),
              SizedBox(width: 8),
              Text('List View'),
              if (_currentViewMode == SharedFolderViewMode.list)
                Icon(Icons.check, color: Colors.green, size: 16),
            ],
          ),
        ),
        PopupMenuItem(
          value: SharedFolderViewMode.grid2x2,
          child: Row(
            children: [
              Icon(Icons.grid_on, color: Colors.indigo),
              SizedBox(width: 8),
              Text('Grid (2x2)'),
              if (_currentViewMode == SharedFolderViewMode.grid2x2)
                Icon(Icons.check, color: Colors.green, size: 16),
            ],
          ),
        ),
        PopupMenuItem(
          value: SharedFolderViewMode.grid3x3,
          child: Row(
            children: [
              Icon(Icons.view_module, color: Colors.indigo),
              SizedBox(width: 8),
              Text('Grid (3x3)'),
              if (_currentViewMode == SharedFolderViewMode.grid3x3)
                Icon(Icons.check, color: Colors.green, size: 16),
            ],
          ),
        ),
        PopupMenuItem(
          value: SharedFolderViewMode.compact,
          child: Row(
            children: [
              Icon(Icons.view_headline, color: Colors.indigo),
              SizedBox(width: 8),
              Text('Compact View'),
              if (_currentViewMode == SharedFolderViewMode.compact)
                Icon(Icons.check, color: Colors.green, size: 16),
            ],
          ),
        ),
        PopupMenuItem(
          value: SharedFolderViewMode.detailed,
          child: Row(
            children: [
              Icon(Icons.table_rows, color: Colors.indigo),
              SizedBox(width: 8),
              Text('Detailed View'),
              if (_currentViewMode == SharedFolderViewMode.detailed)
                Icon(Icons.check, color: Colors.green, size: 16),
            ],
          ),
        ),
      ],
    );
  }

  IconData _getViewModeIcon(SharedFolderViewMode mode) {
    switch (mode) {
      case SharedFolderViewMode.list:
        return Icons.list;
      case SharedFolderViewMode.grid2x2:
        return Icons.grid_on;
      case SharedFolderViewMode.grid3x3:
        return Icons.view_module;
      case SharedFolderViewMode.compact:
        return Icons.view_headline;
      case SharedFolderViewMode.detailed:
        return Icons.table_rows;
    }
  }

  Widget _buildDocumentsContent(List<Document> documents) {
    switch (_currentViewMode) {
      case SharedFolderViewMode.list:
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: documents.length,
          itemBuilder: (context, index) => _buildDocumentCard(documents[index]),
        );
      case SharedFolderViewMode.grid2x2:
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.9,
          ),
          itemCount: documents.length,
          itemBuilder: (context, index) =>
              _buildDocumentGridItem(documents[index], 2),
        );
      case SharedFolderViewMode.grid3x3:
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 0.85,
          ),
          itemCount: documents.length,
          itemBuilder: (context, index) =>
              _buildDocumentGridItem(documents[index], 3),
        );
      case SharedFolderViewMode.compact:
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: documents.length,
          itemBuilder: (context, index) =>
              _buildDocumentCompactItem(documents[index]),
        );
      case SharedFolderViewMode.detailed:
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: documents.length,
          itemBuilder: (context, index) =>
              _buildDocumentDetailedItem(documents[index]),
        );
    }
  }

  Widget _buildDocumentGridItem(Document document, int columns) {
    final iconData = _getFileIconData(document.type);
    final color = _getFileColor(document.type);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _handleDocumentDoubleTap(document),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(columns == 2 ? 12 : 8),
                decoration: BoxDecoration(
                  color: color.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  iconData,
                  color: color,
                  size: columns == 2 ? 26 : 18,
                ),
              ),
              const SizedBox(height: 6),
              Flexible(
                child: Text(
                  document.name,
                  style: TextStyle(
                    fontSize: columns == 2 ? 11 : 9,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: columns == 2 ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                document.type,
                style: TextStyle(
                  fontSize: columns == 2 ? 9 : 8,
                  color: Colors.grey.shade600,
                ),
              ),
              if (columns == 2) ...[
                const SizedBox(height: 2),
                Text(
                  _formatDateDDMMYYYY(document.uploadDate),
                  style: TextStyle(fontSize: 8, color: Colors.grey.shade500),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentCompactItem(Document document) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        elevation: 0.5,
        child: InkWell(
          onTap: () => _handleDocumentDoubleTap(document),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey.shade100, width: 1),
            ),
            child: Row(
              children: [
                Icon(
                  _getFileIconData(document.type),
                  color: _getFileColor(document.type),
                  size: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    document.name,
                    style: const TextStyle(fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatDateDDMMYYYY(document.uploadDate),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentDetailedItem(Document document) {
    final iconData = _getFileIconData(document.type);
    final color = _getFileColor(document.type);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _handleDocumentDoubleTap(document),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withAlpha(20),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(iconData, color: color, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          document.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.person,
                                  size: 12,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    _displayOwner(document),
                                    style: TextStyle(
                                      fontSize: 11,
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
                                  size: 12,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    document.folder,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.calendar_today,
                                  size: 12,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _formatDateDDMMYYYY(document.uploadDate),
                                  style: TextStyle(
                                    fontSize: 11,
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
                                  size: 12,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  document.classification,
                                  style: TextStyle(
                                    fontSize: 11,
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
                    onPressed: () => _showDocumentActions(document),
                    icon: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.more_vert,
                        size: 16,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _handleDocumentDoubleTap(document),
                      icon: Icon(
                        Icons.visibility,
                        size: 14,
                        color: Colors.purple,
                      ),
                      label: Text(
                        'View',
                        style: TextStyle(fontSize: 12, color: Colors.purple),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.purple),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showDocumentVersions(document),
                      icon: Icon(Icons.history, size: 14, color: Colors.blue),
                      label: Text(
                        'Versions',
                        style: TextStyle(fontSize: 12, color: Colors.blue),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.blue),
                        padding: const EdgeInsets.symmetric(vertical: 6),
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

  // ============ FEATURE 3: FILE TYPE FILTER ============
  Widget _buildFileTypeFilter() {
    return PopupMenuButton<String>(
      tooltip: 'Filter by File Type',
      icon: Icon(
        Icons.filter_alt,
        color: _selectedFileType != 'All' ? Colors.blue : Colors.indigo,
        size: 24,
      ),
      onSelected: (String type) {
        setState(() {
          _selectedFileType = type;
        });
      },
      itemBuilder: (context) => _availableFileTypes.map((type) {
        return PopupMenuItem(
          value: type,
          child: Row(
            children: [
              if (type == 'All')
                Icon(Icons.all_inclusive, color: Colors.grey)
              else
                Icon(_getFileIconData(type), color: _getFileColor(type)),
              SizedBox(width: 8),
              Text(type),
              if (_selectedFileType == type)
                Icon(Icons.check, color: Colors.green, size: 16),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFileTypeBadge() {
    if (_selectedFileType == 'All') return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade200, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getFileIconData(_selectedFileType),
            size: 14,
            color: _getFileColor(_selectedFileType),
          ),
          const SizedBox(width: 6),
          Text(
            _selectedFileType,
            style: TextStyle(fontSize: 12, color: Colors.blue.shade800),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () {
              setState(() {
                _selectedFileType = 'All';
              });
            },
            child: Icon(Icons.close, size: 14, color: Colors.blue.shade800),
          ),
        ],
      ),
    );
  }

  // ============ SUBFOLDERS ============
  Widget _buildSubfoldersSection() {
    if (_subfolders.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.folder, color: Colors.amber),
              const SizedBox(width: 8),
              const Text(
                'Shared Folders',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _subfolders.length.toString(),
                  style: const TextStyle(fontSize: 12, color: Colors.amber),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _subfolders.length,
            itemBuilder: (context, index) =>
                _buildSubfolderCard(_subfolders[index]),
          ),
        ],
      ),
    );
  }

  Widget _buildSubfolderCard(Map<String, dynamic> folder) {
    final sharedBy = _resolveSharedBy(folder);
    final folderId = folder['id']?.toString() ?? '';
    final cachedCount = _subfolderItemCounts[folderId];
    final apiCount = folder['item_count'] is Map
        ? (folder['item_count'] as Map)['total'] ?? 0
        : 0;
    final int? itemCount = cachedCount == null
        ? apiCount
        : (cachedCount >= 0 ? cachedCount : null);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _navigateToSubfolder(folder),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.folder,
                  color: Colors.amber.shade800,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      folder['name']?.toString() ?? 'Unnamed Folder',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Shared by: $sharedBy',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.description,
                          size: 12,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          itemCount == null
                              ? 'Loading...'
                              : '$itemCount item${itemCount != 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.calendar_today,
                          size: 12,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDate(folder['created_at']),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'download') {
                    _downloadFolderFiles(folder);
                  } else if (v == 'download_zip') {
                    _downloadFolderZip(folder);
                  }
                },
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
                        Text('Download as ZIP'),
                      ],
                    ),
                  ),
                ],
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.more_vert, color: Colors.grey, size: 20),
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.indigo),
            ],
          ),
        ),
      ),
    );
  }

  // ============ HELPER METHODS ============
  Widget _buildDetailRow(String label, String value, IconData iconData) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(iconData, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label: ',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

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
      return date.toString();
    }
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'Unknown';
    try {
      final dateStr = date.toString();
      if (dateStr.contains('T')) {
        final dateTime = DateTime.parse(dateStr);
        final now = DateTime.now();
        final difference = now.difference(dateTime);

        if (difference.inDays == 0) return 'Today';
        if (difference.inDays == 1) return 'Yesterday';
        if (difference.inDays < 7) return '${difference.inDays} days ago';
        return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
      }
      return dateStr;
    } catch (e) {
      return date.toString();
    }
  }

  IconData _getFileIconData(String type) {
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

  Icon _getFileIcon(String type, double size) {
    return Icon(_getFileIconData(type), color: _getFileColor(type), size: size);
  }

  String _formatFileSize(String size) {
    try {
      final cleanSize = size.replaceAll(RegExp(r'[^0-9]'), '');
      final bytes = int.tryParse(cleanSize) ?? 0;
      if (bytes == 0) return '0 B';
      if (bytes < 1024) return '$bytes B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
      if (bytes < 1024 * 1024 * 1024)
        return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } catch (e) {
      return size;
    }
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.indigo),
          SizedBox(height: 16),
          Text('Loading shared folder...'),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 80, color: Colors.red),
            const SizedBox(height: 20),
            const Text(
              'Failed to Load',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _errorMessage,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loadSharedFolderContents,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadingBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: Colors.green[50],
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Downloading document...',
              style: TextStyle(
                color: const Color.fromARGB(255, 57, 170, 57),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showDownloadRestrictedPopup(Document document) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.download_outlined, size: 48, color: Colors.blue),
        title: const Text('Download Document'),
        content: const Text(
          'Download requires approval. Please request access from the document owner.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final service = DownloadRequestsService();
              final result = await service.createRequest(
                documentId: document.id,
                reason: 'Requesting download access',
              );
              if (!mounted) return;
              _showSnackBar(
                result['success'] == true
                    ? 'Download request submitted'
                    : (result['message'] ?? 'Request failed'),
                result['success'] == true ? Colors.green : Colors.red,
              );
            },
            child: const Text('Request Download'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredDocs = _filterDocuments();

    return DismissKeyboard(child: Scaffold(
      appBar: AppBar(
   
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.folderName,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            if (widget.userName != null)
              Text(
                'Shared by: ${widget.userName}',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
          ],
        ),
        backgroundColor: Colors.indigo.shade700,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loadSharedFolderContents,
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search and filters section
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade100,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
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
                          onChanged: (value) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Search in shared folder...',
                            hintStyle: TextStyle(color: Colors.grey.shade600),
                            prefixIcon: const Icon(
                              Icons.search,
                              color: Colors.indigo,
                            ),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(
                                      Icons.clear,
                                      color: Colors.grey,
                                    ),
                                    onPressed: _clearSearch,
                                  )
                                : null,
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildFileTypeFilter(),
                    const SizedBox(width: 8),
                    _buildLayoutSelector(),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '${filteredDocs.length} document${filteredDocs.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                    _buildFileTypeBadge(),
                    const Spacer(),
                    if (_subfolders.isNotEmpty)
                      Text(
                        '${_subfolders.length} folder${_subfolders.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Loading/Error/Content
          Expanded(
            child: _isLoading
                ? _buildLoading()
                : _hasError
                ? _buildError()
                : RefreshIndicator(
                    onRefresh: _loadSharedFolderContents,
                    color: Colors.indigo,
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          if (_isDownloading) _buildDownloadingBanner(),
                          _buildSubfoldersSection(),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.insert_drive_file,
                                      color: Colors.indigo,
                                      size: 24,
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Shared Documents',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.indigo.shade100,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        filteredDocs.length.toString(),
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                filteredDocs.isEmpty
                                    ? _buildEmptyState()
                                    : _buildDocumentsContent(filteredDocs),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    ));
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _subfolders.isEmpty ? Icons.folder_off : Icons.insert_drive_file,
              size: 80,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 20),
            Text(
              _subfolders.isEmpty ? 'Empty Folder' : 'No Documents',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _subfolders.isEmpty
                  ? 'This shared folder is empty'
                  : 'No documents shared in this folder',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
