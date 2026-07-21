// ignore_for_file: use_build_context_synchronously
import 'dart:io';

import 'package:digi_sanchika/utils/app_fonts.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:digi_sanchika/models/document.dart';
import 'package:digi_sanchika/models/folder.dart';
import 'package:digi_sanchika/services/upload_service.dart';
import 'package:digi_sanchika/services/folder_tree_service.dart';
import 'package:digi_sanchika/models/folder_tree_node.dart';

// ---------------------------------------------------------------------------
// ScanSaveScreen
//
// Final step of the CamScanner-like flow:
//   1. Name the document
//   2. Pick a folder from the existing tree
//   3. Set keywords + classification
//   4. Assembles all scanned pages into a single PDF
//   5. Uploads via UploadService (same path as the regular upload flow)
// ---------------------------------------------------------------------------
class ScanSaveScreen extends StatefulWidget {
  final List<File> pages;
  final List<dynamic> folders;
  final String? userName;
  final Function(File) onSaved;

  const ScanSaveScreen({
    super.key,
    required this.pages,
    required this.folders,
    required this.onSaved,
    this.userName,
  });

  @override
  State<ScanSaveScreen> createState() => _ScanSaveScreenState();
}

class _ScanSaveScreenState extends State<ScanSaveScreen> {
  // ── Form controllers ────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _keywordsCtrl = TextEditingController();
  final _remarksCtrl = TextEditingController();

  // ── Folder ───────────────────────────────────────────────────────────────
  String? _selectedFolderId;
  String? _selectedFolderName;
  List<FolderTreeNode> _folderTree = [];
  bool _folderLoading = false;

  // ── Settings ────────────────────────────────────────────────────────────
  String _classification = 'General';
  String _sharingType = 'Public';
  bool _allowDownload = true;
  String _outputFormat = 'PDF'; // PDF | JPEG

  static const _classifications = [
    'General',
    'Internal Use Only',
    'Corporate Confidential',
    'Restricted',
    'Secret',
  ];
  static const _sharingTypes = ['Public', 'Private', 'Specific Users'];

  // ── Upload state ─────────────────────────────────────────────────────────
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String _uploadStatus = '';

  @override
  void initState() {
    super.initState();
    _nameCtrl.text =
        'Scan_${DateTime.now().day}-${DateTime.now().month}-${DateTime.now().year}';
    _loadFolders();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _keywordsCtrl.dispose();
    _remarksCtrl.dispose();
    super.dispose();
  }

  // ── Load folders ──────────────────────────────────────────────────────────
  Future<void> _loadFolders() async {
    setState(() => _folderLoading = true);
    try {
      final svc = FolderTreeService();
      final tree = await svc.fetchFolderTree();
      if (mounted) setState(() => _folderTree = tree);
    } catch (_) {
      // Fallback: build flat list from widget.folders if FolderTreeService fails
      final flat = widget.folders.whereType<Folder>().map((f) {
        return FolderTreeNode(
          id: f.id,
          name: f.name,
          parentId: f.parentId,
          children: [], createdAt: DateTime.now(), owner: widget.userName ?? 'Current User',
        );
      }).toList();
      if (mounted) setState(() => _folderTree = flat);
    } finally {
      if (mounted) setState(() => _folderLoading = false);
    }
  }

