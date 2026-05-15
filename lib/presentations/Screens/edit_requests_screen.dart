import 'package:flutter/material.dart';
import 'package:digi_sanchika/widgets/responsive_page.dart';
import 'package:digi_sanchika/services/edit_requests_service.dart';
import 'package:digi_sanchika/models/edit_request.dart';
import 'package:digi_sanchika/models/document.dart';
import 'package:digi_sanchika/services/my_documents_service.dart';
import 'package:digi_sanchika/presentations/Screens/document_preview_screen.dart';
import 'package:digi_sanchika/widgets/request_document_card.dart';

class EditRequestsScreen extends StatefulWidget {
  const EditRequestsScreen({super.key});

  @override
  State<EditRequestsScreen> createState() => _EditRequestsScreenState();
}

class _EditRequestsScreenState extends State<EditRequestsScreen>
    with SingleTickerProviderStateMixin {
  final EditRequestsService _service = EditRequestsService();
  late TabController _tabController;

  bool _isLoading = true;
  List<EditRequest> _myRequests = [];
  List<EditRequest> _pending = [];
  final Map<String, Future<Document?>> _documentCache = {};

  Future<Document?> _getDocument(String documentId, {String? nameHint}) {
    return _documentCache.putIfAbsent(documentId, () async {
      try {
        final detailsResp = await MyDocumentsService.getDocumentDetails(
          documentId,
        );
        if (detailsResp['success'] == true && detailsResp['details'] != null) {
          final raw = detailsResp['details'];
          if (raw is Map<String, dynamic>) {
            return _mapBackendDoc(raw, idFallback: documentId, nameHint: nameHint);
          }
        }
      } catch (_) {}
      if (nameHint != null && nameHint.trim().isNotEmpty) {
        return _minimalDocument(documentId, nameHint.trim());
      }
      return null;
    });
  }

  Document _minimalDocument(String id, String name) {
    return Document(
      id: id,
      name: name,
      type: '',
      size: '',
      keyword: '',
      uploadDate: '',
      owner: '',
      details: '',
      classification: 'General',
      allowDownload: false,
      sharingType: 'private',
      folder: '',
      path: name,
      fileType: '',
    );
  }

  Document _mapBackendDoc(
    Map<String, dynamic> docData, {
    required String idFallback,
    String? nameHint,
  }) {
    final filename =
        docData['name']?.toString() ??
        docData['original_name']?.toString() ??
        docData['original_filename']?.toString() ??
        docData['file_name']?.toString() ??
        docData['filename']?.toString() ??
        nameHint?.toString() ??
        'Untitled Document';

    final mimeType = docData['mime_type']?.toString();
    final type =
        docData['file_type']?.toString() ??
        (mimeType != null && mimeType.contains('/')
            ? mimeType.split('/').last
            : '');

    final ownerName =
        (docData['owner'] is Map<String, dynamic>)
            ? (docData['owner']['name']?.toString() ?? '')
            : (docData['owner']?.toString() ?? '');

    return Document(
      id: docData['id']?.toString() ?? idFallback,
      name: filename.isNotEmpty ? filename : 'Untitled Document',
      type: type,
      size: (docData['size'] ?? '').toString(),
      keyword: docData['keywords']?.toString() ?? '',
      uploadDate: (docData['created_at'] ?? docData['updated_at'] ?? '').toString(),
      owner: ownerName,
      details: docData['remarks']?.toString() ?? '',
      classification:
          docData['classification']?.toString() ??
          docData['doc_class']?.toString() ??
          'internal',
      allowDownload: docData['allow_download'] == true,
      sharingType: (docData['is_public'] == true) ? 'Public' : 'Private',
      folder: docData['folder_path']?.toString() ?? 'Home',
      folderId: docData['folder_id']?.toString(),
      path: filename,
      fileType: type.isNotEmpty ? type : 'unknown',
    );
  }

  ({String text, Color color, IconData icon}) _statusStyle(String status) {
    final s = status.trim().toLowerCase();
    if (s.contains('approve') || s.contains('granted')) {
      return (text: 'Approved', color: Colors.green.shade700, icon: Icons.check_circle);
    }
    if (s.contains('reject') || s.contains('denied')) {
      return (text: 'Rejected', color: Colors.red.shade700, icon: Icons.cancel);
    }
    if (s.contains('pending') || s.contains('requested')) {
      return (text: 'Pending', color: Colors.orange.shade800, icon: Icons.hourglass_top);
    }
    return (text: status.isEmpty ? 'Unknown' : status, color: Colors.grey.shade700, icon: Icons.info_outline);
  }

  Widget _docLeading(Document? doc) {
    final name = (doc?.name ?? '').toLowerCase();
    final ext = name.contains('.') ? name.split('.').last : '';
    final icon = switch (ext) {
      'pdf' => Icons.picture_as_pdf_rounded,
      'doc' || 'docx' => Icons.description_rounded,
      'xls' || 'xlsx' => Icons.grid_on_rounded,
      'ppt' || 'pptx' => Icons.slideshow_rounded,
      'jpg' || 'jpeg' || 'png' => Icons.image_rounded,
      'txt' => Icons.text_snippet_rounded,
      _ => Icons.insert_drive_file_rounded,
    };
    final color = switch (ext) {
      'pdf' => const Color(0xFFD32F2F),
      'doc' || 'docx' => const Color(0xFF1565C0),
      'xls' || 'xlsx' => const Color(0xFF2E7D32),
      'ppt' || 'pptx' => const Color(0xFFE65100),
      'jpg' || 'jpeg' || 'png' => const Color(0xFF6A1B9A),
      'txt' => const Color(0xFF455A64),
      _ => const Color(0xFF2B41BD),
    };

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(35)),
      ),
      child: Icon(icon, color: color),
    );
  }

  Future<void> _viewDocument(Document doc) async {
    final fileType = doc.type.isNotEmpty ? doc.type : doc.fileType;
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentPreviewScreen(
          document: doc,
          fileType: fileType.isNotEmpty ? fileType : 'unknown',
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> _promptApproveDetails() async {
    if (!mounted) return null;
    final notes = TextEditingController();
    final hours = TextEditingController(text: '24');
    Map<String, dynamic>? result;
    try {
      result = await showDialog<Map<String, dynamic>?>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Approve edit request'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: notes,
                decoration:
                    const InputDecoration(hintText: 'Review notes (optional)'),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: hours,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Expires in (hours)',
                  hintText: 'e.g. 24',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final parsed = int.tryParse(hours.text.trim());
                Navigator.pop(context, <String, dynamic>{
                  'notes': notes.text.trim(),
                  'hours': parsed,
                });
              },
              child: const Text('Approve'),
            ),
          ],
        ),
      );
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notes.dispose();
        hours.dispose();
      });
    }
    return result;
  }

  Future<String?> _promptRejectNotes() async {
    if (!mounted) return null;
    final notes = TextEditingController();
    String? result;
    try {
      result = await showDialog<String?>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reject edit request'),
          content: TextField(
            controller: notes,
            decoration:
                const InputDecoration(hintText: 'Review notes (optional)'),
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, notes.text.trim()),
              child: const Text('Reject'),
            ),
          ],
        ),
      );
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notes.dispose();
      });
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final myReq = await _service.myRequests();
    final pending = await _service.pendingApprovals();
    setState(() {
      _myRequests = myReq;
      _pending = pending;
      _isLoading = false;
    });
  }

  Widget _buildRequestTile(EditRequest request, {bool actions = false}) {
    final status = _statusStyle(request.status);
    return FutureBuilder<Document?>(
      future: _getDocument(request.documentId, nameHint: request.documentName),
      builder: (context, snapshot) {
        final doc = snapshot.data ??
            (request.documentName != null
                ? _minimalDocument(request.documentId, request.documentName!)
                : null);
        final title = doc?.name ?? 'Document ${request.documentId}';
        final subtitle = (doc?.owner.isNotEmpty == true)
            ? 'Owner: ${doc!.owner}'
            : (actions
                ? (request.requesterName != null
                    ? 'Requested by: ${request.requesterName}'
                    : (request.requesterEmail != null
                        ? 'Requested by: ${request.requesterEmail}'
                        : null))
                : null);

        final meta = [
          if (doc?.folder.isNotEmpty == true) 'Folder: ${doc!.folder}',
          if (request.createdAt != null && request.createdAt!.isNotEmpty)
            'Requested: ${request.createdAt}',
        ].join(' • ');

        final onView = doc == null ? null : () => _viewDocument(doc);

        final List<Widget> cardActions = [];
        if (actions) {
          cardActions.addAll([
            TextButton.icon(
              onPressed: () async {
                final details = await _promptApproveDetails();
                if (details == null) return;
                await _service.approve(
                  request.id,
                  reviewNotes: (details['notes'] as String?)?.trim(),
                  expiresInHours: details['hours'] as int?,
                );
                _load();
              },
              icon: const Icon(Icons.check_rounded),
              label: const Text('Approve'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.green.shade800,
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () async {
                final notes = await _promptRejectNotes();
                if (notes == null) return;
                await _service.reject(request.id, reviewNotes: notes);
                _load();
              },
              icon: const Icon(Icons.close_rounded),
              label: const Text('Reject'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red.shade700,
              ),
            ),
          ]);
        }

        return RequestDocumentCard(
          leading: _docLeading(doc),
          title: title,
          subtitle: subtitle,
          statusText: status.text,
          statusColor: status.color,
          statusIcon: status.icon,
          metaLine: meta.isEmpty ? null : meta,
          reason: request.reason,
          onView: onView,
          actions: cardActions,
        );
      },
    );
  }

  Widget _buildList(List<EditRequest> requests, {bool actions = false}) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (requests.isEmpty) {
      return const Center(child: Text('No requests found'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemCount: requests.length,
        itemBuilder: (context, index) =>
            _buildRequestTile(requests[index], actions: actions),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Requests'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'My Requests'),
            Tab(text: 'Pending'),
          ],
        ),
      ),
      body: ResponsivePage(
        padding: EdgeInsets.zero,
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildList(_myRequests),
            _buildList(_pending, actions: true),
          ],
        ),
      ),
    );
  }
}
