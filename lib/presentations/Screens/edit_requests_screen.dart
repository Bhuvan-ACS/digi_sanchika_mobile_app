import 'package:digi_sanchika/utils/app_fonts.dart';
import 'package:flutter/material.dart';
import 'package:digi_sanchika/widgets/responsive_page.dart';
import 'package:digi_sanchika/services/edit_requests_service.dart';
import 'package:digi_sanchika/models/edit_request.dart';
import 'package:digi_sanchika/models/document.dart';
import 'package:digi_sanchika/services/my_documents_service.dart';
import 'package:digi_sanchika/presentations/Screens/document_preview_screen.dart';

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

  ({String text, Color bg, Color fg, IconData icon}) _statusChipStyle(String status) {
    final s = status.trim().toLowerCase();
    if (s.contains('approve') || s.contains('granted')) {
      return (
        text: 'Approved',
        bg: const Color(0xFFE6F6EC),
        fg: const Color(0xFF1E8A4C),
        icon: Icons.check_circle_rounded,
      );
    }
    if (s.contains('reject') || s.contains('denied')) {
      return (
        text: 'Rejected',
        bg: const Color(0xFFFCEAEA),
        fg: const Color(0xFFD32F2F),
        icon: Icons.cancel_rounded,
      );
    }
    if (s.contains('pending') || s.contains('requested')) {
      return (
        text: 'Pending',
        bg: const Color(0xFFFFF3E0),
        fg: const Color(0xFFE65100),
        icon: Icons.hourglass_top_rounded,
      );
    }
    return (
      text: status.isEmpty ? 'Unknown' : status,
      bg: const Color(0xFFF0F0F0),
      fg: Colors.grey.shade700,
      icon: Icons.info_outline_rounded,
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

  /// Turns an ISO timestamp into a short relative string like "18m ago".
  String _timeAgo(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
    return '${(diff.inDays / 365).floor()}y ago';
  }

  /// Small file-type icon used inside chips/leading avatars.
  Widget _fileTypeIcon(String? name, {double size = 16, Color? color}) {
    final n = (name ?? '').toLowerCase();
    final ext = n.contains('.') ? n.split('.').last : '';
    final icon = switch (ext) {
      'pdf' => Icons.picture_as_pdf_rounded,
      'doc' || 'docx' => Icons.description_rounded,
      'xls' || 'xlsx' => Icons.grid_on_rounded,
      'ppt' || 'pptx' => Icons.slideshow_rounded,
      'jpg' || 'jpeg' || 'png' => Icons.image_rounded,
      'txt' => Icons.text_snippet_rounded,
      _ => Icons.insert_drive_file_rounded,
    };
    return Icon(icon, size: size, color: color ?? const Color(0xFFE65100));
  }

  /// Card design for the "Pending" tab — avatar initial, name, time, a
  /// "wants to edit" chip with the document name, and full-width
  /// Decline / Approve buttons. Uses the same _service.approve/_service.reject
  /// calls (with the same approve-details / reject-notes dialogs) as before.
  Widget _buildPendingRequestTile(EditRequest request) {
    return FutureBuilder<Document?>(
      future: _getDocument(request.documentId, nameHint: request.documentName),
      builder: (context, snapshot) {
        final doc = snapshot.data ??
            (request.documentName != null
                ? _minimalDocument(request.documentId, request.documentName!)
                : null);
        final fileName = doc?.name ?? request.documentName ?? 'Document';

        final displayName = (request.requesterName?.trim().isNotEmpty == true)
            ? request.requesterName!.trim()
            : (request.requesterEmail ?? 'Unknown user');

        final initial =
            displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

        final timeAgo = _timeAgo(request.createdAt);

        // NOTE: "requesterRole" (e.g. "Product") isn't part of the current
        // EditRequest model. Add it to the model/API response and uncomment
        // below if you want it to show alongside the time.
        final roleAndTime = [
          // if (request.requesterRole != null && request.requesterRole!.isNotEmpty)
          //   request.requesterRole,
          if (timeAgo.isNotEmpty) timeAgo,
        ].join(' • ');

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(10),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C4CE0),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        if (roleAndTime.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              roleAndTime,
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 13,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (doc != null)
                    IconButton(
                      tooltip: 'View document',
                      onPressed: () => _viewDocument(doc),
                      icon: const Icon(Icons.visibility_outlined, size: 20),
                      color: Colors.grey.shade600,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F5FA),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'wants to edit',
                      style:
                          TextStyle(color: Colors.grey.shade500, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _fileTypeIcon(doc?.name ?? fileName),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            fileName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (request.reason != null &&
                        request.reason!.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        request.reason!.trim(),
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12.5,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final notes = await _promptRejectNotes();
                        if (notes == null) return;
                        await _service.reject(request.id, reviewNotes: notes);
                        _load();
                      },
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Decline'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade600,
                        side: BorderSide(color: Colors.grey.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
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
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Approve'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2B41BD),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// Card design for the "My Requests" tab — shows the document the current
  /// user requested to edit, when it was requested, a status chip
  /// (Pending / Approved / Rejected), and a View button.
  Widget _buildMyRequestTile(EditRequest request) {
    final chip = _statusChipStyle(request.status);
    final timeAgo = _timeAgo(request.createdAt);

    return FutureBuilder<Document?>(
      future: _getDocument(request.documentId, nameHint: request.documentName),
      builder: (context, snapshot) {
        final doc = snapshot.data ??
            (request.documentName != null
                ? _minimalDocument(request.documentId, request.documentName!)
                : null);
        final title = doc?.name ?? request.documentName ?? 'Document';

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(10),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2B41BD).withAlpha(18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _fileTypeIcon(title, size: 20, color: const Color(0xFF2B41BD)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        if (timeAgo.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Requested $timeAgo',
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 13,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: chip.bg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(chip.icon, size: 14, color: chip.fg),
                        const SizedBox(width: 4),
                        Text(
                          chip.text,
                          style: TextStyle(
                            color: chip.fg,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (request.reason != null &&
                  request.reason!.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F5FA),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    request.reason!.trim(),
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
              if (doc != null) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _viewDocument(doc),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('View'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2B41BD),
                      side: BorderSide(color: Colors.grey.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
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
        itemBuilder: (context, index) => actions
            ? _buildPendingRequestTile(requests[index])
            : _buildMyRequestTile(requests[index]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: Colors.black),
        title:  Text('Edit Requests',style: w700_16Poppins()),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
          bottom: TabBar(
          indicatorColor:  Color(0xFF4F63FF),
          labelStyle:  w400_16Poppins(color:  Color(0xFF4F63FF)),
          unselectedLabelStyle:w400_16Poppins(color: Colors.black45) ,
          controller: _tabController,
          tabs:  [
            Tab(child: Text('My Requests',style: w400_16Poppins(),),),
            Tab(child:Text('Pending',style: w400_16Poppins(),)),
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