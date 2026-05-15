import 'package:digi_sanchika/models/document_annotation.dart';
import 'package:digi_sanchika/services/annotations_service.dart';
import 'package:flutter/material.dart';

class DocumentAnnotationsSheet {
  static Future<void> show({
    required BuildContext context,
    required String documentId,
    int? version,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DocumentAnnotationsSheetWidget(
        documentId: documentId,
        version: version,
      ),
    );
  }
}

class _DocumentAnnotationsSheetWidget extends StatefulWidget {
  final String documentId;
  final int? version;

  const _DocumentAnnotationsSheetWidget({
    required this.documentId,
    required this.version,
  });

  @override
  State<_DocumentAnnotationsSheetWidget> createState() =>
      _DocumentAnnotationsSheetWidgetState();
}

class _DocumentAnnotationsSheetWidgetState
    extends State<_DocumentAnnotationsSheetWidget> {
  final AnnotationsService _service = AnnotationsService();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _level = 'view_only';
  List<DocumentAnnotation> _items = const [];

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
      final resp = await _service.listAnnotations(
        widget.documentId,
        version: widget.version,
      );
      if (!mounted) return;
      if (resp == null) {
        setState(() {
          _loading = false;
          _error = 'Failed to load annotations';
        });
        return;
      }
      setState(() {
        _level = resp.collaborationLevel;
        _items = resp.annotations.where((a) => !a.isDeleted).toList();
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

  bool get _canAnnotate => _level == 'annotate' || _level == 'moderate';

  Future<void> _addStickyNote() async {
    if (!_canAnnotate) return;
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New note'),
        content: TextField(
          controller: controller,
          minLines: 1,
          maxLines: 6,
          decoration: const InputDecoration(hintText: 'Note text'),
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
    if (ok != true) return;
    final content = controller.text.trim();
    if (content.isEmpty) return;

    setState(() => _saving = true);
    try {
      final created = await _service.createAnnotation(
        widget.documentId,
        type: 'sticky_note',
        pageNumber: 1,
        x: 0.1,
        y: 0.1,
        width: 0.4,
        height: 0.2,
        content: content,
        visibility: 'public',
        documentVersion: widget.version,
      );
      if (!mounted) return;
      if (created == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to add annotation')),
        );
        return;
      }
      await _load();
    } finally {
      if (mounted) setState(() => _saving = false);
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
            title: const Text('Annotations', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('Level: $_level'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  onPressed: (!_canAnnotate || _saving) ? null : _addStickyNote,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  tooltip: _canAnnotate ? 'Add note' : 'No annotate permission',
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!)))
                    : _items.isEmpty
                        ? Center(
                            child: Text(
                              'No annotations yet',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _items.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final a = _items[index];
                              return ListTile(
                                title: Text(a.type),
                                subtitle: Text(
                                  '${a.creatorName ?? 'User'} • page ${a.pageNumber ?? '-'}',
                                ),
                                trailing: a.content != null && a.content!.trim().isNotEmpty
                                    ? const Icon(Icons.sticky_note_2_outlined)
                                    : const Icon(Icons.edit_outlined),
                                onTap: a.content == null || a.content!.trim().isEmpty
                                    ? null
                                    : () => showDialog<void>(
                                          context: context,
                                          builder: (_) => AlertDialog(
                                            title: const Text('Annotation'),
                                            content: Text(a.content!.trim()),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(context),
                                                child: const Text('Close'),
                                              ),
                                            ],
                                          ),
                                        ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

