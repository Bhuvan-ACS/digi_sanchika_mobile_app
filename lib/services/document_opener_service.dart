// lib/services/document_opener_service.dart
// import 'dart:async';
// import 'dart:io';
// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';
// import 'package:path/path.dart' as path;
// import 'package:path_provider/path_provider.dart';
// import 'package:open_filex/open_filex.dart';
// import 'package:digi_sanchika/models/document.dart';
// import 'package:digi_sanchika/services/api_service.dart';
// import 'package:digi_sanchika/services/my_documents_service.dart';
// import 'package:digi_sanchika/local_storage.dart';
// import 'package:digi_sanchika/presentations/screens/document_open_options.dart';

// /// Service to handle document opening with double-tap
// class DocumentOpenerService {
//   static final DocumentOpenerService _instance =
//       DocumentOpenerService._internal();
//   factory DocumentOpenerService() => _instance;
//   DocumentOpenerService._internal();

//   // Double-tap tracking
//   Document? _lastTappedDocument;
//   DateTime? _lastTapTime;
//   static const int _doubleTapThreshold = 350; // milliseconds

//   /// Check if double-tap
//   bool isDoubleTap(Document document) {
//     final now = DateTime.now();
//     final isSameDoc = _lastTappedDocument?.id == document.id;
//     final isWithinThreshold =
//         _lastTapTime != null &&
//         now.difference(_lastTapTime!).inMilliseconds < _doubleTapThreshold;

//     _lastTappedDocument = document;
//     _lastTapTime = now;

//     return isSameDoc && isWithinThreshold;
//   }

//   /// Extract file type (matches your existing method)
//   String getFileType(Document document) {
//     final filename = document.name.toLowerCase();
//     final ext = path.extension(filename);

//     switch (ext) {
//       case '.pdf':
//         return 'PDF';
//       case '.doc':
//       case '.docx':
//         return 'DOCX';
//       case '.xls':
//       case '.xlsx':
//         return 'XLSX';
//       case '.ppt':
//       case '.pptx':
//         return 'PPTX';
//       case '.txt':
//         return 'TXT';
//       default:
//         return ext.replaceAll('.', '').toUpperCase();
//     }
//   }

//   /// Check if file exists locally
//   Future<bool> isFileLocal(Document document) async {
//     try {
//       // Check your LocalStorageService
//       final localDocs = await LocalStorageService.loadDocuments();
//       return localDocs.any((doc) => doc.id == document.id);
//     } catch (e) {
//       return false;
//     }
//   }

//   /// Download file using your existing service
//   Future<File?> downloadDocument(Document document) async {
//     try {
//       if (!ApiService.isConnected) return null;

//       final result = await MyDocumentsService.downloadDocument(document.id);

//       if (result['success'] == true && result['data'] != null) {
//         final tempDir = await getTemporaryDirectory();
//         final safeName = document.name.replaceAll(RegExp(r'[^\w\.]'), '_');
//         final filePath = '${tempDir.path}/$safeName';
//         final file = File(filePath);

//         await file.writeAsBytes(result['data'] as List<int>);
//         return file;
//       }
//       return null;
//     } catch (e) {
//       if (kDebugMode) {
//         print('Download error: $e');
//       }
//       return null;
//     }
//   }

