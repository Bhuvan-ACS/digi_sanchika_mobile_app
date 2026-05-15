import 'package:digi_sanchika/models/document_comment.dart';
import 'package:digi_sanchika/services/comments_service.dart';
import 'package:flutter/material.dart';

class DocumentCommentsSheet {
  static Future<void> show({
    required BuildContext context,
    required String documentId,
    int? version,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DocumentCommentsSheetWidget(
        documentId: documentId,
        version: version,
      ),
    );
  }
}

class _DocumentCommentsSheetWidget extends StatefulWidget {
  final String documentId;
  final int? version;

  const _DocumentCommentsSheetWidget({
    required this.documentId,
    required this.version,
  });

  @override
  State<_DocumentCommentsSheetWidget> createState() =>
      _DocumentCommentsSheetWidgetState();
}

class _DocumentCommentsSheetWidgetState
    extends State<_DocumentCommentsSheetWidget> {
  final CommentsService _service = CommentsService();
  final TextEditingController _newController = TextEditingController();

  bool _loading = true;
  bool _sending = false;
  String? _error;
  CollaborationStatus _status =
      const CollaborationStatus(level: 'view_only', isLocked: false);
  List<DocumentComment> _comments = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _newController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await _service.listRootComments(
        widget.documentId,
        version: widget.version,
      );
      if (!mounted) return;
      if (resp == null) {
        setState(() {
          _loading = false;
          _error = 'Failed to load comments';
        });
        return;
      }
      setState(() {
        _status = resp.collaborationStatus;
        _comments = resp.comments;
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

  bool get _canCreateRoot {
    if (_status.isLocked) return false;
    return _status.level != 'view_only';
  }

  Future<void> _createRootComment() async {
    final text = _newController.text.trim();
    if (text.isEmpty) return;
    if (!_canCreateRoot) return;

    setState(() => _sending = true);
    try {
      final created = await _service.createComment(
        widget.documentId,
        content: text,
        parentId: null,
        visibility: 'public',
        documentVersion: widget.version,
      );
      if (!mounted) return;
      if (created == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to add comment')),
        );
        return;
      }
      _newController.clear();
      await _load();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openThread(DocumentComment root) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CommentThreadSheet(
        documentId: widget.documentId,
        root: root,
      ),
    );
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Container(
      constraints: BoxConstraints(maxHeight: h * 0.92),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          ListTile(
            title: const Text('Comments', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('Level: ${_status.level}${_status.isLocked ? ' • Locked' : ''}'),
            trailing: IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
          ),
          if (_status.isLocked)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: const Text(
                'Collaboration is locked. New threads are disabled; replies are still allowed.',
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: _load,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _comments.isEmpty
                        ? Center(
                            child: Text(
                              'No comments yet',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _comments.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final c = _comments[index];
                              return ListTile(
                                onTap: () => _openThread(c),
                                title: _MentionsText(
                                  c.content,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${c.creatorName ?? 'User'}${c.replyCount > 0 ? ' • ${c.replyCount} replies' : ''}${c.isResolved ? ' • Resolved' : ''}',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                              );
                            },
                          ),
          ),
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: 12 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newController,
                    enabled: _canCreateRoot && !_sending,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: _status.level == 'view_only'
                          ? 'No comment permission'
                          : (_status.isLocked ? 'Locked' : 'Add a comment…'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: (!_canCreateRoot || _sending) ? null : _createRootComment,
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentThreadSheet extends StatefulWidget {
  final String documentId;
  final DocumentComment root;

  const _CommentThreadSheet({required this.documentId, required this.root});

  @override
  State<_CommentThreadSheet> createState() => _CommentThreadSheetState();
}

class _CommentThreadSheetState extends State<_CommentThreadSheet> {
  final CommentsService _service = CommentsService();
  final TextEditingController _replyController = TextEditingController();

  bool _loading = true;
  bool _sending = false;
  String? _error;
  DocumentComment? _root;
  List<DocumentComment> _replies = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await _service.getThread(widget.documentId, widget.root.id);
      if (!mounted) return;
      if (resp == null) {
        setState(() {
          _loading = false;
          _error = 'Failed to load thread';
        });
        return;
      }
      setState(() {
        _root = resp.root;
        _replies = resp.replies;
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

  Future<void> _reply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final created = await _service.createComment(
        widget.documentId,
        content: text,
        parentId: widget.root.id,
      );
      if (!mounted) return;
      if (created == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to reply')),
        );
        return;
      }
      _replyController.clear();
      await _load();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Container(
      constraints: BoxConstraints(maxHeight: h * 0.92),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          ListTile(
            title: const Text('Thread', style: TextStyle(fontWeight: FontWeight.w600)),
            trailing: IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!)))
                    : ListView(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_root?.creatorName ?? widget.root.creatorName ?? 'User', style: const TextStyle(fontWeight: FontWeight.w600)),
                                const SizedBox(height: 6),
                                _MentionsText(widget.root.content),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          for (final r in _replies)
                            ListTile(
                              title: Text(r.creatorName ?? 'User'),
                              subtitle: _MentionsText(r.content),
                            ),
                        ],
                      ),
          ),
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: 12 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _replyController,
                    enabled: !_sending,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Reply…',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _sending ? null : _reply,
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MentionsText extends StatelessWidget {
  final String text;
  final int? maxLines;
  final TextOverflow? overflow;

  const _MentionsText(this.text, {this.maxLines, this.overflow});

  static final RegExp _mentionRx = RegExp(r'@\[([^\]]+)\]\(([a-f0-9-]{6,})\)');

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    int last = 0;
    for (final m in _mentionRx.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      final name = m.group(1) ?? 'User';
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.indigo.shade100),
            ),
            child: Text('@$name', style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      );
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }

    return RichText(
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: spans.isEmpty ? [TextSpan(text: text)] : spans,
      ),
    );
  }
}

