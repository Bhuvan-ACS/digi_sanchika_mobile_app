// lib/presentations/screens/document_open_options.dart
// ignore_for_file: unused_element

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:digi_sanchika/models/document.dart';
import 'package:digi_sanchika/presentations/screens/document_preview_screen.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:digi_sanchika/services/download_access_service.dart';
import 'package:digi_sanchika/services/download_requests_service.dart';

class DocumentOpenOptionsDialog extends StatefulWidget {
  final Document document;
  final String fileType;

  const DocumentOpenOptionsDialog({
    super.key,
    required this.document,
    required this.fileType,
  });

  @override
  State<DocumentOpenOptionsDialog> createState() =>
      _DocumentOpenOptionsDialogState();
}

class _DocumentOpenOptionsDialogState extends State<DocumentOpenOptionsDialog> {
  @override
  Widget build(BuildContext context) {
    final isPdf = widget.fileType.toUpperCase() == 'PDF';

    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          _buildFileInfo(),
          const SizedBox(height: 24),
          isPdf ? _buildPdfOptions() : _buildOtherOptions(),
          const SizedBox(height: 16),
          _buildCloseButton(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.indigo.shade50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.open_in_new, color: Colors.indigo, size: 24),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Open Document',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildFileInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.document.name,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          '${widget.fileType} • ${widget.document.size}',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildPdfOptions() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _openWithBuiltInViewer(),
            icon: const Icon(Icons.picture_as_pdf, size: 20),
            label: const Text('Open in Built-in PDF Viewer'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Or open with:', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _openExternalApp(context),
            icon: const Icon(Icons.open_in_new, color: Colors.green),
            label: const Text('Open with Other Apps'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: Colors.green.shade400),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOtherOptions() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _openExternalApp(context),
            icon: Icon(_getFileIcon(widget.fileType), size: 20),
            label: Text('Open ${widget.fileType} File'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCloseButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () => Navigator.pop(context),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.grey.shade700,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: const Text('Cancel'),
      ),
    );
  }

  IconData _getFileIcon(String fileType) {
    final type = fileType.toUpperCase();
    switch (type) {
      case 'PDF':
        return Icons.picture_as_pdf;
      case 'DOCX':
      case 'DOC':
        return Icons.description;
      case 'XLSX':
      case 'XLS':
        return Icons.table_chart;
      case 'PPTX':
      case 'PPT':
        return Icons.slideshow;
      case 'TXT':
        return Icons.text_fields;
      case 'JPG':
      case 'JPEG':
      case 'PNG':
      case 'GIF':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  Future<void> _openWithBuiltInViewer() async {
    Navigator.pop(context);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DocumentPreviewScreen(
          document: widget.document,
          fileType: widget.fileType,
        ),
      ),
    );
  }

  Future<void> _openExternalApp(BuildContext context) async {
    if (kDebugMode) {
      print('🟢 Opening external app for: ${widget.document.name}');
    }
    if (kDebugMode) {
      print('📄 File type: ${widget.fileType}');
    }

    // Close dialog immediately
    Navigator.pop(context);

    // Show opening message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Opening ${widget.document.name}...'),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 2),
      ),
    );

    try {
      // 1. First, try to download the file from backend
      if (kDebugMode) {
        print('📥 Downloading file from backend...');
      }
      final downloadResult = await DownloadAccessService.downloadBytesWithAccess(
        documentId: widget.document.id,
      );

      if (downloadResult['requiresApproval'] == true) {
        final reqService = DownloadRequestsService();
        final reqResult = await reqService.createRequest(
          documentId: widget.document.id,
          reason: 'Need offline copy',
        );
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              reqResult['success'] == true
                  ? 'Download request sent for approval'
                  : (reqResult['message'] ?? 'Download request failed'),
            ),
            backgroundColor:
                reqResult['success'] == true ? Colors.orange : Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }

      if (downloadResult['success'] == true && downloadResult['bytes'] != null) {
        final bytes = downloadResult['bytes'] as List<int>;
        if (kDebugMode) {
          print('✅ Downloaded ${bytes.length} bytes');
        }

        // 2. Save to a proper location with correct filename
        final tempDir = await getTemporaryDirectory();
        final downloadsDir = Directory(
          '${tempDir.path}/digi_sanchika_downloads',
        );
        if (!await downloadsDir.exists()) {
          await downloadsDir.create(recursive: true);
        }

        // Get original filename or use document name
        final originalFilename =
            downloadResult['filename'] ?? widget.document.name;
        final safeFilename = originalFilename.replaceAll(
          RegExp(r'[<>:"/\\|?*]'),
          '_',
        );
        final filePath = '${downloadsDir.path}/$safeFilename';

        if (kDebugMode) {
          print('💾 Saving to: $filePath');
        }

        // 3. Write file AS BINARY (not text!)
        await File(filePath).writeAsBytes(bytes);

        // 4. Verify file was saved correctly
        final savedFile = File(filePath);
        final exists = await savedFile.exists();
        final fileSize = await savedFile.length();

        if (kDebugMode) {
          print('📊 File saved - Exists: $exists, Size: $fileSize bytes');
        }

        if (exists && fileSize > 0) {
          // 5. Open with open_filex
          if (kDebugMode) {
            print('🚀 Opening with OpenFilex...');
          }
          final result = await OpenFilex.open(filePath);
          if (kDebugMode) {
            print(
              '📱 OpenFilex result: ${result.type}, Message: ${result.message}',
            );
          }

          if (result.type == ResultType.done) {
            // ignore: use_build_context_synchronously
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('File opened successfully'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          } else if (result.type == ResultType.noAppToOpen) {
            // ignore: use_build_context_synchronously
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('No app found to open this file'),
                backgroundColor: Colors.orange,
                action: SnackBarAction(
                  label: 'Save File',
                  onPressed: () =>
                      _saveFileToDownloads(bytes, originalFilename, context),
                ),
                duration: const Duration(seconds: 4),
              ),
            );
          } else {
            // ignore: use_build_context_synchronously
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error: ${result.message}'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        } else {
          if (kDebugMode) {
            print('❌ File not saved properly');
          }
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to save file'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else {
        if (kDebugMode) {
          print('❌ Download failed: ${downloadResult['error']}');
        }
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: ${downloadResult['error']}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error: $e');
      }
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // Helper method to save file to Downloads folder
  Future<void> _saveFileToDownloads(
    List<int> bytes,
    String filename,
    BuildContext context,
  ) async {
    try {
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir != null) {
        final filePath = '${downloadsDir.path}/$filename';
        await File(filePath).writeAsBytes(bytes);

        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File saved to Downloads: $filename'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

 

 

 



  @override
  void dispose() {
    super.dispose();
  }
}
