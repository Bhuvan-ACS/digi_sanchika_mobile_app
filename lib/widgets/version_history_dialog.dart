import 'package:digi_sanchika/models/document.dart';
import 'package:digi_sanchika/models/version_info.dart';
import 'package:digi_sanchika/services/api_service.dart';
import 'package:digi_sanchika/services/document_opener_service.dart';
import 'package:digi_sanchika/services/versions_service.dart';
import 'package:flutter/material.dart';

class VersionHistoryDialog {
  static Future<void> show(
    BuildContext context, {
    required Document document,
    VoidCallback? onRestored,
  }) async {
    if (!ApiService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot view versions while offline'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final versionsService = VersionsService();
    final opener = DocumentOpenerService();

    List<VersionInfo> versions = [];
    try {
      versions = await versionsService.listVersions(document.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load versions: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (!context.mounted) return;
    if (versions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No versions found'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    int parseVersion(String v) => int.tryParse(v.trim()) ?? -1;
    versions.sort((a, b) => parseVersion(b.version).compareTo(parseVersion(a.version)));

    String? selected = versions.first.version;
    String? compareFrom =
        versions.length > 1 ? versions[1].version : versions.first.version;
    String? compareTo = versions.first.version;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          VersionInfo selectedInfo() {
            final match = versions.firstWhere(
              (v) => v.version == selected,
              orElse: () => versions.first,
            );
            return match;
          }

          String formatWhen(String? iso) {
            if (iso == null || iso.trim().isEmpty) return '';
            try {
              final dt = DateTime.parse(iso).toLocal();
              final y = dt.year.toString().padLeft(4, '0');
              final m = dt.month.toString().padLeft(2, '0');
              final d = dt.day.toString().padLeft(2, '0');
              final hh = dt.hour.toString().padLeft(2, '0');
              final mm = dt.minute.toString().padLeft(2, '0');
              return '$d-$m-$y $hh:$mm';
            } catch (_) {
              return iso;
            }
          }

          Future<void> viewSelected() async {
            final info = selectedInfo();
            Navigator.pop(dialogContext);
            await opener.openDocumentVersion(
              context: context,
              documentId: document.id,
              versionNumber: info.version,
              originalFileName: info.name.isNotEmpty ? info.name : document.name,
            );
          }

          Future<void> compareSelected() async {
            final fromV = (compareFrom ?? '').trim();
            final toV = (compareTo ?? '').trim();
            if (fromV.isEmpty || toV.isEmpty) return;
            if (fromV == toV) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Choose two different versions to compare'),
                  backgroundColor: Colors.orange,
                ),
              );
              return;
            }

            if (!context.mounted) return;
            showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => const Center(child: CircularProgressIndicator()),
            );
            Map<String, dynamic>? resp;
            try {
              resp = await versionsService.compareText(
                documentId: document.id,
                versionFrom: fromV,
                versionTo: toV,
              );
            } catch (_) {}
            if (context.mounted) Navigator.pop(context);

            if (!context.mounted) return;
            if (resp == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Compare failed'),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }

            final diff = resp['diff'] is Map
                ? Map<String, dynamic>.from(resp['diff'] as Map)
                : Map<String, dynamic>.from(resp);

            final summary = diff['summary']?.toString() ?? '';
            final diffType = diff['diffType']?.toString() ?? '';
            final extractionStatus = diff['extractionStatus']?.toString() ?? '';
            final changes = diff['changes'];
            final changeCount = changes is List ? changes.length : 0;

            await showDialog<void>(
              context: context,
              builder: (_) => Dialog(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Compare v$fromV → v$toV',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (diffType.isNotEmpty) _infoRow('Type', diffType),
                        if (extractionStatus.isNotEmpty)
                          _infoRow('Status', extractionStatus),
                        if (summary.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(summary),
                        ],
                        const SizedBox(height: 10),
                        _infoRow('Changes', changeCount.toString()),
                        if (changes is List && changes.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          for (final c in changes.take(6))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text('• ${c.toString()}'),
                            ),
                          if (changes.length > 6)
                            Text('… and ${changes.length - 6} more'),
                        ],
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          Future<void> restoreSelected() async {
            final info = selectedInfo();
            final controller = TextEditingController();
            if (!context.mounted) return;
            final ok = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: Text('Restore version ${info.version}?'),
                content: TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'Reason (optional)',
                  ),
                  maxLines: 2,
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Restore'),
                  ),
                ],
              ),
            );
            final reason = controller.text.trim();
            controller.dispose();
            if (ok != true) return;

