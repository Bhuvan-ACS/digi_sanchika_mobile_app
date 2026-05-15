import 'package:digi_sanchika/models/folder_alert.dart';
import 'package:digi_sanchika/services/folder_alerts_service.dart';
import 'package:flutter/material.dart';

class FolderAlertSheet {
  static Future<void> show({
    required BuildContext context,
    required String folderId,
    required String folderName,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FolderAlertSheetWidget(
        folderId: folderId,
        folderName: folderName,
      ),
    );
  }
}

class _FolderAlertSheetWidget extends StatefulWidget {
  final String folderId;
  final String folderName;

  const _FolderAlertSheetWidget({
    required this.folderId,
    required this.folderName,
  });

  @override
  State<_FolderAlertSheetWidget> createState() => _FolderAlertSheetWidgetState();
}

class _FolderAlertSheetWidgetState extends State<_FolderAlertSheetWidget> {
  final FolderAlertsService _service = FolderAlertsService();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  FolderAlert? _alert;

  bool _onAdd = true;
  bool _onDelete = true;
  bool _onShare = false;
  bool _onEdit = false;

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
      final alert = await _service.getAlert(widget.folderId);
      if (!mounted) return;
      setState(() {
        _alert = alert;
        _onAdd = alert?.onAdd ?? true;
        _onDelete = alert?.onDelete ?? true;
        _onShare = alert?.onShare ?? false;
        _onEdit = alert?.onEdit ?? false;
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

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final updated = await _service.upsertAlert(
        widget.folderId,
        onAdd: _onAdd,
        onDelete: _onDelete,
        onShare: _onShare,
        onEdit: _onEdit,
      );
      if (!mounted) return;
      if (updated == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save alert')),
        );
        return;
      }
      setState(() => _alert = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Folder alert saved')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _unsubscribe() async {
    setState(() => _saving = true);
    try {
      final ok = await _service.deleteAlert(widget.folderId);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to unsubscribe')),
        );
        return;
      }
      setState(() {
        _alert = null;
        _onAdd = true;
        _onDelete = true;
        _onShare = false;
        _onEdit = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unsubscribed')),
      );
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
            title: const Text('Folder alerts', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(widget.folderName),
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
                        padding: const EdgeInsets.all(16),
                        children: [
                          SwitchListTile.adaptive(
                            value: _onAdd,
                            onChanged: _saving ? null : (v) => setState(() => _onAdd = v),
                            title: const Text('On add'),
                            subtitle: const Text('A document is added to the folder'),
                          ),
                          SwitchListTile.adaptive(
                            value: _onDelete,
                            onChanged: _saving ? null : (v) => setState(() => _onDelete = v),
                            title: const Text('On delete'),
                            subtitle: const Text('A document is deleted from the folder'),
                          ),
                          SwitchListTile.adaptive(
                            value: _onShare,
                            onChanged: _saving ? null : (v) => setState(() => _onShare = v),
                            title: const Text('On share'),
                            subtitle: const Text('The folder is shared with someone'),
                          ),
                          SwitchListTile.adaptive(
                            value: _onEdit,
                            onChanged: _saving ? null : (v) => setState(() => _onEdit = v),
                            title: const Text('On edit'),
                            subtitle: const Text('A document in the folder is edited'),
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
                  child: OutlinedButton.icon(
                    onPressed: (_alert == null || _saving) ? null : _unsubscribe,
                    icon: const Icon(Icons.notifications_off_outlined),
                    label: const Text('Unsubscribe'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Saving...' : (_alert == null ? 'Subscribe' : 'Save')),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