  // ── Build PDF from scanned pages ──────────────────────────────────────────
  Future<File> _buildPdf() async {
    final pdf = pw.Document();

    for (final pageFile in widget.pages) {
      final bytes = await pageFile.readAsBytes();
      final image = pw.MemoryImage(bytes);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Image(image, fit: pw.BoxFit.contain),
            );
          },
        ),
      );
    }

    final dir = await getTemporaryDirectory();
    final cleanName = _nameCtrl.text
        .trim()
        .replaceAll(RegExp(r'[^\w\s\-]'), '')
        .replaceAll(' ', '_');
    final outFile = File('${dir.path}/$cleanName.pdf');
    await outFile.writeAsBytes(await pdf.save());
    return outFile;
  }

  // ── Map classification label → API value ──────────────────────────────────
  String _mapClass(String label) {
    switch (label.trim().toLowerCase()) {
      case 'internal use only':
        return 'internal';
      case 'corporate confidential':
        return 'confidential';
      case 'restricted':
        return 'restricted';
      case 'secret':
        return 'secret';
      default:
        return 'internal';
    }
  }

  // ── Upload ────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.1;
      _uploadStatus = 'Building PDF…';
    });

    try {
      // Step 1 – assemble PDF
      final pdfFile = await _buildPdf();

      setState(() {
        _uploadProgress = 0.35;
        _uploadStatus = 'Uploading…';
      });

      // Step 2 – upload via the existing service
      final result = await UploadService.uploadSingleFile(
        file: pdfFile,
        keywords: _keywordsCtrl.text.trim(),
        remarks: _remarksCtrl.text.trim().isEmpty
            ? 'Scanned document'
            : _remarksCtrl.text.trim(),
        docClass: _mapClass(_classification),
        allowDownload: _allowDownload,
        sharing: _sharingType.toLowerCase(),
        folderId: _selectedFolderId ?? '',
      );

      setState(() {
        _uploadProgress = 1.0;
        _uploadStatus = '';
      });

      if (result['success'] == true) {
        widget.onSaved(pdfFile);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 10),
                  Text(
                    '"${_nameCtrl.text.trim()}" saved successfully!',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        _showError(result['message']?.toString() ?? 'Upload failed');
      }
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    setState(() {
      _isUploading = false;
      _uploadStatus = '';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  // ── Folder picker bottom sheet ─────────────────────────────────────────────
  void _pickFolder() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, sc) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Choose Folder',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            // Home option
            ListTile(
              leading: const Icon(Icons.home_outlined, color: Colors.indigo),
              title: const Text('Home'),
              trailing: _selectedFolderId == null
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () {
                setState(() {
                  _selectedFolderId = null;
                  _selectedFolderName = null;
                });
                Navigator.pop(ctx);
              },
            ),
            Expanded(
              child: _folderLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      controller: sc,
                      children: _buildFolderTiles(_folderTree, 0, ctx),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFolderTiles(
    List<FolderTreeNode> nodes,
    int depth,
    BuildContext sheetCtx,
  ) {
    final tiles = <Widget>[];
    for (final node in nodes) {
      tiles.add(
        ListTile(
          contentPadding: EdgeInsets.only(left: 16.0 + depth * 16),
          leading: Icon(
            node.children.isNotEmpty
                ? Icons.folder_open
                : Icons.folder_outlined,
            color: Colors.indigo,
            size: 22,
          ),
          title: Text(node.name),
          trailing: _selectedFolderId == node.id
              ? const Icon(Icons.check, color: Colors.green)
              : null,
          onTap: () {
            setState(() {
              _selectedFolderId = node.id;
              _selectedFolderName = node.name;
            });
            Navigator.pop(sheetCtx);
          },
        ),
      );
      if (node.children.isNotEmpty) {
        tiles.addAll(_buildFolderTiles(node.children, depth + 1, sheetCtx));
      }
    }
    return tiles;
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        iconTheme: const IconThemeData(color: Colors.black87),
        title:  Text(
          'Save Document',
          style: w600_16Poppins(),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: Stack(
        children: [
          Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              children: [
                // ── Page previews ──────────────────────────────────────
                _buildPagePreviews(),
                const SizedBox(height: 20),

                // ── Document name ──────────────────────────────────────
                _SectionLabel(label: 'Document Name'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _nameCtrl,
                  decoration: _inputDecoration(
                    hint: 'e.g. Invoice_2024',
                    prefix: Icons.description_outlined,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Document name is required'
                      : null,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),

                // ── Folder ─────────────────────────────────────────────
                _SectionLabel(label: 'Save to Folder'),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: _pickFolder,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.folder_open,
                            color: Colors.indigo, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _selectedFolderName ?? 'Home (default)',
                            style: TextStyle(
                              color: _selectedFolderName != null
                                  ? Colors.black87
                                  : Colors.grey.shade500,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        const Icon(Icons.chevron_right,
                            color: Colors.grey, size: 20),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Keywords ───────────────────────────────────────────
                _SectionLabel(label: 'Keywords (optional)'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _keywordsCtrl,
                  decoration: _inputDecoration(
                    hint: 'invoice, finance, Q3',
                    prefix: Icons.label_outline,
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),

                // ── Remarks ─────────────────────────────────────────────
                _SectionLabel(label: 'Remarks (optional)'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _remarksCtrl,
                  decoration: _inputDecoration(
                    hint: 'Scanned at office – original filed in cabinet A',
                    prefix: Icons.notes,
                  ),
                  maxLines: 2,
                  textInputAction: TextInputAction.done,
                ),
                const SizedBox(height: 16),

                // ── Classification ──────────────────────────────────────
                _SectionLabel(label: 'Classification'),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _classification,
                  decoration: _inputDecoration(
                    prefix: Icons.shield_outlined,
                  ),
                  items: _classifications
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _classification = v ?? _classification),
                ),
                const SizedBox(height: 16),

                // ── Sharing ─────────────────────────────────────────────
                _SectionLabel(label: 'Sharing'),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _sharingType,
                  decoration: _inputDecoration(
                    prefix: Icons.share_outlined,
                  ),
                  items: _sharingTypes
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _sharingType = v ?? _sharingType),
                ),
                const SizedBox(height: 12),

                // ── Allow download ──────────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: SwitchListTile(
                    title: const Text('Allow Download'),
                    subtitle: const Text('Others can download this document'),
                    value: _allowDownload,
                    activeColor: Colors.indigo,
                    onChanged: (v) => setState(() => _allowDownload = v),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Output format ────────────────────────────────────────
                _SectionLabel(label: 'Output Format'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _FormatChip(
                      label: 'PDF',
                      icon: Icons.picture_as_pdf,
                      selected: _outputFormat == 'PDF',
                      color: Colors.red,
                      onTap: () => setState(() => _outputFormat = 'PDF'),
                    ),
                    const SizedBox(width: 12),
                    _FormatChip(
                      label: 'JPEG',
                      icon: Icons.image_outlined,
                      selected: _outputFormat == 'JPEG',
                      color: Colors.blue,
                      onTap: () => setState(() => _outputFormat = 'JPEG'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Upload progress overlay ───────────────────────────────────
          if (_isUploading) _buildUploadOverlay(),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  // ── Page previews strip ─────────────────────────────────────────────────
  Widget _buildPagePreviews() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(
          label: '${widget.pages.length} Page${widget.pages.length > 1 ? 's' : ''} Scanned',
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: widget.pages.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    widget.pages[i],
                    width: 64,
                    height: 90,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Upload progress overlay ───────────────────────────────────────────────
  Widget _buildUploadOverlay() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: _uploadProgress),
                duration: const Duration(milliseconds: 400),
                builder: (_, v, __) => CircularProgressIndicator(
                  value: v < 1.0 ? v : null,
                  color: Colors.indigo,
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _uploadStatus.isNotEmpty ? _uploadStatus : 'Uploading…',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${((_uploadProgress) * 100).toInt()}%',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Bottom bar with Save button ───────────────────────────────────────────
  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: _isUploading ? null : _save,
          icon: const Icon(Icons.cloud_upload_outlined, size: 22),
          label: const Text(
            'Upload Document',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 2,
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({String? hint, IconData? prefix}) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: prefix != null ? Icon(prefix, color: Colors.indigo) : null,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.indigo, width: 1.5),
      ),
    );
  }
}

// ── Reusable widgets ──────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.black54,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _FormatChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _FormatChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.12) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: selected ? color : Colors.grey, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? color : Colors.grey.shade600,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}