            if (!context.mounted) return;
            showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => const Center(child: CircularProgressIndicator()),
            );
            final resp = await versionsService.restore(
              documentId: document.id,
              sourceVersion: info.version,
              reason: reason.isEmpty ? null : reason,
            );
            if (context.mounted) Navigator.pop(context);

            final success = resp['success'] == true;
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    success
                        ? (resp['message']?.toString() ?? 'Restored successfully')
                        : (resp['message']?.toString() ?? 'Restore failed'),
                  ),
                  backgroundColor: success ? Colors.green : Colors.red,
                ),
              );
            }
            if (success) {
              onRestored?.call();
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            }
          }

          final latestVersion = versions.first.version;

          final items = <DropdownMenuItem<String>>[
            for (final v in versions)
              DropdownMenuItem(
                value: v.version,
                child: Text('v${v.version}'),
              ),
          ];

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.history_rounded, color: Color(0xFF2B41BD)),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Document Versions',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close_rounded),
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Compare row
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2B41BD).withAlpha(14),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF2B41BD).withAlpha(28)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: compareFrom,
                              items: items,
                              decoration: const InputDecoration(
                                labelText: 'From',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) => setDialogState(() => compareFrom = v),
                            ),
                          ),
                          const SizedBox(width: 10),
                          IconButton(
                            onPressed: () {
                              setDialogState(() {
                                final tmp = compareFrom;
                                compareFrom = compareTo;
                                compareTo = tmp;
                              });
                            },
                            icon: const Icon(Icons.swap_horiz_rounded),
                            tooltip: 'Swap',
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: compareTo,
                              items: items,
                              decoration: const InputDecoration(
                                labelText: 'To',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) => setDialogState(() => compareTo = v),
                            ),
                          ),
                          const SizedBox(width: 10),
                          IconButton(
                            tooltip: 'Compare (web only)',
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Compare is currently available only on the web.',
                                  ),
                                  backgroundColor: Colors.black87,
                                ),
                              );
                            },
                            icon: const Icon(Icons.info_outline_rounded),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    Text(
                      'Select a version',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    const SizedBox(height: 8),

                    Expanded(
                      child: ListView.separated(
                        itemCount: versions.length,
                        separatorBuilder: (_, index) => const SizedBox(height: 8),
                        itemBuilder: (_, index) {
                          final v = versions[index];
                          final when = formatWhen(v.createdAt);
                          final meta = [
                            if ((v.authorName ?? '').trim().isNotEmpty)
                              'By ${v.authorName}',
                            if (when.isNotEmpty) when,
                            if ((v.changeNote ?? '').trim().isNotEmpty)
                              v.changeNote!,
                          ].where((s) => s.trim().isNotEmpty).join(' • ');

                          final isLatest = v.version == latestVersion;
                          final isSelected = v.version == selected;

                          return Material(
                            color: isSelected
                                ? const Color(0xFF2B41BD).withAlpha(12)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => setDialogState(() => selected = v.version),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                child: Row(
                                  children: [
                                    Radio<String>(
                                      value: v.version,
                                      groupValue: selected,
                                      onChanged: (val) =>
                                          setDialogState(() => selected = val),
                                      activeColor: const Color(0xFF2B41BD),
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                'Version ${v.version}',
                                                style: const TextStyle(fontWeight: FontWeight.w700),
                                              ),
                                              const SizedBox(width: 8),
                                              if (isLatest)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: Colors.green.withAlpha(18),
                                                    borderRadius: BorderRadius.circular(999),
                                                    border: Border.all(color: Colors.green.withAlpha(40)),
                                                  ),
                                                  child: const Text(
                                                    'Latest',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w700,
                                                      color: Colors.green,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          if (meta.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              meta,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(color: Colors.grey.shade700),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: restoreSelected,
                            icon: const Icon(Icons.restore_rounded),
                            label: const Text('Restore'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: viewSelected,
                            icon: const Icon(Icons.visibility_rounded),
                            label: const Text('View'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 54,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
