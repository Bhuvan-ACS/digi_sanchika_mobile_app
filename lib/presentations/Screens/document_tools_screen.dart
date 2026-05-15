import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:digi_sanchika/models/document.dart';
import 'package:digi_sanchika/models/ocr_status.dart';
import 'package:digi_sanchika/models/conversion_status.dart';
import 'package:digi_sanchika/models/semantic_index_status.dart';
import 'package:digi_sanchika/models/version_comment.dart';
import 'package:digi_sanchika/services/ocr_service.dart';
import 'package:digi_sanchika/services/conversion_service.dart';
import 'package:digi_sanchika/services/semantic_search_service.dart';
import 'package:digi_sanchika/services/version_comments_service.dart';
import 'package:digi_sanchika/services/versions_service.dart';

class DocumentToolsScreen extends StatefulWidget {
  final Document document;

  const DocumentToolsScreen({super.key, required this.document});

  @override
  State<DocumentToolsScreen> createState() => _DocumentToolsScreenState();
}

class _DocumentToolsScreenState extends State<DocumentToolsScreen> {
  final OcrService _ocrService = OcrService();
  final ConversionService _conversionService = ConversionService();
  final SemanticSearchService _semanticService = SemanticSearchService();
  final VersionCommentsService _commentsService = VersionCommentsService();

  bool _loadingOcr = false;
  bool _loadingConversion = false;
  bool _loadingSemantic = false;
  bool _loadingComments = false;

