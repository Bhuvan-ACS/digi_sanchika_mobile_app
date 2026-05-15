import 'package:flutter/material.dart';
import 'package:digi_sanchika/services/version_comments_service.dart';
import 'package:digi_sanchika/models/version_comment.dart';

class VersionCommentsScreen extends StatefulWidget {
  final String documentId;
  final String versionTo;
  final String? versionFrom;

  const VersionCommentsScreen({
    super.key,
    required this.documentId,
    this.versionTo = 'latest',
    this.versionFrom,
  });

  @override
  State<VersionCommentsScreen> createState() => _VersionCommentsScreenState();
}

class _VersionCommentsScreenState extends State<VersionCommentsScreen> {
  final VersionCommentsService _service = VersionCommentsService();
  bool _isLoading = true;
  List<VersionComment> _comments = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final items = await _service.listComments(
      widget.documentId,
      versionTo: widget.versionTo,
      versionFrom: widget.versionFrom,
    );
    if (!mounted) return;
    setState(() {
      _comments = items;
      _isLoading = false;
    });
  }

  Future<void> _addComment() async {
    if (!mounted) return;
    final versionController = TextEditingController();
    final commentController = TextEditingController();
    bool? ok;
    try {
      ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Add Comment'),
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

    if (ok != true) return;
    final version = versionController.text.trim();
    final comment = commentController.text.trim();
    if (version.isEmpty || comment.isEmpty) {
      _showSnack('Version and comment are required', isError: true);
      return;
    }

    final success = await _service.addComment(
      documentId: widget.documentId,
      version: version,
      comment: comment,
    );
    _showSnack(success ? 'Comment added' : 'Failed to add comment',
        isError: !success);
    _load();
  }

  Future<void> _resolveComment(String id) async {
    final ok = await _service.resolveComment(id);
    _showSnack(ok ? 'Comment resolved' : 'Failed to resolve', isError: !ok);
    _load();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Version Comments'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _comments.isEmpty
              ? const Center(child: Text('No comments yet'))
              : ListView.builder(
                  itemCount: _comments.length,
                  itemBuilder: (context, index) {
                    final comment = _comments[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: ListTile(
                        title: Text('Version ${comment.version}'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(comment.comment),
                            if (comment.createdAt != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  comment.createdAt!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.check_circle,
                            color: Colors.green,
                          ),
                          onPressed: () => _resolveComment(comment.id),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addComment,
        child: const Icon(Icons.add_comment),
      ),
    );
  }
}
