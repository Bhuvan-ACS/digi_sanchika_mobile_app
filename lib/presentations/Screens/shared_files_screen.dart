// screens/shared_me.dart
// ignore: unused_import
// ignore_for_file: unused_field, unused_import, unnecessary_brace_in_string_interps, unused_element

import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:digi_sanchika/utils/app_fonts.dart';
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
import 'package:open_filex/open_filex.dart';
import 'package:digi_sanchika/services/document_opener_service.dart';
import 'package:digi_sanchika/presentations/Screens/shared_folder_screen.dart';
import 'package:digi_sanchika/widgets/dismiss_keyboard.dart';
import 'package:digi_sanchika/services/my_documents_service.dart';
import 'package:digi_sanchika/services/shared_folders_service.dart';
import 'package:digi_sanchika/services/download_requests_service.dart';
import 'package:digi_sanchika/widgets/share_access_sheet.dart';
import 'package:digi_sanchika/services/download_access_service.dart';
import 'package:digi_sanchika/services/shared_browse_service.dart';
import 'package:digi_sanchika/models/app_view_mode.dart';
import 'package:digi_sanchika/widgets/view_mode_popup_button.dart';
import 'package:digi_sanchika/widgets/download_feedback.dart';
import 'package:digi_sanchika/widgets/version_history_dialog.dart';
import 'package:digi_sanchika/widgets/responsive_page.dart';

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
  List<SharedFolder> _sharedFolders = [];
  bool _isLoading = true;
  bool _hasError = false;
  bool _isDownloading = false;
  String _errorMessage = '';

  // NEW: Layout mode and file type filter variables
  AppViewMode _currentViewMode = AppViewMode.list;
  bool _showFileTypeFilter = false;
  String _selectedFileType = 'All';
  List<String> _availableFileTypes = [
    'All',
  ]; // Will be populated from documents

  // NEW: Collapsible states for document cards
  Map<String, bool> _expandedStates = {};

  void _clearExpandedStates() {
    _expandedStates.clear();
  }

  // Stats
  int _totalDocuments = 0;
  int _totalFolders = 0;

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
 print("shared data $_filteredDocuments");
 _sharedFoldersService.fetchSharedFolders().then((folders) {
      print('Fetched ${folders.length} shared folders:');
      for (final folder in folders) {
        print(
          'Id: ${folder.id}, Name: ${folder.name}, Owner: ${folder.owner}, CreatedAt: ${folder.createdAt}, ExpiresAt: ${folder.expiresAt}, ItemCount: ${folder.itemCount}',
        );
      }
    }).catchError((e) {
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
        // Load from local storage
        _loadFromLocalStorage();
        return;
      }

      // Try to load from backend first
      final response = await _sharedService.fetchSharedDocuments();

      // Extract documents and folders from the response
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
        _totalDocuments = documents.length;
        _totalFolders = folders.length;
        _availableFileTypes = ['All', ...fileTypes];
        _isLoading = false;
      });
