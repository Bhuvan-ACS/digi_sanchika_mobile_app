import 'package:digi_sanchika/models/shared_by_me_model.dart';
import 'package:digi_sanchika/models/sharing_models.dart';
import 'package:digi_sanchika/presentations/Screens/shared_folder_screen.dart';
import 'package:digi_sanchika/services/sharing_service.dart';
import 'package:digi_sanchika/utils/app_fonts.dart';
import 'package:digi_sanchika/utils/responsive_helper.dart';
import 'package:digi_sanchika/widgets/dismiss_keyboard.dart';
import 'package:digi_sanchika/widgets/responsive_page.dart';
import 'package:digi_sanchika/widgets/section_panel.dart';
import 'package:digi_sanchika/models/app_view_mode.dart';
import 'package:digi_sanchika/services/my_documents_service.dart';
import 'package:digi_sanchika/widgets/ai_sparkle_button.dart';
import 'package:digi_sanchika/widgets/home_components.dart';
import 'package:digi_sanchika/widgets/layout_capsule.dart';
import 'package:digi_sanchika/widgets/share_empty_illustration.dart';
import 'package:flutter/material.dart';

class SharedByMeScreen extends StatefulWidget {
  const SharedByMeScreen({super.key});

  @override
  State<SharedByMeScreen> createState() => _SharedByMeScreenState();
}

class _SharedByMeScreenState extends State<SharedByMeScreen> {
  final SharingService _service = SharingService();
  final TextEditingController _searchController = TextEditingController();

  // Raw data
  List<DocumentElement> _documents = [];
  List<FolderElement> _folders = [];

  // Filtered
  List<DocumentElement> _filteredDocuments = [];
  List<FolderElement> _filteredFolders = [];

  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';

  // Collapsible states — keyed by share id
  final Map<String, bool> _expandedStates = {};