//   /// Open a specific version of a document
//   Future<void> openDocumentVersion({
//     required BuildContext context,
//     required String documentId,
//     required String versionNumber,
//     required String originalFileName,
//   }) async {
//     try {
//       // Show loading indicator
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Row(
//             children: [
//               const SizedBox(
//                 width: 20,
//                 height: 20,
//                 child: CircularProgressIndicator(strokeWidth: 2),
//               ),
//               const SizedBox(width: 12),
//               Text('Downloading version $versionNumber...'),
//             ],
//           ),
//           duration: const Duration(seconds: 30), // Long duration for download
//         ),
//       );

//       // Download the specific version
//       final result = await MyDocumentsService.downloadDocumentVersion(
//         documentId: documentId,
//         versionNumber: versionNumber,
//       );

//       // Clear loading indicator
//       ScaffoldMessenger.of(context).hideCurrentSnackBar();

//       if (result['success'] == true) {
//         // Get directory for saving
//         final directory = await getTemporaryDirectory();

//         // Create filename with version number
//         String fileName = originalFileName;
//         if (result['filename'] != null) {
//           fileName = result['filename']!;
//         } else {
//           // Add version number to filename if not provided by server
//           final extIndex = originalFileName.lastIndexOf('.');
//           if (extIndex != -1) {
//             final name = originalFileName.substring(0, extIndex);
//             final ext = originalFileName.substring(extIndex);
//             fileName = '${name}_v$versionNumber$ext';
//           } else {
//             fileName = '${originalFileName}_v$versionNumber';
//           }
//         }

//         final filePath = '${directory.path}/$fileName';
//         final file = File(filePath);

//         // Save the file
//         await file.writeAsBytes(result['data'] as List<int>);

//         // Open the file
//         await _openFileWithFallback(context, filePath);
//       } else {
//         throw Exception(result['error'] ?? 'Failed to download version');
//       }
//     } catch (e) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Text('Failed to open version: $e'),
//           backgroundColor: Colors.red,
//         ),
//       );
//     }
//   }

//   /// Helper method to open file with fallback for Android
//   Future<void> _openFileWithFallback(
//     BuildContext context,
//     String filePath,
//   ) async {
//     try {
//       final uriToOpen = Platform.isAndroid
//           ? _getFileProviderUri(filePath)
//           : filePath;

//       if (kDebugMode) {
//         print('📂 Opening file: $uriToOpen');
//       }

//       final result = await OpenFilex.open(uriToOpen);

//       if (result.type != ResultType.done) {
//         if (kDebugMode) {
//           print('⚠ Could not open file automatically: ${result.message}');
//         }

//         // Try fallback
//         if (Platform.isAndroid) {
//           try {
//             await OpenFilex.open(filePath);
//           } catch (e) {
//             _showOpenError(context, result.message);
//           }
//         } else {
//           _showOpenError(context, result.message);
//         }
//       }
//     } catch (e) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Text('Could not open file: $e'),
//           backgroundColor: Colors.orange,
//         ),
//       );
//     }
//   }

//   /// Generate FileProvider URI for Android
//   String _getFileProviderUri(String filePath) {
//     if (Platform.isAndroid) {
//       try {
//         final file = File(filePath);
//         if (file.existsSync()) {
//           final fileName = file.path.split('/').last;
//           return 'content://com.example.digi_sanchika.fileprovider/files/$fileName';
//         }
//       } catch (e) {
//         if (kDebugMode) {
//           print('⚠ Error creating FileProvider URI: $e');
//         }
//       }
//     }
//     return filePath;
//   }

//   /// Show error when file cannot be opened
//   void _showOpenError(BuildContext context, String? message) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Text('Could not open file: ${message ?? 'Unknown error'}'),
//         backgroundColor: Colors.orange,
//       ),
//     );
//   }

//   /// Open document directly (without options dialog)
//   Future<void> openDocumentDirectly({
//     required BuildContext context,
//     required Document document,
//   }) async {
//     try {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Row(
//             children: [
//               const SizedBox(
//                 width: 20,
//                 height: 20,
//                 child: CircularProgressIndicator(strokeWidth: 2),
//               ),
//               const SizedBox(width: 12),
//               Text('Downloading ${document.name}...'),
//             ],
//           ),
//           duration: const Duration(seconds: 30),
//         ),
//       );

//       final result = await MyDocumentsService.downloadDocument(document.id);

//       ScaffoldMessenger.of(context).hideCurrentSnackBar();

//       if (result['success'] == true && result['data'] != null) {
//         final tempDir = await getTemporaryDirectory();
//         final safeName = document.name.replaceAll(RegExp(r'[^\w\.]'), '_');
//         final filePath = '${tempDir.path}/$safeName';
//         final file = File(filePath);

//         await file.writeAsBytes(result['data'] as List<int>);
//         await _openFileWithFallback(context, filePath);
//       } else {
//         throw Exception(result['error'] ?? 'Failed to download document');
//       }
//     } catch (e) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Text('Failed to open document: $e'),
//           backgroundColor: Colors.red,
//         ),
//       );
//     }
//   }

//   /// Main handler for double-tap
//   void handleDoubleTap({
//     required BuildContext context,
//     required Document document,
//   }) {
//     final fileType = getFileType(document);

//     // Show opening options
//     showModalBottomSheet(
//       context: context,
//       shape: const RoundedRectangleBorder(
//         borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
//       ),
//       isScrollControlled: true,
//       builder: (context) =>
//           DocumentOpenOptionsDialog(document: document, fileType: fileType),
//     );
//   }
// }
// lib/services/document_opener_service.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:digi_sanchika/models/document.dart';
import 'package:digi_sanchika/services/api_service.dart';
import 'package:digi_sanchika/services/my_documents_service.dart';
import 'package:digi_sanchika/presentations/screens/document_open_options.dart';
import 'package:digi_sanchika/presentations/screens/document_preview_screen.dart';

/// Service to handle document opening with double-tap
class DocumentOpenerService {
  static final DocumentOpenerService _instance =
      DocumentOpenerService._internal();
  factory DocumentOpenerService() => _instance;
  DocumentOpenerService._internal();

  // Double-tap tracking
  Document? _lastTappedDocument;
  DateTime? _lastTapTime;
  static const int _doubleTapThreshold = 350;

  /// Check if double-tap
  bool isDoubleTap(Document document) {
    final now = DateTime.now();
    final isSameDoc = _lastTappedDocument?.id == document.id;
    final isWithinThreshold =
        _lastTapTime != null &&
        now.difference(_lastTapTime!).inMilliseconds < _doubleTapThreshold;

    _lastTappedDocument = document;
    _lastTapTime = now;

    return isSameDoc && isWithinThreshold;
  }

  /// Extract file type with better extension detection
  String getFileType(Document document) {
    final filename = document.name.toLowerCase();
    final ext = path.extension(filename);

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
      case '.csv':
        return 'CSV';
      case '.jpg':
      case '.jpeg':
        return 'JPEG';
      case '.png':
        return 'PNG';
      case '.gif':
        return 'GIF';
      case '.bmp':
        return 'BMP';
      default:
        if (document.type.isNotEmpty) {
          return document.type.toUpperCase();
        }
        return ext.replaceAll('.', '').toUpperCase();
    }
  }

  /// Get safe file name for saving
  String _getSafeFileName(String originalName) {
    return originalName.replaceAll(RegExp(r'[^\w\.\-]'), '_');
  }

  /// Download document to cache - SIMPLIFIED VERSION
  Future<File?> _downloadToCache(Document document) async {
    try {
      if (!ApiService.isConnected) {
        throw Exception('No internet connection');
      }

      // Download from service
      final result = await MyDocumentsService.downloadDocument(document.id);

      if (result['success'] == true && result['data'] != null) {
        final tempDir = await getTemporaryDirectory();
        final safeName = _getSafeFileName(document.name);
        final filePath = '${tempDir.path}/$safeName';
        final file = File(filePath);

        await file.writeAsBytes(result['data'] as List<int>);

        if (kDebugMode) {
          print('✅ File downloaded to: $filePath');
          print('📁 File size: ${await file.length()} bytes');
        }

        return file;
      } else {
        throw Exception(result['error']?.toString() ?? 'Download failed');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Download error: $e');
      }
      return null;
    }
  }

  /// SIMPLIFIED METHOD FOR VIEW BUTTON - This is what you need
  Future<void> openDocumentDirectly({
    required BuildContext context,
    required Document document,
  }) async {
    bool loadingShown = false;
    bool loadingDismissed = false;
    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Text('Opening ${document.name}...'),
            ],
          ),
        ),
      );
      loadingShown = true;

      // Download file
      final file = await _downloadToCache(document);

      if (!context.mounted) return;

      // Close loading (only once)
      if (loadingShown && !loadingDismissed) {
        final navigator = Navigator.of(context, rootNavigator: true);
        if (navigator.canPop()) {
          navigator.pop();
        }
        loadingDismissed = true;
      }

      if (file == null || !await file.exists()) {
        throw Exception('File not found after download');
      }

      if (!context.mounted) return;

      // Open the file
      await _openFileDirectly(context, file);
    } catch (e) {
      if (!context.mounted) return;

      // Ensure loading dialog is closed (only once)
      if (loadingShown && !loadingDismissed) {
        final navigator = Navigator.of(context, rootNavigator: true);
        if (navigator.canPop()) {
          navigator.pop();
        }
        loadingDismissed = true;
      }

      _showErrorDialog(context, 'Cannot open file: ${e.toString()}');
    }
  }

  /// Open file directly without FileProvider complexities
  Future<void> _openFileDirectly(BuildContext context, File file) async {
    try {
      if (kDebugMode) {
        print('📂 Attempting to open: ${file.path}');
        print('📁 File exists: ${await file.exists()}');
      }

      if (!await file.exists()) {
        throw Exception('File does not exist');
      }

      // SIMPLIFIED: Just open the file directly
      final result = await OpenFilex.open(file.path);

      if (kDebugMode) {
        print('📂 Open result: ${result.type}');
        print('📂 Message: ${result.message}');
      }

      if (result.type != ResultType.done) {
        // Try alternative method
        if (!context.mounted) return;
        await _openFileAlternative(context, file);
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Open error: $e');
      }
      if (context.mounted) {
        _showErrorDialog(context, 'Could not open file: $e');
      }
    }
  }

  /// Alternative method for opening files
  Future<void> _openFileAlternative(BuildContext context, File file) async {
    try {
      if (Platform.isAndroid) {
        // For Android, try using intent
        final result = await OpenFilex.open(file.path);

        if (result.type == ResultType.done) {
          return;
        }

        // If still not working, show user options
        if (context.mounted) {
          _showOpenOptions(context, file);
        }
      } else {
        // For iOS/other platforms
        final result = await OpenFilex.open(file.path);

        if (result.type != ResultType.done && context.mounted) {
          _showOpenErrorDialog(
            context,
            path.basename(file.path),
            result.message,
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        _showErrorDialog(context, 'Failed to open: $e');
      }
    }
  }

  /// Show open options to user
  void _showOpenOptions(BuildContext context, File file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Open File'),
        content: Text('Choose an app to open: ${path.basename(file.path)}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              // Try again with file path
              await OpenFilex.open(file.path);
            },
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  /// Original method for double-tap (shows options dialog)
  void handleDoubleTap({
    required BuildContext context,
    required Document document,
  }) {
    final fileType = getFileType(document);

    // Show opening options dialog
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) =>
          DocumentOpenOptionsDialog(document: document, fileType: fileType),
    );
  }

  /// Standard in-app viewer (full screen).
  /// This is the behavior we want across the app: card tap and "View" should open the same viewer.
  void openViewer({required BuildContext context, required Document document}) {
    final fileType = getFileType(document);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            DocumentPreviewScreen(document: document, fileType: fileType),
      ),
    );
  }

  /// Backward compatible name used in many screens.
  /// We now standardize this to open the full-screen viewer.
  void openPreviewDialog({
    required BuildContext context,
    required Document document,
  }) {
    openViewer(context: context, document: document);
  }

  /// Show error dialog
  void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error Opening File'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Show open error dialog
  void _showOpenErrorDialog(
    BuildContext context,
    String fileName,
    String? message,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cannot Open File'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('File: $fileName'),
            const SizedBox(height: 8),
            Text('Error: ${message ?? 'Unknown error'}'),
            const SizedBox(height: 12),
            const Text(
              'You may need to install an app that can open this file type.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Keep your existing methods for backward compatibility
  Future<File?> downloadDocument(Document document) async {
    return _downloadToCache(document);
  }

  Future<void> openDocumentVersion({
    required BuildContext context,
    required String documentId,
    required String versionNumber,
    required String originalFileName,
  }) async {
    try {
      final ext = path.extension(originalFileName).replaceFirst('.', '');
      final fileType = ext.isNotEmpty ? ext : 'unknown';

      final doc = Document(
        id: documentId,
        name: originalFileName,
        type: fileType,
        size: '',
        keyword: '',
        uploadDate: '',
        owner: '',
        details: '',
        classification: '',
        allowDownload: false,
        sharingType: 'private',
        folder: '',
        path: originalFileName,
        fileType: fileType,
      );

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DocumentPreviewScreen(
            document: doc,
            fileType: fileType,
            versionNumber: versionNumber,
            versionFileName: originalFileName,
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open version: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
