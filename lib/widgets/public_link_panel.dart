import 'package:digi_sanchika/models/sharing_models.dart';
import 'package:digi_sanchika/services/api_client.dart';
import 'package:digi_sanchika/services/sharing_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// "Anyone with the link" sharing for a document or folder, backed by
/// /api/public-links (create, list active, update flags/expiry, revoke).
class PublicLinkPanel extends StatefulWidget {
  final bool isFolder;
  final String entityId;

  const PublicLinkPanel({
    super.key,
    required this.isFolder,
    required this.entityId,
  });

  @override
  State<PublicLinkPanel> createState() => _PublicLinkPanelState();
}

class _PublicLinkPanelState extends State<PublicLinkPanel> {
  final SharingService _service = SharingService();

  /// Expiry choices: null days means "never expires".
  static const Map<String, int?> _expiryOptions = {
    '1 day': 1,
    '7 days': 7,
    '30 days': 30,
    '90 days': 90,
    'Never': null,
  };

  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<PublicLinkGrant> _links = [];

  bool _allowView = true;
  bool _allowDownload = false;
  String _expiry = '7 days';

  ShareEntityType get _type =>
      widget.isFolder ? ShareEntityType.folder : ShareEntityType.document;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final links = await _service.listPublicLinks(
        type: _type,
        entityId: widget.entityId,
      );
      if (!mounted) return;
      setState(() {
        _links = links;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// Create returns `url` (built from the server's FRONTEND_URL); list does
  /// not, so rebuild it from the API host for older rows.
  String _linkUrl(PublicLinkGrant link) {
    if (link.url != null && link.url!.isNotEmpty) return link.url!;
    final api = Uri.tryParse(ApiClient.instance.baseUrl);
    final origin = api == null || api.host.isEmpty
        ? ''
        : '${api.scheme}://${api.host}${api.hasPort ? ':${api.port}' : ''}';
    return '$origin/public/${link.token}';
  }

  String _expiryLabel(PublicLinkGrant link) {
    final expires = DateTime.tryParse(link.expiresAt ?? '');
    if (expires == null || expires.year >= 9999) return 'Never expires';
    final local = expires.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    return 'Expires $d/$m/${local.year}';
  }

  void _toast(String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _create() async {
    setState(() => _saving = true);
    try {
      final days = _expiryOptions[_expiry];
      final link = await _service.createPublicLink(
        type: _type,
        entityId: widget.entityId,
        allowView: _allowView,
        allowDownload: _allowDownload,
        expiryDays: days,
        noExpiry: days == null,
      );
      if (!mounted) return;
      if (link == null) {
        _toast('Could not create link');
      } else {
        await Clipboard.setData(ClipboardData(text: _linkUrl(link)));
        _toast('Link created and copied');
        setState(() => _links = [link, ..._links]);
      }
    } catch (e) {
      if (mounted) _toast('Could not create link: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _update(
    PublicLinkGrant link, {
    bool? allowView,
    bool? allowDownload,
  }) async {
    final ok = await _service.updatePublicLink(
      link: link,
      allowView: allowView,
      allowDownload: allowDownload,
    );
    if (!mounted) return;
    if (!ok) {
      _toast('Could not update link');
      return;
    }
    setState(() {
      _links = [
        for (final l in _links)
          l.id == link.id
              ? PublicLinkGrant(
                  id: l.id,
                  token: l.token,
                  url: l.url,
                  allowView: allowView ?? l.allowView,
                  allowDownload: allowDownload ?? l.allowDownload,
                  expiresAt: l.expiresAt,
                )
              : l,
      ];
    });
  }

  Future<void> _revoke(PublicLinkGrant link) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke link?'),
        content: const Text('Anyone using this link will lose access.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revoke', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await _service.revokePublicLink(link.id);
    if (!mounted) return;
    if (ok) {
      setState(() => _links.removeWhere((l) => l.id == link.id));
      _toast('Link revoked');
    } else {
      _toast('Could not revoke link');
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _buildCreateCard(),
          const SizedBox(height: 16),
          Text(
            'Active links',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  TextButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            )
          else if (_links.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No active links.',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ),
            )
          else
            ..._links.map(_buildLinkCard),
        ],
      ),
    );
  }

  Widget _buildCreateCard() {
    return Card(
      elevation: 0,
      color: Colors.grey.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.withAlpha(40)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Anyone with the link can open this '
              '${widget.isFolder ? 'folder' : 'document'} without signing in.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _allowView,
              onChanged: _saving ? null : (v) => setState(() => _allowView = v),
              title: const Text('Allow view'),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _allowDownload,
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _allowDownload = v),
              title: const Text('Allow download'),
            ),
            DropdownButtonFormField<String>(
              initialValue: _expiry,
              items: _expiryOptions.keys
                  .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                  .toList(),
              onChanged: _saving
                  ? null
                  : (v) {
                      if (v != null) setState(() => _expiry = v);
                    },
              decoration: InputDecoration(
                labelText: 'Expires after',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _create,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_link),
                label: Text(_saving ? 'Creating...' : 'Create link'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinkCard(PublicLinkGrant link) {
    final url = _linkUrl(link);
    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.withAlpha(40)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.indigo.withAlpha(24),
                  child: const Icon(Icons.link, color: Colors.indigo),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        _expiryLabel(link),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Copy',
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: url));
                    if (mounted) _toast('Link copied');
                  },
                ),
                IconButton(
                  tooltip: 'Share',
                  icon: const Icon(Icons.share_outlined),
                  onPressed: () => Share.share(url),
                ),
                IconButton(
                  tooltip: 'Revoke',
                  icon: const Icon(Icons.block, color: Colors.red),
                  onPressed: () => _revoke(link),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: link.allowView,
                    onChanged: (v) => _update(link, allowView: v),
                    title: const Text('View'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: link.allowDownload,
                    onChanged: (v) => _update(link, allowDownload: v),
                    title: const Text('Download'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
