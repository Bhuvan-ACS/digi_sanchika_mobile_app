// lib/presentations/screens/document_preview_screen.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

import 'package:digi_sanchika/models/document.dart';
import 'package:digi_sanchika/presentations/screens/document_open_options.dart';
import 'package:digi_sanchika/presentations/Screens/document_annotations_sheet.dart';
import 'package:digi_sanchika/presentations/Screens/document_comments_sheet.dart';
import 'package:digi_sanchika/services/api_client.dart';
import 'package:digi_sanchika/services/conversion_service.dart';
import 'package:digi_sanchika/services/versions_service.dart';

class DocumentPreviewScreen extends StatefulWidget {
  final Document document;
  final String fileType;
  final File? localFile;
  final String? versionNumber;
  final bool versionOriginal;
  final String? versionFileName;

  const DocumentPreviewScreen({
    super.key,
    required this.document,
    required this.fileType,
    this.localFile,
    this.versionNumber,
    this.versionOriginal = false,
    this.versionFileName,
  });

  @override
  State<DocumentPreviewScreen> createState() => _DocumentPreviewScreenState();
}

class _DocumentPreviewScreenState extends State<DocumentPreviewScreen> {
  PdfController? _pdfController;
  bool _isLoading = true;
  bool _isRetrying = false;
  String _errorMessage = '';
  String? _conversionStatus;
  String _textContent = '';
  File? _binaryFile;
  List<List<String>> _csvRows = [];

  void _dlog(String message) {
    if (!kDebugMode) return;
    print('[Preview][${widget.document.id}] $message');
  }

