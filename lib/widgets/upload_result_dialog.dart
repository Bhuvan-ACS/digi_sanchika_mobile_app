import 'package:flutter/material.dart';

class UploadResultDialog extends StatelessWidget {
  final String title;
  final String? subtitle;
  final int total;
  final int uploaded;
  final int failed;
  final int savedLocally;
  final String? destinationLabel;
  final List<Map<String, String>> failedDetails;

  const UploadResultDialog({
    super.key,
    required this.title,
    this.subtitle,
    required this.total,
    required this.uploaded,
    required this.failed,
    this.savedLocally = 0,
    this.destinationLabel,
    this.failedDetails = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ok = failed == 0 && uploaded > 0;
    final icon = ok ? Icons.check_circle_rounded : Icons.info_rounded;
    final iconColor = ok ? Colors.green.shade700 : Colors.orange.shade800;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      title: Row(
        children: [
          Icon(icon, color: iconColor, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                Text(
                  subtitle!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.black54,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _chip(
                    label: 'Total',
                    value: total.toString(),
                    color: Colors.blueGrey,
                    icon: Icons.folder_copy_rounded,
                  ),
                  _chip(
                    label: 'Uploaded',
                    value: uploaded.toString(),
                    color: Colors.green.shade700,
                    icon: Icons.cloud_done_rounded,
                  ),
                  if (savedLocally > 0)
                    _chip(
                      label: 'Saved locally',
                      value: savedLocally.toString(),
                      color: const Color(0xFF2B41BD),
                      icon: Icons.save_rounded,
                    ),
                  _chip(
                    label: 'Failed',
                    value: failed.toString(),
                    color: failed == 0 ? Colors.green.shade700 : Colors.red,
                    icon: failed == 0
                        ? Icons.check_rounded
                        : Icons.error_outline_rounded,
                  ),
                ],
              ),
              if (destinationLabel != null &&
                  destinationLabel!.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F6FB),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.withAlpha(35)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.folder_rounded, color: Color(0xFF2B41BD)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          destinationLabel!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (failedDetails.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'Failed items',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                ...failedDetails.take(8).map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withAlpha(12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.red.withAlpha(40)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.close_rounded,
                            color: Colors.red.shade700,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  e['file'] ?? 'Unknown',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  e['reason'] ?? 'Unknown error',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.black54,
                                    height: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (failedDetails.length > 8)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '+${failedDetails.length - 8} more failed item(s)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.black54,
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF2B41BD),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }

  static Widget _chip({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