print('SharedFolder JSON: $json');
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

  /// Load data from local storage
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
          _filteredDocuments = localDocs;
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

  /// Filter documents based on search query and file type
  void _filterDocuments({String? searchQuery, String? fileType}) {
    final query = searchQuery ?? _searchController.text;
    final type = fileType ?? _selectedFileType;

    setState(() {
      _filteredDocuments = _sharedDocuments.where((doc) {
        // Apply file type filter
        final fileTypeMatch = type == 'All' || doc.type.toUpperCase() == type;

        // Apply search filter if query exists
        if (query.isEmpty) return fileTypeMatch;

        final lowercaseQuery = query.toLowerCase();
        return fileTypeMatch &&
            (doc.name.toLowerCase().contains(lowercaseQuery) ||
                (doc.owner.isNotEmpty &&
                    doc.owner.toLowerCase().contains(lowercaseQuery)) ||
                ((doc.sharedViaGroupName ?? '')
                    .toLowerCase()
                    .contains(lowercaseQuery)) ||
                ((doc.sharedByName ?? '')
                    .toLowerCase()
                    .contains(lowercaseQuery)) ||
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

  /// Get download directory (same as My Documents)
  Future<Directory> getDownloadDirectory() async {
    if (Platform.isAndroid) {
      return await getApplicationDocumentsDirectory();
    } else if (Platform.isIOS) {
      return await getApplicationDocumentsDirectory();
    }
    return Directory.current;
  }

  /// Get FileProvider URI for Android
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

  /// Download a document (with auto-open like My Documents)
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
            // Normalize new download flow response to existing code path.
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
          // Convert List<dynamic> to List<int>
          bytesToSave = fileData.cast<int>();
        } else if (fileData is String) {
          // Convert String to bytes
          bytesToSave = utf8.encode(fileData);
        } else {
          debugPrint(
            '❌ fileData is not List<int>, it is: ${fileData.runtimeType}',
          );
          throw Exception(
            'Invalid file data format. Expected List<int>, got ${fileData.runtimeType}',
          );
        }

        // Check if data is not empty
        if (bytesToSave.isEmpty) {
          throw Exception('Downloaded file data is empty (0 bytes)');
        }

        debugPrint('✅ Received ${bytesToSave.length} bytes of file data');

        final directory = await getDownloadDirectory();

        String filename = result['filename']?.toString() ?? document.name;

        // If filename is just a number (document ID), use the document name
        if (RegExp(r'^\d+$').hasMatch(filename) && document.name.isNotEmpty) {
          filename = document.name;
        }

        // Ensure correct file extension
        final docName = document.name;
        if (docName.isNotEmpty) {
          final extension = path.extension(docName);
          // If the filename doesn't have the same extension as the document name
          if (!filename.toLowerCase().endsWith(extension.toLowerCase()) &&
              extension.isNotEmpty) {
            // Remove any existing extension from filename and add the correct one
            final nameWithoutExt = path.withoutExtension(filename);
            filename = '$nameWithoutExt$extension';
          }
        }

        // Ensure .py files have correct extension
        if (document.type.toLowerCase() == 'py' &&
            !filename.toLowerCase().endsWith('.py')) {
          filename = '$filename.py';
        }

        // Also check if we need to add .pdf extension
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

          // Auto-open the downloaded file (same as My Documents)
          try {
            final uriToOpen = Platform.isAndroid
                ? _getFileProviderUri(filePath)
                : filePath;

            debugPrint('Opening with: $uriToOpen');

            final openResult = await OpenFilex.open(uriToOpen);

            if (openResult.type != ResultType.done) {
              debugPrint('⚠ Could not open file: ${openResult.message}');

              // Fallback: Try normal path
              if (Platform.isAndroid) {
                try {
                  await OpenFilex.open(filePath);
                } catch (e) {
                  debugPrint('⚠ Fallback also failed: $e');
                }
              }
              _showSnackBar(
                'File downloaded. Could not open automatically.',
                Colors.orange,
              );
            } else {
              debugPrint('File opened successfully');
            }
          } catch (e) {
            debugPrint('⚠ Error opening file: $e');
            _showSnackBar(
              'File downloaded. Use a compatible app to open it.',
              Colors.blue,
            );
          }
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

  /// Show text content of .py files
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
                Icon(_getFileIcon('py'), size: r.sp(24), color: _getFileColor('py')),
                SizedBox(width: r.p(12)),
                Expanded(child: Text(filename, overflow: TextOverflow.ellipsis)),
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
                  // Copy to clipboard
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

  /// Handle document double-tap
  void _handleDocumentDoubleTap(Document document) {
    _documentOpener.openPreviewDialog(context: context, document: document);
  }

  void _showDocumentActions(Document document) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(context.r.p(16))),
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

  /// Show document details
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
                  _buildDetailRow('File Type', document.type.toUpperCase(), r: r),
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
              // if (document.allowDownload)
              //   ElevatedButton(
              //     onPressed: () {
              //       Navigator.pop(context);
              //       _downloadDocument(document);
              //     },
              //     style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              //     child: Row(
              //       mainAxisSize: MainAxisSize.min,
              //       children: [
              //         Icon(Icons.download, size: r.sp(18)),
              //         SizedBox(width: r.p(6)),
              //         Text('Download'),
              //       ],
              //     ),
              //   ),
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

  String _formatDate(dynamic date) {
    try {
      return DateTime.parse(date.toString()).toString().split(' ')[0];
    } catch (e) {
      return date.toString();
    }
  }

  // Format date to DD-MM-YYYY (Same as Document Library)
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
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: r?.sp(14) ?? 14),
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

  // Helper method to build detail row WITH icons (for the new design)
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
            child: Text(
              label,
              style: w400_14Poppins(color: Colors.black87),
            ),
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

  /// Show shared folders dialog
  void _showSharedFolders() {
    showDialog(
      context: context,
      builder: (context) {
        final r = context.r;
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.folder_shared, color: Colors.indigo),
              SizedBox(width: r.p(10)),
              Text('Shared Folders (${_sharedFolders.length})'),
            ],
          ),
          content: _sharedFolders.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.folder_off, size: r.sp(60), color: Colors.grey),
                      SizedBox(height: r.p(10)),
                      const Text('No shared folders'),
                    ],
                  ),
                )
              : SizedBox(
                  width: double.maxFinite,
                  height: MediaQuery.of(context).size.height * 0.6,
                  child: ListView.builder(
                    itemCount: _sharedFolders.length,
                    itemBuilder: (context, index) {
                      final folder = _sharedFolders[index];
                      return Card(
                        margin: EdgeInsets.symmetric(vertical: r.p(4)),
                        child: ListTile(
                          leading: const Icon(Icons.folder, color: Colors.amber),
                          title: Text(
                            folder.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Owner: ${folder.owner}'),
                              Text('Created: ${folder.createdAt}'),
                              if (folder.itemCount >= 0)
                                Text('${folder.itemCount} item${folder.itemCount == 1 ? '' : 's'}'),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.arrow_forward),
                            onPressed: () {
                              Navigator.pop(context);
                              _openSharedFolder(folder);
                            },
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            _openSharedFolder(folder);
                          },
                        ),
                      );
                    },
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  /// Open a shared folder (navigate to FolderScreen)
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

  // ============ FEATURE 1: COLLAPSIBLE DOCUMENT CARDS ============

  // Build document item card with COLLAPSIBLE functionality
  Widget _buildDocumentCard(BuildContext context, Document document, int index,) {
    final r = context.r;
    final iconData = _getFileIcon(document.type);
    final color = _getFileColor(document.type);
print("document upload date: ${document.name} - ${document.uploadDate}");
    // Format the date to DD MM YYYY
    String formattedDate = _formatDateDDMMYYYY(document.uploadDate);
    String uniqueKey = document.id.isNotEmpty ? document.id : 'doc_$index';
    // '${document.id}_${document.name}_${document.uploadDate}_${document.type}';
    // Check if this specific document is expanded
    bool isExpanded = _expandedStates[uniqueKey] ?? false;

    return InkWell(
      onTap: () => _handleDocumentDoubleTap(document),
      borderRadius: BorderRadius.circular(r.p(12)),
      child: Card(
        margin: EdgeInsets.symmetric(horizontal: r.p(16), vertical: r.p(8)),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r.p(12))),
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
                    child: Icon(iconData, color: color, size: r.sp(32)),
                  ),
                  SizedBox(width: r.p(16)),
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
                                  height5,
                                      Text(
                          'Type: ${document.type} • $formattedDate',
                          style: w400_14Poppins(color: Colors.grey.shade700),
                        ),
                                ],
                              ),
                            ),
                            // COLLAPSIBLE EXPAND/COLLAPSE BUTTON
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  // Toggle only this specific document using its ID
                                  _expandedStates[uniqueKey] = !isExpanded;

                                  // debugPrint('Toggled document: $uniqueKey');
                                  // debugPrint(
                                  //   'New state: ${_expandedStates[uniqueKey]}',
                                  // );
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
                            // Vertical More Options Button
                            IconButton(
                              onPressed: () =>
                                  _showDocumentActions(document),
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

              // COLLAPSIBLE CONTENT SECTION
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
                      // Metadata details section
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
          Icon(Icons.schedule, size: r?.sp(16) ?? 16, color: Colors.grey.shade600),
          SizedBox(width: r?.p(12) ?? 12),
          SizedBox(
            width: r?.p(100) ?? 100,
            child: Text(
              "Expires in: ",
              style: w400_14Poppins(color: Colors.black87),
            ),
          ),
          SizedBox(width: r?.p(8) ?? 8),
          Expanded(
            child: Text(
              _getExpiryText(document.expiresAt),
              style: w400_14Poppins(color: _getExpiryColor(document.expiresAt)),
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

                      // ACTION BUTTONS ROW
                      Row(
                        children: [
                          // VIEW BUTTON
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

                          // VERSIONS BUTTON
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

                          SizedBox(width: r.p(8)),

                          // DOWNLOAD BUTTON (conditionally enabled)
                          // Expanded(
                          //   child: document.allowDownload
                          //       ? OutlinedButton.icon(
                          //           onPressed: () =>
                          //               _downloadDocument(document),
                          //           icon: Icon(Icons.download, size: r.sp(18)),
                          //           label: const Text('Download'),
                          //           style: OutlinedButton.styleFrom(
                          //             foregroundColor: Colors.green,
                          //             side: const BorderSide(
                          //               color: Colors.green,
                          //             ),
                          //             padding: EdgeInsets.symmetric(
                          //               vertical: r.p(10),
                          //             ),
                          //           ),
                          //         )
                          //       : ElevatedButton.icon(
                          //           onPressed: () =>
                          //               _showDownloadRestrictedPopup(context, document),
                          //           icon: Icon(
                          //             Icons.download,
                          //             size: r.sp(18),
                          //             color: Colors.grey.shade300,
                          //           ),
                          //           label: Text(
                          //             'Download',
                          //             style: TextStyle(
                          //               color: Colors.grey.shade300,
                          //             ),
                          //           ),
                          //           style: ElevatedButton.styleFrom(
                          //             backgroundColor: Colors.grey.shade200,
                          //             foregroundColor: Colors.grey.shade300,
                          //             padding: EdgeInsets.symmetric(
                          //               vertical: r.p(10),
                          //             ),
                          //             shape: RoundedRectangleBorder(
                          //               borderRadius: BorderRadius.circular(r.p(8)),
                          //             ),
                          //           ),
                          //         ),
                          // ),
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
    final difference = expiry.difference(now);

    // Already expired
    if (difference.isNegative) {
      return 'Expired';
    }

    // Less than 24 hours remaining
    if (difference.inHours < 24) {
      final hours =
          difference.inMinutes <= 60 ? 1 : difference.inHours + 1;

      return 'In $hours hour${hours > 1 ? 's' : ''}';
    }

    // Calculate remaining days
    final days = difference.inDays;

    if (days == 1) {
      return 'Tomorrow';
    }

    return 'In ${days + 1} days';
  } catch (e) {
    return 'No Expiry';
  }
}

Color _getExpiryColor(String? expiryDate) {
  if (expiryDate == null ||
      expiryDate.isEmpty ||
      expiryDate == 'No Expiry') {
    return Colors.grey;
  }

  try {
    final expiry = DateTime.parse(expiryDate);

    if (expiry.year >= 9999) {
      return Colors.grey;
    }

    final now = DateTime.now();
    final difference = expiry.difference(now);

    if (difference.isNegative) {
      return Colors.grey; // Expired
    }

    if (difference.inHours < 24) {
      return Colors.red; // In X hours
    }

    if (difference.inDays < 7) {
      return Colors.orange; // Tomorrow to 7 days
    }

    return Colors.green; // More than 7 days
  } catch (e) {
    return Colors.grey;
  }
}

  // ============ FEATURE 2: LAYOUT MODES ============

  /// Method to build layout selector
  Widget _buildLayoutSelector() {
    return ViewModePopupButton(
      value: _currentViewMode,
      onSelected: (mode) => setState(() => _currentViewMode = mode),
    );
  }

  /// Method to build documents content based on view mode
  Widget _buildDocumentsContent(List<Document> documents) {
    switch (_currentViewMode) {
      case AppViewMode.list:
        return ListView.builder(
          // shrinkWrap: true,
          // physics: const NeverScrollableScrollPhysics(),
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
          // shrinkWrap: true,
          // physics: const NeverScrollableScrollPhysics(),
          itemCount: documents.length,
          itemBuilder: (context, index) {
            return _buildDocumentDetailedItem(context, documents[index], index);
          },
        );
    }
  }

  // Grid view item
  Widget _buildDocumentGridItem(BuildContext context, Document document, int index, int columns) {
    final r = context.r;
    final iconData = _getFileIcon(document.type);
    final color = _getFileColor(document.type);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r.p(12))),
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
                padding: EdgeInsets.all(columns == 2 ? r.p(12) : r.p(8)),
                decoration: BoxDecoration(
                  color: color.withAlpha(20),
                  borderRadius: BorderRadius.circular(r.p(12)),
                ),
                child: Icon(
                  iconData,
                  color: color,
                  size: columns == 2 ? r.sp(26) : r.sp(18),
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
                  style: TextStyle(fontSize: r.sp(8), color: Colors.grey.shade500),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Compact view item
  Widget _buildDocumentCompactItem(BuildContext context, Document document, int index) {
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
            padding: EdgeInsets.symmetric(horizontal: r.p(12), vertical: r.p(10)),
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
                SizedBox(width: r.p(12)),
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
                  style: TextStyle(fontSize: r.sp(11), color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Detailed view item
  Widget _buildDocumentDetailedItem(BuildContext context, Document document, int index) {
    final r = context.r;
    final iconData = _getFileIcon(document.type);
    final color = _getFileColor(document.type);

    return Card(
      elevation: 2,
      margin: EdgeInsets.only(bottom: r.p(8)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r.p(12))),
      child: InkWell(
        onTap: () => _handleDocumentDoubleTap(document),
        borderRadius: BorderRadius.circular(r.p(12)),
        child: Container(
          padding: EdgeInsets.all(r.p(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.all(r.p(10)),
                    decoration: BoxDecoration(
                      color: color.withAlpha(20),
                      borderRadius: BorderRadius.circular(r.p(10)),
                    ),
                    child: Icon(iconData, color: color, size: r.sp(24)),
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
                    onPressed: () => _showDocumentActions(document),
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
                        style: TextStyle(fontSize: r.sp(12), color: Colors.purple),
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
                      icon: Icon(Icons.history, size: r.sp(14), color: Colors.blue),
                      label: Text(
                        'Versions',
                        style: TextStyle(fontSize: r.sp(12), color: Colors.blue),
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

  // ============ FEATURE 3: FILE TYPE FILTER ============

  /// Build file type filter dropdown
  Widget _buildFileTypeFilter(ResponsiveHelper r) {
    return PopupMenuButton<String>(
      tooltip: 'Filter by File Type',
      icon: Icon(
        Icons.filter_alt,
        color: _selectedFileType != 'All' ? Colors.blue : Colors.indigo,
        size: r.sp(24),
      ),
      onSelected: (String type) {
        setState(() {
          _selectedFileType = type;
          _filterDocuments(fileType: type);
        });
      },
      itemBuilder: (BuildContext context) {
        final r = context.r;
        return <PopupMenuEntry<String>>[
          for (String type in _availableFileTypes)
            PopupMenuItem<String>(
              value: type,
              child: Row(
                children: [
                  if (type == 'All')
                    Icon(Icons.all_inclusive, color: Colors.grey)
                  else
                    Icon(_getFileIcon(type), color: _getFileColor(type)),
                  SizedBox(width: r.p(8)),
                  Text(type),
                  if (_selectedFileType == type)
                    Icon(Icons.check, color: Colors.green, size: r.sp(16)),
                ],
              ),
            ),
        ];
      },
    );
  }

  /// Show file type filter badge
  Widget _buildFileTypeBadge(ResponsiveHelper r) {
    if (_selectedFileType == 'All') return const SizedBox.shrink();

    return Container(
      margin: EdgeInsets.only(left: r.p(8)),
      padding: EdgeInsets.symmetric(horizontal: r.p(10), vertical: r.p(4)),
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
            child: Icon(Icons.close, size: r.sp(14), color: Colors.blue.shade800),
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
          icon: Icon(Icons.download_outlined, size: r.sp(48), color: Colors.blue),
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
                    backgroundColor:
                        result['success'] == true ? Colors.green : Colors.red,
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

  /// Format file size
  String _formatFileSize(String size) {
    try {
      final cleanSize = size.replaceAll(RegExp(r'[^0-9]'), '');
      final bytes = int.tryParse(cleanSize) ?? 0;
      if (bytes == 0) return '0 B';
      if (bytes < 1024) return '$bytes B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
      if (bytes < 1024 * 1024 * 1024) {
        return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      }
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } catch (e) {
      debugPrint('Error formatting file size: $e for input: $size');
      return size;
    }
  }

  /// Build empty state widget
  Widget _buildEmptyState(ResponsiveHelper r) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _searchController.text.isEmpty
                ? Icons.people_outline
                : Icons.search_off,
            size: r.sp(80),
            color: Colors.grey.shade400,
          ),
          SizedBox(height: r.p(20)),
          Text(
            _searchController.text.isEmpty
                ? (_hasError ? 'Unable to Load Data' : 'No Shared Documents')
                : 'No Documents Found',
            style: TextStyle(
              fontSize: r.sp(20),
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: r.p(10)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: r.p(40)),
            child: Text(
              _hasError
                  ? _errorMessage
                  : _searchController.text.isEmpty
                  ? 'Documents and folders shared with you will appear here'
                  : 'No documents found for "${_searchController.text}"',
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
                backgroundColor: Colors.indigo,
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

  /// Show snackbar
  void _showSnackBar(String message, Color backgroundColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return DismissKeyboard(child: Scaffold(
     
      body: ResponsivePage(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            // Search and stats section
            Container(
              padding: EdgeInsets.all(r.p(16)),
              color: Colors.grey.shade50,
              child: Column(
                children: [
                // Search bar with filters
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
                          onChanged: (value) =>
                              _filterDocuments(searchQuery: value),
                          maxLines: 1,
                          decoration: InputDecoration(
                            hintText: 'Search documents, owners, keywords...',
                            hintStyle: TextStyle(color: Colors.grey.shade600),
                            prefixIcon: const Icon(
                              Icons.search,
                              color: Colors.indigo,
                            ),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    color: Colors.grey,
                                    onPressed: _clearSearch,
                                  )
                                : null,
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(r.p(12)),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: EdgeInsets.symmetric(
                              vertical: r.p(14),
                              horizontal: r.p(16),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: r.p(10)),
                    // File Type Filter
                    // _buildFileTypeFilter(),
                    // SizedBox(width: r.p(8)),
                    // Layout Selector
                    _buildLayoutSelector(),
                    SizedBox(width: r.p(12)),
                    // Folders button - Only show if needed
                  
                  ],
                ),
                SizedBox(height: r.p(8)),
                // Stats row with filter badge
                Row(
                  children: [
                    Text(
                      '${_filteredDocuments.length} document${_filteredDocuments.length == 1 ? '' : 's'}',
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

          // Loading/Downloading Banner
          if (_isDownloading) _buildDownloadingBanner(r),

          // Main Content Area
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
            )
          else if (_filteredDocuments.isEmpty)
            Expanded(child: _buildEmptyState(r))
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadSharedData,
                color: Colors.indigo,
                child: _buildDocumentsContent(_filteredDocuments),
              ),
            ),
        ],
      ),
    ),
    ));
  }

  /// Downloading banner widget
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
}