  OcrStatus? _ocrStatus;
  ConversionStatus? _conversionStatus;
  SemanticIndexStatus? _semanticStatus;
  List<VersionComment> _comments = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadOcrStatus(),
      _loadConversionStatus(),
      _loadSemanticStatus(),
      _loadComments(),
    ]);
  }

  Future<void> _loadOcrStatus() async {
    setState(() => _loadingOcr = true);
    try {
      final status = await _ocrService.getStatus(widget.document.id);
      if (mounted) {
        setState(() => _ocrStatus = status);
      }
    } finally {
      if (mounted) {
        setState(() => _loadingOcr = false);
      }
    }
  }

  Future<void> _loadConversionStatus() async {
    setState(() => _loadingConversion = true);
    try {
      final status = await _conversionService.getStatus(widget.document.id);
      if (mounted) {
        setState(() => _conversionStatus = status);
      }
    } finally {
      if (mounted) {
        setState(() => _loadingConversion = false);
      }
    }
  }

  Future<void> _loadSemanticStatus() async {
    setState(() => _loadingSemantic = true);
    try {
      final status = await _semanticService.getIndexStatus(widget.document.id);
      if (mounted) {
        setState(() => _semanticStatus = status);
      }
    } finally {
      if (mounted) {
        setState(() => _loadingSemantic = false);
      }
    }
  }

  Future<void> _loadComments() async {
    setState(() => _loadingComments = true);
    try {
      String versionTo = 'latest';
      try {
        final versions = await VersionsService().listVersions(widget.document.id);
        if (versions.isNotEmpty) {
          int parseVersion(String v) => int.tryParse(v.trim()) ?? -1;
          versions.sort((a, b) => parseVersion(b.version).compareTo(parseVersion(a.version)));
          final top = versions.first.version.trim();
          if (top.isNotEmpty) versionTo = top;
        }
      } catch (_) {}

      final items = await _commentsService.listComments(
        widget.document.id,
        versionTo: versionTo,
      );
      if (mounted) {
        setState(() => _comments = items);
      }
    } finally {
      if (mounted) {
        setState(() => _loadingComments = false);
      }
    }
  }

  Future<void> _showOcrText() async {
    try {
      final text = await _ocrService.getText(widget.document.id);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('OCR Text'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Text(text?.isNotEmpty == true ? text! : 'No OCR text found'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showSnack('Failed to load OCR text: $e', isError: true);
    }
  }

  Future<void> _queueOcr() async {
    final ok = await _ocrService.queue(widget.document.id);
    _showSnack(ok ? 'OCR queued' : 'Failed to queue OCR', isError: !ok);
    _loadOcrStatus();
  }

  Future<void> _retryOcr() async {
    final ok = await _ocrService.retry(widget.document.id);
    _showSnack(ok ? 'OCR retry started' : 'Failed to retry OCR', isError: !ok);
    _loadOcrStatus();
  }

  Future<void> _requestConversion() async {
    final ok = await _conversionService.requestConversion(widget.document.id);
    _showSnack(
      ok ? 'Conversion requested' : 'Failed to request conversion',
      isError: !ok,
    );
    _loadConversionStatus();
  }

  Future<void> _downloadConverted() async {
    if (!mounted) return;
    final formatController = TextEditingController(text: 'pdf');
    String? format;
    try {
      format = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Download Converted File'),
          content: TextField(
            controller: formatController,
            decoration: const InputDecoration(
              labelText: 'Format (e.g., pdf, docx)',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, formatController.text),
              child: const Text('Download'),
            ),
          ],
        ),
      );
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        formatController.dispose();
      });
    }

    if (format == null || format.trim().isEmpty) return;
    final safeFormat = format.trim().toLowerCase();

    try {
      final result = await _conversionService.downloadConverted(
        widget.document.id,
        safeFormat,
      );
      if (result['success'] == true && result['data'] != null) {
        final bytes = result['data'] as List<int>;
        final tempDir = await getTemporaryDirectory();
        final safeName = widget.document.name.replaceAll(
          RegExp(r'[^\w\.\-]'),
          '_',
        );
        final filePath =
            '${tempDir.path}/${safeName}_converted.$safeFormat';
        final file = File(filePath);
        await file.writeAsBytes(bytes);
        await OpenFilex.open(file.path);
        _showSnack('Converted file downloaded');
      } else {
        _showSnack(
          result['message']?.toString() ?? 'Download failed',
          isError: true,
        );
      }
    } catch (e) {
      _showSnack('Download failed: $e', isError: true);
    }
  }

  Future<void> _retryConversion() async {
    final ok = await _conversionService.retryConversion(widget.document.id);
    _showSnack(
      ok ? 'Conversion retry started' : 'Failed to retry conversion',
      isError: !ok,
    );
    _loadConversionStatus();
  }

  Future<void> _rerunSemantic() async {
    final ok = await _semanticService.rerunIndexing(widget.document.id);
    _showSnack(
      ok ? 'Semantic indexing started' : 'Failed to re-run indexing',
      isError: !ok,
    );
    _loadSemanticStatus();
  }

  Future<void> _addComment() async {
    if (!mounted) return;
    final versionController = TextEditingController();
    final commentController = TextEditingController();
    bool? result;
    try {
      result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Add Version Comment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: versionController,
                decoration: const InputDecoration(labelText: 'Version'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: commentController,
                decoration: const InputDecoration(labelText: 'Comment'),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Add'),
            ),
          ],
        ),
      );
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        versionController.dispose();
        commentController.dispose();
      });
    }

    if (result != true) return;
    final version = versionController.text.trim();
    final comment = commentController.text.trim();
    if (version.isEmpty || comment.isEmpty) {
      _showSnack('Version and comment are required', isError: true);
      return;
    }

    final ok = await _commentsService.addComment(
      documentId: widget.document.id,
      version: version,
      comment: comment,
    );
    _showSnack(ok ? 'Comment added' : 'Failed to add comment', isError: !ok);
    _loadComments();
  }

  Future<void> _resolveComment(String id) async {
    final ok = await _commentsService.resolveComment(id);
    _showSnack(ok ? 'Comment resolved' : 'Failed to resolve', isError: !ok);
    _loadComments();
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required Widget child,
  }) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Document Tools'),
        actions: [
          IconButton(
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection(
            title: 'OCR',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _loadingOcr
                      ? 'Loading OCR status...'
                      : 'Status: ${_ocrStatus?.status ?? 'unknown'}',
                ),
                if (_ocrStatus?.message?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_ocrStatus!.message!),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    ElevatedButton(
                      onPressed: _loadingOcr ? null : _loadOcrStatus,
                      child: const Text('Refresh'),
                    ),
                    OutlinedButton(
                      onPressed: _queueOcr,
                      child: const Text('Queue OCR'),
                    ),
                    OutlinedButton(
                      onPressed: _retryOcr,
                      child: const Text('Retry OCR'),
                    ),
                    TextButton(
                      onPressed: _showOcrText,
                      child: const Text('View Text'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _buildSection(
            title: 'Conversion',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _loadingConversion
                      ? 'Loading conversion status...'
                      : 'Status: ${_conversionStatus?.status ?? 'unknown'}',
                ),
                if (_conversionStatus?.message?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_conversionStatus!.message!),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    ElevatedButton(
                      onPressed: _loadingConversion ? null : _loadConversionStatus,
                      child: const Text('Refresh'),
                    ),
                    OutlinedButton(
                      onPressed: _requestConversion,
                      child: const Text('Request'),
                    ),
                    OutlinedButton(
                      onPressed: _retryConversion,
                      child: const Text('Retry'),
                    ),
                    TextButton(
                      onPressed: _downloadConverted,
                      child: const Text('Download'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _buildSection(
            title: 'Semantic Index',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _loadingSemantic
                      ? 'Loading semantic status...'
                      : 'Status: ${_semanticStatus?.status ?? 'unknown'}',
                ),
                if (_semanticStatus?.message?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_semanticStatus!.message!),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    ElevatedButton(
                      onPressed: _loadingSemantic ? null : _loadSemanticStatus,
                      child: const Text('Refresh'),
                    ),
                    OutlinedButton(
                      onPressed: _rerunSemantic,
                      child: const Text('Re-run Indexing'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _buildSection(
            title: 'Version Comments',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_loadingComments)
                  const Text('Loading comments...')
                else if (_comments.isEmpty)
                  const Text('No comments yet')
                else
                  ..._comments.map(
                    (comment) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Version ${comment.version}'),
                      subtitle: Text(comment.comment),
                      trailing: IconButton(
                        icon: const Icon(Icons.check_circle, color: Colors.green),
                        onPressed: () => _resolveComment(comment.id),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ElevatedButton(
                      onPressed: _loadingComments ? null : _loadComments,
                      child: const Text('Refresh'),
                    ),
                    OutlinedButton(
                      onPressed: _addComment,
                      child: const Text('Add Comment'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