  AppViewMode _viewMode = AppViewMode.list;
  bool _aiSearching = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Data loading ─────────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    if (!mounted) return;
    _expandedStates.clear();
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = '';
    });

    try {
      final result = await _service.sharedByMe();
      if (!mounted) return;
      setState(() {
        _documents = result.documents;
        _folders = result.folders;
        _filteredDocuments = List.from(_documents);
        _filteredFolders = List.from(_folders);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading shared-by-me data: $e');
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = 'Failed to load data. Please try again.';
        _isLoading = false;
      });
    }
  }

  // ── Search / filter ──────────────────────────────────────────────────────────

  void _filter(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filteredDocuments = List.from(_documents);
        _filteredFolders = List.from(_folders);
      } else {
        _filteredDocuments = _documents.where((e) {
          return e.document.name.toLowerCase().contains(q) ||
              e.document.classification.toLowerCase().contains(q) ||
              e.document.mimeType.toLowerCase().contains(q) ||
              e.sharedWithAll.any(
                (u) =>
                    u.fullName.toLowerCase().contains(q) ||
                    u.email.toLowerCase().contains(q),
              );
        }).toList();

        _filteredFolders = _folders.where((e) {
          return e.folder.name.toLowerCase().contains(q) ||
              e.sharedWithAll.any(
                (u) =>
                    u.fullName.toLowerCase().contains(q) ||
                    u.email.toLowerCase().contains(q),
              );
        }).toList();
      }
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _filter('');
  }

  /// AI assistant search over documents I own (POST /search/semantic, scope
  /// `my`), narrowed to the ones I've shared. Folders still match by name or
  /// recipient.
  Future<void> _runAiSearch(String query) async {
    setState(() => _aiSearching = true);
    final result = await MyDocumentsService.semanticSearch(
      query: query,
      scope: 'my',
      limit: 50,
    );
    if (!mounted) return;
    setState(() => _aiSearching = false);
    final results = result['results'];
    if (result['success'] != true || results is! List) {
      _filter(query);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result['error'] ?? 'AI search failed'}. Showing name matches.',
          ),
        ),
      );
      return;
    }
    final ids = results.map((r) => r['documentId'].toString()).toList();
    _filter(query);
    setState(() {
      _filteredDocuments =
          _documents.where((e) => ids.contains(e.document.id)).toList()
            ..sort(
              (a, b) => ids
                  .indexOf(a.document.id)
                  .compareTo(ids.indexOf(b.document.id)),
            );
    });
  }

  ShareGrant _grantFor(Share share, ShareEntityType type) =>
      share.viaGroup != null
      ? ShareGrant.group({'id': share.id}, entityType: type)
      : ShareGrant.direct({'id': share.id}, entityType: type);

  void _openFolder(FolderElement item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SharedFolderScreen(
          folderId: item.folder.id,
          folderName: item.folder.name,
          userName: item.sharedWith.fullName,
        ),
      ),
    );
  }

  /// Grid cards keep the list card's full details one tap away.
  void _showDocumentDetails(DocumentElement item, int index) {
    final key = item.share.id.isNotEmpty ? item.share.id : 'doc_$index';
    _expandedStates[key] = true;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16),
        backgroundColor: Colors.transparent,
        child: SingleChildScrollView(child: _buildDocumentCard(item, index)),
      ),
    ).then((_) {
      if (mounted) setState(() => _expandedStates[key] = false);
    });
  }

  // ── Grid layouts ─────────────────────────────────────────────────────────────

  /// Same cell geometry as the document gallery: 12px gaps, 4px inset.
  Widget _buildGrid(List<Widget> cards) {
    final compact = _viewMode == AppViewMode.grid3x3;
    final columns = compact ? 3 : 2;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final card in cards)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: SizedBox(
                  width: width - 8,
                  height: compact ? 112 : null,
                  child: card,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _gridCard({
    required IconData icon,
    required Color color,
    required String name,
    required String subtitle,
    required bool isRevoked,
    required VoidCallback? onTap,
    required VoidCallback onRevoke,
  }) {
    final compact = _viewMode == AppViewMode.grid3x3;
    final tint = isRevoked ? Colors.grey : color;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x96E1E5F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(22),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: compact ? 28 : 52,
                      height: compact ? 28 : 52,
                      decoration: BoxDecoration(
                        color: tint.withAlpha(20),
                        borderRadius: BorderRadius.circular(compact ? 9 : 16),
                      ),
                      child: Icon(icon, color: tint, size: compact ? 18 : 30),
                    ),
                    const Spacer(),
                    if (isRevoked)
                      Icon(
                        Icons.block,
                        color: Colors.grey,
                        size: compact ? 14 : 18,
                      )
                    else
                      SizedBox.square(
                        dimension: compact ? 24 : 32,
                        child: IconButton(
                          tooltip: 'Revoke access',
                          padding: EdgeInsets.zero,
                          iconSize: compact ? 16 : 20,
                          icon: Icon(
                            Icons.link_off_rounded,
                            color: Colors.red.shade400,
                          ),
                          onPressed: onRevoke,
                        ),
                      ),
                  ],
                ),
                SizedBox(height: compact ? 4 : 10),
                Text(
                  name,
                  maxLines: compact ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 13 : 14.5,
                    height: 1.25,
                    fontWeight: compact ? FontWeight.w700 : FontWeight.w600,
                    color: isRevoked ? Colors.grey : const Color(0xFF1E293B),
                    decoration: isRevoked ? TextDecoration.lineThrough : null,
                  ),
                ),
                SizedBox(height: compact ? 2 : 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 10 : 12,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _recipientsLabel(List<SharedWith> users) {
    if (users.isEmpty) return 'Shared';
    if (users.length == 1) return 'With ${users.first.fullName}';
    return 'With ${users.length} people';
  }

  Widget _buildFolderGridCard(FolderElement item) {
    return _gridCard(
      icon: Icons.folder,
      color: Colors.amber.shade700,
      name: item.folder.name,
      subtitle: _recipientsLabel(item.sharedWithAll),
      isRevoked: item.share.isRevoked,
      onTap: item.share.isRevoked ? null : () => _openFolder(item),
      onRevoke: () => _revokeShare(
        _grantFor(item.share, ShareEntityType.folder),
        item.folder.name,
      ),
    );
  }

  Widget _buildDocumentGridCard(DocumentElement item, int index) {
    return _gridCard(
      icon: _mimeIcon(item.document.mimeType),
      color: _mimeColor(item.document.mimeType),
      name: item.document.name,
      subtitle: _recipientsLabel(item.sharedWithAll),
      isRevoked: item.share.isRevoked,
      onTap: () => _showDocumentDetails(item, index),
      onRevoke: () => _revokeShare(
        _grantFor(item.share, ShareEntityType.document),
        item.document.name,
      ),
    );
  }

  // ── Revoke ───────────────────────────────────────────────────────────────────

  Future<void> _revokeShare(ShareGrant grant, String itemName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke Access'),
        content: Text(
          'Are you sure you want to revoke access to "$itemName"? '
          'The recipient will no longer be able to access this item.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Revoke', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _service.revokeShare(grant);
      _showSnackBar('Access revoked successfully', Colors.green);
      _loadData();
    } catch (e) {
      _showSnackBar('Failed to revoke access', Colors.red);
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _formatDate(DateTime date) {
    if (date.year >= 9999) return 'No Expiry';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day-$month-${date.year}';
  }

  String _expiryText(DateTime expiresAt) {
    if (expiresAt.year >= 9999) return 'No Expiry';
    final diff = expiresAt.difference(DateTime.now());
    if (diff.isNegative) return 'Expired';
    if (diff.inHours < 24) {
      final h = diff.inMinutes <= 60 ? 1 : diff.inHours + 1;
      return 'In $h hour${h > 1 ? 's' : ''}';
    }
    final days = diff.inDays;
    return days == 1 ? 'Tomorrow' : 'In ${days + 1} days';
  }

  Color _expiryColor(DateTime expiresAt) {
    if (expiresAt.year >= 9999) return Colors.grey;
    final diff = expiresAt.difference(DateTime.now());
    if (diff.isNegative) return Colors.grey;
    if (diff.inHours < 24) return Colors.red;
    if (diff.inDays < 7) return Colors.orange;
    return Colors.green;
  }

  IconData _mimeIcon(String mimeType) {
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf;
    if (mimeType.contains('word') || mimeType.contains('document')) {
      return Icons.description;
    }
    if (mimeType.contains('sheet') || mimeType.contains('excel')) {
      return Icons.table_chart;
    }
    if (mimeType.contains('presentation') || mimeType.contains('powerpoint')) {
      return Icons.slideshow;
    }
    if (mimeType.contains('image')) return Icons.image;
    if (mimeType.contains('text')) return Icons.text_fields;
    return Icons.insert_drive_file;
  }

  Color _mimeColor(String mimeType) {
    if (mimeType.contains('pdf')) return Colors.red;
    if (mimeType.contains('word') || mimeType.contains('document')) {
      return Colors.blue;
    }
    if (mimeType.contains('sheet') || mimeType.contains('excel')) {
      return Colors.green;
    }
    if (mimeType.contains('presentation') || mimeType.contains('powerpoint')) {
      return Colors.orange;
    }
    if (mimeType.contains('image')) return Colors.purple;
    return Colors.indigo;
  }

  // ── Detail row (matches shared_files_screen style) ───────────────────────────

  Widget _buildDetailRowWithIcon(
    String label,
    String value,
    IconData iconData, {
    required ResponsiveHelper r,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: r.p(4)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(iconData, size: r.sp(16), color: Colors.grey.shade600),
          SizedBox(width: r.p(12)),
          SizedBox(
            width: r.p(100),
            child: Text(label, style: w400_14Poppins(color: Colors.black87)),
          ),
          SizedBox(width: r.p(8)),
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

  // ── Section header (identical to shared_files_screen) ────────────────────────

  Widget _buildSectionHeader(String title, int count, IconData icon) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.indigo),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.indigo,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.indigo.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.indigo,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Folder card (matches shared_files_screen _buildFolderCard style) ─────────

  Widget _buildFolderCard(FolderElement item) {
    final folder = item.folder;
    final share = item.share;
    final isRevoked = share.isRevoked;
    final recipientNames = item.sharedWithAll.map((u) => u.fullName).join(', ');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(
          Icons.folder,
          color: isRevoked ? Colors.grey : Colors.amber,
          size: 32,
        ),
        title: Text(
          folder.name,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: isRevoked ? Colors.grey : Colors.black87,
            decoration: isRevoked ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (recipientNames.isNotEmpty)
              Text('Shared with: $recipientNames'),
            Text('Permission: ${share.permission.toUpperCase()}'),
            RichText(
              text: TextSpan(
                text: 'Expires: ',
                style: const TextStyle(fontSize: 13, color: Colors.black87),
                children: [
                  TextSpan(
                    text: _expiryText(share.expiresAt),
                    style: TextStyle(
                      fontSize: 13,
                      color: _expiryColor(share.expiresAt),
                    ),
                  ),
                ],
              ),
            ),
            if (isRevoked)
              const Text(
                'Revoked',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
          ],
        ),
        trailing: isRevoked
            ? const Icon(Icons.block, color: Colors.grey, size: 18)
            : IconButton(
                tooltip: 'Revoke access',
                icon: Icon(Icons.link_off_rounded,
                    color: Colors.red.shade400, size: 20),
                onPressed: () => _revokeShare(
                  share.viaGroup != null
                      ? ShareGrant.group({'id': share.id},
                          entityType: ShareEntityType.folder)
                      : ShareGrant.direct({'id': share.id},
                          entityType: ShareEntityType.folder),
                  folder.name,
                ),
              ),
        onTap: isRevoked
            ? null
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SharedFolderScreen(
                      folderId: folder.id,
                      folderName: folder.name,
                      userName: item.sharedWith.fullName,
                    ),
                  ),
                ),
      ),
    );
  }

  // ── Document card (matches shared_files_screen collapsible card style) ────────

  Widget _buildDocumentCard(DocumentElement item, int index) {
    final r = context.r;
    final doc = item.document;
    final share = item.share;
    final icon = _mimeIcon(doc.mimeType);
    final color = _mimeColor(doc.mimeType);
    final isRevoked = share.isRevoked;

    final uniqueKey = share.id.isNotEmpty ? share.id : 'doc_$index';
    final isExpanded = _expandedStates[uniqueKey] ?? false;

    final recipientNames =
        item.sharedWithAll.map((u) => u.fullName).join(', ');

    return InkWell(
      borderRadius: BorderRadius.circular(r.p(12)),
      onTap: () => setState(
          () => _expandedStates[uniqueKey] = !isExpanded),
      child: Card(
        margin: EdgeInsets.symmetric(vertical: r.p(5)),
        elevation: 0.5,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(r.p(12))),
        child: Padding(
          padding: EdgeInsets.all(r.p(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top row ───────────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // File icon
                  Container(
                    padding: EdgeInsets.all(r.p(12)),
                    decoration: BoxDecoration(
                      color: (isRevoked ? Colors.grey : color).withAlpha(20),
                      borderRadius: BorderRadius.circular(r.p(8)),
                    ),
                    child: Icon(
                      icon,
                      color: isRevoked ? Colors.grey : color,
                      size: r.sp(32),
                    ),
                  ),
                  SizedBox(width: r.p(10)),
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
                                    doc.name,
                                    style: TextStyle(
                                      fontSize: r.sp(16),
                                      fontWeight: FontWeight.bold,
                                      color: isRevoked
                                          ? Colors.grey
                                          : Colors.black87,
                                      decoration: isRevoked
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                    maxLines: isExpanded ? 2 : 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    'v${doc.version}  •  ${_formatDate(share.createdAt)}',
                                    style: w400_14Poppins(
                                        color: Colors.grey.shade700),
                                  ),
                                ],
                              ),
                            ),
                            // Expand / collapse button
                            GestureDetector(
                              onTap: () => setState(() =>
                                  _expandedStates[uniqueKey] = !isExpanded),
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
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // ── Collapsible content ───────────────────────────────────
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: SizedBox(
                  height: isExpanded ? null : 0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: r.p(16)),
                      const Divider(height: 1),
                      SizedBox(height: r.p(12)),

                      // Recipients
                      if (recipientNames.isNotEmpty)
                        _buildDetailRowWithIcon(
                          'Shared with',
                          recipientNames,
                          Icons.people_outline,
                          r: r,
                        ),

                      // Classification
                      if (doc.classification.isNotEmpty)
                        _buildDetailRowWithIcon(
                          'Classification',
                          doc.classification,
                          Icons.security,
                          r: r,
                        ),

                      // Permission
                      _buildDetailRowWithIcon(
                        'Permission',
                        share.permission.toUpperCase(),
                        Icons.lock_outline,
                        r: r,
                      ),

                      // Allow download
                      _buildDetailRowWithIcon(
                        'Download',
                        share.allowDownload ? 'Allowed' : 'Not allowed',
                        Icons.download_outlined,
                        r: r,
                      ),

                      // Allow edit
                      _buildDetailRowWithIcon(
                        'Edit',
                        share.allowEdit ? 'Allowed' : 'Not allowed',
                        Icons.edit_outlined,
                        r: r,
                      ),

                      // Expiry
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.schedule,
                              size: r.sp(16), color: Colors.grey.shade600),
                          SizedBox(width: r.p(12)),
                          SizedBox(
                            width: r.p(100),
                            child: Text(
                              'Expires in: ',
                              style: w400_14Poppins(color: Colors.black87),
                            ),
                          ),
                          SizedBox(width: r.p(8)),
                          Expanded(
                            child: Text(
                              _expiryText(share.expiresAt),
                              style: w400_14Poppins(
                                  color: _expiryColor(share.expiresAt)),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: r.p(16)),

                      // ── Action buttons ────────────────────────────────
                      Row(
                        children: [
                          // Revoke button
                          Expanded(
                            child: isRevoked
                                ? OutlinedButton.icon(
                                    onPressed: null,
                                    icon: Icon(Icons.block, size: r.sp(18)),
                                    label: const Text('Revoked'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.grey,
                                      side: const BorderSide(
                                          color: Colors.grey),
                                      padding: EdgeInsets.symmetric(
                                          vertical: r.p(10)),
                                    ),
                                  )
                                : OutlinedButton.icon(
                                    onPressed: () => _revokeShare(
                                      share.viaGroup != null
                                          ? ShareGrant.group(
                                              {'id': share.id},
                                              entityType:
                                                  ShareEntityType.document,
                                            )
                                          : ShareGrant.direct(
                                              {'id': share.id},
                                              entityType:
                                                  ShareEntityType.document,
                                            ),
                                      doc.name,
                                    ),
                                    icon: Icon(Icons.link_off_rounded,
                                        size: r.sp(18)),
                                    label: const Text('Revoke'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red,
                                      side: const BorderSide(
                                          color: Colors.red),
                                      padding: EdgeInsets.symmetric(
                                          vertical: r.p(10)),
                                    ),
                                  ),
                          ),
                          // Show all recipients button
                          if (item.sharedWithAll.length > 1) ...[
                            SizedBox(width: r.p(8)),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _showAllRecipients(
                                    item.sharedWithAll, doc.name, r),
                                icon: Icon(Icons.group, size: r.sp(18)),
                                label: Text(
                                    '+${item.sharedWithAll.length - 1} more'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.indigo,
                                  side: const BorderSide(color: Colors.indigo),
                                  padding: EdgeInsets.symmetric(
                                      vertical: r.p(10)),
                                ),
                              ),
                            ),
                          ],
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

  // ── All recipients bottom sheet ───────────────────────────────────────────────

  void _showAllRecipients(
      List<SharedWith> users, String itemName, ResponsiveHelper r) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(r.p(20))),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.85,
        builder: (_, controller) => Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(vertical: r.p(12)),
              child: Container(
                width: r.p(40),
                height: r.p(4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(r.p(2)),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: r.p(16)),
              child: Row(
                children: [
                  const Icon(Icons.people, color: Colors.indigo),
                  SizedBox(width: r.p(8)),
                  Expanded(
                    child: Text(
                      'Recipients — $itemName',
                      style: TextStyle(
                        fontSize: r.sp(16),
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${users.length} total',
                    style: TextStyle(
                        fontSize: r.sp(13), color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: users.length,
                itemBuilder: (_, i) {
                  final u = users[i];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: u.isGroup == true
                          ? Colors.purple.shade100
                          : Colors.indigo.shade100,
                      child: Icon(
                        u.isGroup == true ? Icons.groups : Icons.person,
                        color: u.isGroup == true
                            ? Colors.purple
                            : Colors.indigo,
                        size: r.sp(18),
                      ),
                    ),
                    title: Text(u.fullName,
                        style: TextStyle(
                            fontSize: r.sp(14),
                            fontWeight: FontWeight.w500)),
                    subtitle: Text(u.email,
                        style: TextStyle(
                            fontSize: r.sp(12),
                            color: Colors.grey.shade600)),
                    trailing: u.isGroup == true
                        ? Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: r.p(8), vertical: r.p(2)),
                            decoration: BoxDecoration(
                              color: Colors.purple.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(r.p(12)),
                            ),
                            child: Text('Group',
                                style: TextStyle(
                                    fontSize: r.sp(11),
                                    color: Colors.purple,
                                    fontWeight: FontWeight.w600)),
                          )
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Empty state (matches shared_files_screen) ─────────────────────────────────

  Widget _buildEmptyState(ResponsiveHelper r) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_searchController.text.isEmpty)
            ShareEmptyIllustration(size: r.sp(64))
          else
            Icon(
              Icons.search_off,
              size: r.sp(58),
              color: const Color(0xFF0866E9),
            ),
          SizedBox(height: r.p(20)),
          Text(
            _searchController.text.isEmpty
                ? (_hasError ? 'Unable to Load Data' : 'No Documents Sent Yet')
                : 'No Results Found',
            style: TextStyle(
              fontSize: r.sp(20),
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: r.p(10)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: r.p(40)),
            child: Text(
              _hasError
                  ? _errorMessage
                  : _searchController.text.isEmpty
                      ? 'Files and folders you share with authorised users will appear here.'
                      : 'No results found for "${_searchController.text}"',
              style:
                  TextStyle(fontSize: r.sp(14), color: Colors.grey.shade600),
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
              onPressed: _loadData,
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

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final bool bothEmpty =
        _filteredDocuments.isEmpty && _filteredFolders.isEmpty;

    return DismissKeyboard(
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F9FF),
        body: ResponsivePage(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              // ── Title (matches Shared with me) ────────────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(r.p(20), r.p(12), r.p(20), 0),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'DELEGATED ACCESS',
                            style: TextStyle(
                              color: Color(0xFF6D82A1),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.1,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'My Shared Workspace',
                            style: TextStyle(
                              color: Color(0xFF202A4A),
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'Access managed',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // ── Search bar + layout toggle (matches Shared with me) ───
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: r.p(16),
                  vertical: r.p(10),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: PillSearchField(
                            controller: _searchController,
                            hint: 'Search shared workspace...',
                            onChanged: _filter,
                            onSubmitted: _filter,
                            onClear: _clearSearch,
                            loading: _aiSearching,
                            trailing: AiSparkleButton(
                              onTap: () {
                                final query = _searchController.text.trim();
                                if (query.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Enter a search query first.',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                FocusScope.of(context).unfocus();
                                _runAiSearch(query);
                              },
                            ),
                          ),
                        ),
                        SizedBox(width: r.p(10)),
                        LayoutCapsule(
                          value: _viewMode,
                          onChanged: (mode) =>
                              setState(() => _viewMode = mode),
                        ),
                      ],
                    ),
                    SizedBox(height: r.p(8)),
                    // Stats row
                    Row(
                      children: [
                        Text(
                          '${_filteredFolders.length} folder${_filteredFolders.length == 1 ? '' : 's'}  •  '
                          '${_filteredDocuments.length} file${_filteredDocuments.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: r.sp(13),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Main content ──────────────────────────────────────────
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
                        SizedBox(height: r.p(10)),
                        Text(
                          'Loading shared items...',
                          style:
                              TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                )
              else if (bothEmpty)
                Expanded(child: _buildEmptyState(r))
              else
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadData,
                    color: Colors.indigo,
                    child: CustomScrollView(
                      slivers: [
                        // ── Folders section ───────────────────────────
                        if (_filteredFolders.isNotEmpty) ...[
                          SliverToBoxAdapter(
                            child: SectionPanel(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              header: _buildSectionHeader(
                                'Folders',
                                _filteredFolders.length,
                                Icons.folder_open,
                              ),
                              child: _viewMode == AppViewMode.list
                                  ? Column(
                                      children: [
                                        for (final folder in _filteredFolders)
                                          _buildFolderCard(folder),
                                      ],
                                    )
                                  : _buildGrid([
                                      for (final folder in _filteredFolders)
                                        _buildFolderGridCard(folder),
                                    ]),
                            ),
                          ),
                          const SliverToBoxAdapter(
                              child: SizedBox(height: 14)),
                        ],

                        // ── Files section ─────────────────────────────
                        if (_filteredDocuments.isNotEmpty) ...[
                          SliverToBoxAdapter(
                            child: SectionPanel(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              header: _buildSectionHeader(
                                'Files',
                                _filteredDocuments.length,
                                Icons.file_copy_outlined,
                              ),
                              child: _viewMode == AppViewMode.list
                                  ? Column(
                                      children: [
                                        for (int i = 0;
                                            i < _filteredDocuments.length;
                                            i++)
                                          _buildDocumentCard(
                                              _filteredDocuments[i], i),
                                      ],
                                    )
                                  : _buildGrid([
                                      for (int i = 0;
                                          i < _filteredDocuments.length;
                                          i++)
                                        _buildDocumentGridCard(
                                            _filteredDocuments[i], i),
                                    ]),
                            ),
                          ),
                        ],

                        const SliverToBoxAdapter(
                            child: SizedBox(height: 24)),
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
}