  static Dio _rawDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        followRedirects: true,
        validateStatus: (s) => s != null && s < 600,
      ),
    );
  }

  String _hexHead(List<int> bytes, {int max = 16}) {
    final head = bytes.take(max).toList();
    return head.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  }

  String? _tryDecodeText(List<int> bytes, {int maxChars = 2000}) {
    if (bytes.isEmpty) return null;
    try {
      final text = utf8.decode(bytes, allowMalformed: true);
      return text.length > maxChars ? text.substring(0, maxChars) : text;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _tryDecodeJsonMap(List<int> bytes) {
    try {
      final text = _tryDecodeText(bytes);
      if (text == null) return null;
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    super.dispose();
  }

  Future<void> _loadDocument() async {
    try {
      final loaded = await _tryLoadFromContent();
      if (!loaded && mounted) {
        setState(() {
          _isLoading = false;
          if (_errorMessage.isEmpty) {
            _errorMessage = 'Document preview not available.';
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error loading document: $e';
        _isLoading = false;
      });
    }
  }

  Future<bool> _tryLoadFromContent() async {
    if (widget.versionNumber != null &&
        widget.versionNumber!.trim().isNotEmpty) {
      return _tryLoadFromVersionViewUrl();
    }

    final url = '/documents/${widget.document.id}/content?format=auto';

    try {
      final dio = ApiClient.instance.dio;
      _dlog('GET $url');

      final response = await dio.get(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          validateStatus: (s) => s != null && s < 600,
          headers: {'Accept': '*/*'},
        ),
      );

      final status = response.statusCode ?? 0;
      final mimeType = response.headers.value('content-type') ?? '';
      final contentRange = response.headers.value('content-range') ?? '';
      final acceptRanges = response.headers.value('accept-ranges') ?? '';
      final bytes =
          response.data is List<int> ? response.data as List<int> : <int>[];

      _dlog(
        'status=$status mime="$mimeType" bytes=${bytes.length} acceptRanges="$acceptRanges" contentRange="$contentRange" head=${_hexHead(bytes)}',
      );

      // If content endpoint is broken server-side, fall back to view-url path.
      if (status >= 500) {
        _dlog('content endpoint returned $status; trying view-url fallback');
        _errorMessage = 'Server error while generating preview (HTTP $status).';
        return await _tryLoadFromViewUrlFallback();
      }

      // Some servers return JSON error payloads even with 200.
      final jsonMap = mimeType.toLowerCase().contains('application/json')
          ? _tryDecodeJsonMap(bytes)
          : null;
      if (status == 200 && jsonMap != null && jsonMap.isNotEmpty) {
        final msg =
            (jsonMap['message'] ?? jsonMap['error'] ?? jsonMap['detail'])
                ?.toString();
        _errorMessage = msg ?? 'Server returned JSON instead of document bytes.';
        _dlog('json-body=$jsonMap');
        if (mounted) setState(() => _isLoading = false);
        return true;
      }

      if (status == 409) {
        final map = _tryDecodeJsonMap(bytes);
        if (map != null) {
          _dlog('409-body=$map');
          final conv = map['conversionStatus']?.toString();
          final error = map['error']?.toString();
          if (conv == 'pending') {
            _conversionStatus = 'pending';
            _errorMessage = 'File is converting. Please try again in a moment.';
          } else if (error != null) {
            _conversionStatus = 'failed';
            _errorMessage = error;
          } else {
            _errorMessage = 'Conversion not ready.';
          }
        } else {
          _errorMessage = 'Conversion not ready.';
        }

        if (mounted) {
          setState(() => _isLoading = false);
        }
        return true;
      }

      if (status != 200 && status != 206) {
        final map = _tryDecodeJsonMap(bytes);
        final serverMsg = map != null
            ? (map['message'] ?? map['error'] ?? map['detail'])?.toString()
            : null;
        _errorMessage = serverMsg ?? 'Preview failed (HTTP $status).';
        if (mounted) setState(() => _isLoading = false);
        return true;
      }

      if (bytes.isEmpty) {
        _errorMessage = 'Empty preview response from server.';
        if (mounted) setState(() => _isLoading = false);
        return true;
      }

      return await _applyPreviewBytes(
        bytes,
        mimeType: mimeType,
        fileName: widget.document.name,
        isPdf: mimeType.toLowerCase().contains('pdf') || _isPdfSignature(bytes),
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      _dlog('dio-exception status=$status err=$e');
      if (status >= 500) {
        _errorMessage = 'Server error while generating preview.';
        return await _tryLoadFromViewUrlFallback();
      }
      _errorMessage = 'Preview failed (HTTP $status).';
      if (mounted) setState(() => _isLoading = false);
      return true;
    } catch (e) {
      _dlog('exception: $e');
      _errorMessage = 'Preview failed. Please try again.';
      if (mounted) setState(() => _isLoading = false);
      return true;
    }
  }

  Future<bool> _tryLoadFromVersionViewUrl() async {
    try {
      final version = widget.versionNumber!.trim();
      final asset = await VersionsService().getViewAsset(
        documentId: widget.document.id,
        version: version,
        original: widget.versionOriginal,
      );

      if (asset == null || asset.url.isEmpty) {
        _errorMessage = 'Preview URL missing.';
        if (mounted) setState(() => _isLoading = false);
        return true;
      }

      final status = asset.conversionStatus?.toLowerCase();
      if (status == 'pending' || status == 'converting') {
        _conversionStatus = status;
        _errorMessage = 'File is converting. Please try again in a moment.';
        if (mounted) setState(() => _isLoading = false);
        return true;
      }
      if (status == 'failed') {
        _conversionStatus = status;
        _errorMessage = asset.conversionError ?? 'Conversion failed.';
        if (mounted) setState(() => _isLoading = false);
        return true;
      }

      final raw = _rawDio();
      final fileResp = await raw.get(
        asset.url,
        options: Options(
          responseType: ResponseType.bytes,
          validateStatus: (s) => s != null && s < 600,
          headers: {'Accept': '*/*'},
        ),
      );

      final fileStatus = fileResp.statusCode ?? 0;
      if (fileStatus != 200 && fileStatus != 206) {
        _errorMessage = 'Preview download failed (HTTP $fileStatus).';
        if (mounted) setState(() => _isLoading = false);
        return true;
      }

      final bytes = fileResp.data is List<int>
          ? fileResp.data as List<int>
          : (fileResp.data is List
              ? (fileResp.data as List).cast<int>()
              : <int>[]);
      if (bytes.isEmpty) {
        _errorMessage = 'Empty preview download from server.';
        if (mounted) setState(() => _isLoading = false);
        return true;
      }

      final mimeType =
          fileResp.headers.value('content-type') ?? asset.mimeType ?? '';

      return _applyPreviewBytes(
        bytes,
        mimeType: mimeType,
        fileName: widget.versionFileName ?? widget.document.name,
        isPdf: asset.isPdf ||
            mimeType.toLowerCase().contains('pdf') ||
            _isPdfSignature(bytes),
      );
    } catch (e) {
      _errorMessage = 'Preview failed. Please try again.';
      if (mounted) setState(() => _isLoading = false);
      return true;
    }
  }

  Future<bool> _tryLoadFromViewUrlFallback() async {
    try {
      final dio = ApiClient.instance.dio;
      final metaUrl = '/documents/${widget.document.id}/view-url';
      _dlog('GET $metaUrl (fallback)');

      final metaResp = await dio.get(
        metaUrl,
        options: Options(
          validateStatus: (s) => s != null && s < 600,
          headers: {'Accept': 'application/json'},
        ),
      );

      final metaStatus = metaResp.statusCode ?? 0;
      _dlog('fallback view-url status=$metaStatus data=${metaResp.data}');
      if (metaStatus != 200) {
        _errorMessage = 'Preview failed (HTTP $metaStatus).';
        if (mounted) setState(() => _isLoading = false);
        return true;
      }

      final meta = metaResp.data is Map
          ? Map<String, dynamic>.from(metaResp.data as Map)
          : <String, dynamic>{};

      final conversionStatus = meta['conversionStatus']?.toString();
      if (conversionStatus == 'pending') {
        _conversionStatus = 'pending';
        _errorMessage = 'File is converting. Please try again in a moment.';
        if (mounted) setState(() => _isLoading = false);
        return true;
      }

      final url = meta['url']?.toString();
      if (url == null || url.isEmpty) {
        _errorMessage = 'Preview URL missing.';
        if (mounted) setState(() => _isLoading = false);
        return true;
      }

      final raw = _rawDio();
      final fileResp = await raw.get(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          validateStatus: (s) => s != null && s < 600,
          headers: {'Accept': '*/*'},
        ),
      );

      final fileStatus = fileResp.statusCode ?? 0;
      final fileMime = fileResp.headers.value('content-type') ??
          meta['mimeType']?.toString() ??
          '';
      final fileBytes = fileResp.data is List<int>
          ? fileResp.data as List<int>
          : <int>[];

      _dlog(
        'fallback file status=$fileStatus mime="$fileMime" bytes=${fileBytes.length} head=${_hexHead(fileBytes)}',
      );

      if (fileStatus != 200 && fileStatus != 206) {
        _errorMessage = 'Preview download failed (HTTP $fileStatus).';
        if (mounted) setState(() => _isLoading = false);
        return true;
      }

      if (fileBytes.isEmpty) {
        _errorMessage = 'Empty preview download from server.';
        if (mounted) setState(() => _isLoading = false);
        return true;
      }

      final fileName = meta['fileName']?.toString() ?? widget.document.name;
      final isPdf = meta['isPdf'] == true ||
          fileMime.toLowerCase().contains('pdf') ||
          _isPdfSignature(fileBytes);

      return await _applyPreviewBytes(
        fileBytes,
        mimeType: fileMime,
        fileName: fileName,
        isPdf: isPdf,
      );
    } catch (e) {
      _dlog('fallback exception: $e');
      _errorMessage = 'Preview failed. Please try again.';
      if (mounted) setState(() => _isLoading = false);
      return true;
    }
  }

  Future<bool> _applyPreviewBytes(
    List<int> bytes, {
    String? mimeType,
    String? fileName,
    bool? isPdf,
  }) async {
    try {
      final name = (fileName ?? widget.document.name).toLowerCase();
      final type = mimeType?.toLowerCase() ?? '';

      if (isPdf == true || _isPdfSignature(bytes)) {
        try {
          _pdfController = PdfController(
            document: PdfDocument.openData(Uint8List.fromList(bytes)),
          );
          if (mounted) setState(() => _isLoading = false);
          return true;
        } catch (e) {
          _dlog('pdf-openData failed: $e');
          if (mounted) {
            setState(() {
              _errorMessage = 'Could not open PDF preview.';
              _isLoading = false;
            });
          }
          return true;
        }
      }

      if (type.startsWith('text/') || name.endsWith('.txt') || name.endsWith('.csv')) {
        _setTextFromBytes(bytes);
        return true;
      }

      if (type.startsWith('image/') ||
          name.endsWith('.png') ||
          name.endsWith('.jpg') ||
          name.endsWith('.jpeg') ||
          name.endsWith('.gif') ||
          name.endsWith('.bmp')) {
        _binaryFile = await _writeTempFile(bytes);
        if (mounted) setState(() => _isLoading = false);
        return true;
      }

      if (mounted) {
        setState(() {
          _errorMessage =
              'Document preview not available. Try Open with another app.';
          _isLoading = false;
        });
      }
      return false;
    } catch (e) {
      _dlog('applyPreviewBytes exception: $e');
      return false;
    }
  }

  Future<void> _retryConversionAndPoll() async {
    if (_isRetrying) return;
    setState(() {
      _isRetrying = true;
      _isLoading = true;
      _errorMessage = '';
    });

    final conversion = ConversionService();
    await conversion.requestConversion(widget.document.id);

    for (int i = 0; i < 5; i++) {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      final status = await conversion.getStatus(widget.document.id);
      if (status != null) {
        final s = status.status.toLowerCase();
        if (s == 'completed' || s == 'ready') {
          _conversionStatus = 'completed';
          final loaded = await _tryLoadFromContent();
          if (loaded) {
            if (!mounted) return;
            setState(() => _isRetrying = false);
            return;
          }
        }
        if (s == 'failed') {
          setState(() {
            _conversionStatus = 'failed';
            _errorMessage = status.message ?? 'Conversion failed';
            _isRetrying = false;
            _isLoading = false;
          });
          return;
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _isRetrying = false;
      _isLoading = false;
      _conversionStatus = 'pending';
      _errorMessage = 'Conversion still in progress. Please try again.';
    });
  }

  bool _isPdfSignature(List<int> bytes) {
    if (bytes.length < 4) return false;
    return bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46;
  }

  void _setTextFromBytes(List<int> bytes) {
    String content;
    try {
      content = utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      content = latin1.decode(bytes);
    }
    _textContent = content;
    _csvRows = _isProbablyCsv() ? _parseCsv(content) : <List<String>>[];
    if (mounted) setState(() => _isLoading = false);
  }

  bool _isProbablyCsv() {
    final name = widget.document.name.toLowerCase();
    final type = widget.fileType.toLowerCase();
    return name.endsWith('.csv') ||
        name.endsWith('.tsv') ||
        type == 'csv' ||
        type == 'tsv' ||
        type.contains('csv') ||
        type.contains('tsv');
  }

  List<List<String>> _parseCsv(String content) {
    final lines = content
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trimRight())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return <List<String>>[];

    final delimiter = _detectDelimiter(lines);
    final rows = <List<String>>[];

    for (final line in lines) {
      rows.add(_splitDelimitedLine(line, delimiter));
    }

    if (rows.isEmpty) return <List<String>>[];

    // Remove UTF-8 BOM if present in first cell.
    if (rows.first.isNotEmpty) {
      rows.first[0] = rows.first[0].replaceFirst('\ufeff', '');
    }

    // Avoid treating a plain single-column text file as CSV.
    final maxCols = rows.map((r) => r.length).fold<int>(0, (m, v) => v > m ? v : m);
    if (maxCols <= 1) return <List<String>>[];

    return rows;
  }

  String _detectDelimiter(List<String> lines) {
    // If it's a TSV, force tab delimiter.
    final name = widget.document.name.toLowerCase();
    final type = widget.fileType.toLowerCase();
    if (name.endsWith('.tsv') || type == 'tsv' || type.contains('tsv')) {
      return '\t';
    }

    const candidates = [',', ';', '\t', '|'];
    final sample = lines.take(10).toList();

    int bestScore = -1;
    String best = ',';

    for (final d in candidates) {
      int score = 0;
      for (final line in sample) {
        score += _countDelimiterOutsideQuotes(line, d);
      }
      if (score > bestScore) {
        bestScore = score;
        best = d;
      }
    }

    return best;
  }

  int _countDelimiterOutsideQuotes(String line, String delimiter) {
    var inQuotes = false;
    var count = 0;
    for (int i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          i++; // escaped quote
        } else {
          inQuotes = !inQuotes;
        }
        continue;
      }
      if (!inQuotes && ch == delimiter) count++;
    }
    return count;
  }

  List<String> _splitDelimitedLine(String line, String delimiter) {
    final fields = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final ch = line[i];

      if (ch == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
        continue;
      }

      if (!inQuotes && ch == delimiter) {
        fields.add(buffer.toString());
        buffer.clear();
        continue;
      }

      buffer.write(ch);
    }

    fields.add(buffer.toString());
    return fields;
  }

  Future<File> _writeTempFile(List<int> bytes) async {
    final tempDir = await getTemporaryDirectory();
    final safeBaseName =
        widget.document.name.replaceAll(RegExp(r'[^\w\.\-]'), '_');
    final filePath = '${tempDir.path}/$safeBaseName';
    final file = File(filePath);
    await file.writeAsBytes(bytes);
    return file;
  }

  @override
  Widget build(BuildContext context) {
    final versionInt = int.tryParse(widget.versionNumber ?? '');
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.document.name, overflow: TextOverflow.ellipsis),
        backgroundColor: const Color.fromARGB(255, 43, 65, 189),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.comment_outlined),
            onPressed: () => DocumentCommentsSheet.show(
              context: context,
              documentId: widget.document.id,
              version: versionInt,
            ),
            tooltip: 'Comments',
          ),
          IconButton(
            icon: const Icon(Icons.draw_outlined),
            onPressed: () => DocumentAnnotationsSheet.show(
              context: context,
              documentId: widget.document.id,
              version: versionInt,
            ),
            tooltip: 'Annotations',
          ),
          IconButton(
            icon: const Icon(Icons.open_in_new),
            onPressed: _showOpenOptions,
            tooltip: 'Open with other apps',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? _buildErrorView()
              : _buildPreviewContent(),
    );
  }

  Widget _buildErrorView() {
    final showRetry = (_conversionStatus == 'pending') ||
        _errorMessage.toLowerCase().contains('converting');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 60, color: Colors.red),
            const SizedBox(height: 20),
            const Text(
              'Cannot Preview Document',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            if (showRetry)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ElevatedButton.icon(
                  onPressed: _isRetrying ? null : _retryConversionAndPoll,
                  icon: _isRetrying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(_isRetrying ? 'Retrying...' : 'Retry Conversion'),
                ),
              ),
            ElevatedButton.icon(
              onPressed: _showOpenOptions,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Try Opening with Another App'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewContent() {
    if (_pdfController != null) return _buildPdfViewer();
    if (_binaryFile != null) return _buildImageViewer();
    if (_csvRows.isNotEmpty) return _buildCsvViewer();
    if (_textContent.isNotEmpty) return _buildTextViewer();
    return _buildUnsupportedViewer();
  }

  Widget _buildPdfViewer() {
    return PdfView(
      controller: _pdfController!,
      scrollDirection: Axis.vertical,
    );
  }

  Widget _buildTextViewer() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: SelectableText(
        _textContent,
        style: const TextStyle(fontSize: 16, height: 1.5),
      ),
    );
  }

  Widget _buildCsvViewer() {
    if (_csvRows.isEmpty) return _buildTextViewer();

    final maxColumns = _csvRows
        .map((r) => r.length)
        .fold<int>(0, (m, v) => v > m ? v : m);
    if (maxColumns <= 0) return _buildTextViewer();

    final rawHeaders = _csvRows.first;
    final headers = <String>[...rawHeaders];
    if (headers.length < maxColumns) {
      for (int i = headers.length; i < maxColumns; i++) {
        headers.add('Column ${i + 1}');
      }
    } else if (headers.length > maxColumns) {
      headers.removeRange(maxColumns, headers.length);
    }

    final rows = _csvRows.length > 1 ? _csvRows.sublist(1) : <List<String>>[];
    final normalizedRows = rows.map((row) {
      if (row.length == maxColumns) return row;
      if (row.length > maxColumns) return row.sublist(0, maxColumns);
      return [...row, ...List.filled(maxColumns - row.length, '')];
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: DataTable(
          columns: [
            for (final h in headers)
              DataColumn(label: Text(h, style: const TextStyle(fontSize: 12)))
          ],
          rows: [
            for (final row in normalizedRows)
              DataRow(
                cells: [
                  for (final cell in row)
                    DataCell(Text(cell, overflow: TextOverflow.ellipsis)),
                ],
              )
          ],
        ),
      ),
    );
  }

  Widget _buildImageViewer() {
    return Center(
      child: _binaryFile == null
          ? const Text('Image not available')
          : Image.file(_binaryFile!),
    );
  }

  Widget _buildUnsupportedViewer() {
    return const Center(
      child: Text('Preview not available. Try Open with another app.'),
    );
  }

  void _showOpenOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => DocumentOpenOptionsDialog(
        document: widget.document,
        fileType: widget.fileType,
      ),
    );
  }
}
