import 'package:flutter/material.dart';
import 'package:digi_sanchika/models/document.dart';
import 'package:digi_sanchika/utils/app_theme.dart';
import 'package:digi_sanchika/widgets/status_chip.dart';

class DocumentCard extends StatelessWidget {
  final Document document;
  final int index;
  final VoidCallback onDownload;
  final VoidCallback onViewVersions;
  final VoidCallback onShare;
  final VoidCallback onDelete;
  final VoidCallback onViewDetails;

  const DocumentCard({
    super.key,
    required this.document,
    required this.index,
    required this.onDownload,
    required this.onViewVersions,
    required this.onShare,
    required this.onDelete,
    required this.onViewDetails,
  });

  // ── File type mapping ────────────────────────────────────────────────────────
  static const _icons = <String, IconData>{
    'pdf': Icons.picture_as_pdf_rounded,
    'doc': Icons.description_rounded,
    'docx': Icons.description_rounded,
    'xls': Icons.table_chart_rounded,
    'xlsx': Icons.table_chart_rounded,
    'ppt': Icons.slideshow_rounded,
    'pptx': Icons.slideshow_rounded,
    'txt': Icons.text_snippet_rounded,
    'jpg': Icons.image_rounded,
    'jpeg': Icons.image_rounded,
    'png': Icons.image_rounded,
    'gif': Icons.gif_box_rounded,
    'mp4': Icons.video_file_rounded,
    'mov': Icons.video_file_rounded,
    'mp3': Icons.audio_file_rounded,
    'wav': Icons.audio_file_rounded,
    'zip': Icons.folder_zip_rounded,
    'rar': Icons.folder_zip_rounded,
  };

  static const _colors = <String, Color>{
    'pdf': AppColors.filePdf,
    'doc': AppColors.fileWord,
    'docx': AppColors.fileWord,
    'xls': AppColors.fileExcel,
    'xlsx': AppColors.fileExcel,
    'ppt': AppColors.filePpt,
    'pptx': AppColors.filePpt,
    'txt': AppColors.fileText,
    'jpg': AppColors.fileImage,
    'jpeg': AppColors.fileImage,
    'png': AppColors.fileImage,
    'gif': AppColors.fileImage,
    'mp4': AppColors.fileVideo,
    'mov': AppColors.fileVideo,
    'mp3': AppColors.fileAudio,
    'wav': AppColors.fileAudio,
    'zip': AppColors.fileDefault,
    'rar': AppColors.fileDefault,
  };

  Color get _typeColor {
    final ext = document.type.toLowerCase().replaceAll('.', '');
    return _colors[ext] ?? AppColors.fileDefault;
  }

  IconData get _typeIcon {
    final ext = document.type.toLowerCase().replaceAll('.', '');
    return _icons[ext] ?? Icons.insert_drive_file_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final color = _typeColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border(
          left: BorderSide(color: color, width: 4),
          top: const BorderSide(color: AppColors.border),
          right: const BorderSide(color: AppColors.border),
          bottom: const BorderSide(color: AppColors.border),
        ),
        boxShadow: AppShadows.sm,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onViewDetails,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──────────────────────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // File type icon bubble
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: color.withAlpha(20),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Icon(_typeIcon, color: color, size: 24),
                    ),
                    const SizedBox(width: 12),

                    // Name + metadata
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            document.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              if (document.size.isNotEmpty) ...[
                                Icon(Icons.data_usage_rounded,
                                    size: 12, color: AppColors.textTertiary),
                                const SizedBox(width: 3),
                                Text(
                                  document.size,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                                const SizedBox(width: 10),
                              ],
                              if (document.uploadDate.isNotEmpty) ...[
                                Icon(Icons.calendar_today_rounded,
                                    size: 12, color: AppColors.textTertiary),
                                const SizedBox(width: 3),
                                Text(
                                  document.uploadDate,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),

                    // File type pill
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withAlpha(18),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(color: color.withAlpha(50)),
                      ),
                      child: Text(
                        document.type.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: color,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),

                // ── Metadata chips ───────────────────────────────────────────
                const SizedBox(height: 12),
                const Divider(color: AppColors.divider, height: 1),
                const SizedBox(height: 10),

                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (document.owner.isNotEmpty)
                      _MetaChip(
                        icon: Icons.person_outline_rounded,
                        label: document.owner,
                      ),
                    if (document.folder.isNotEmpty)
                      _MetaChip(
                        icon: Icons.folder_outlined,
                        label: document.folder,
                      ),
                    if (document.classification.isNotEmpty)
                      _MetaChip(
                        icon: Icons.shield_outlined,
                        label: document.classification,
                      ),
                    if (document.keyword.isNotEmpty)
                      _MetaChip(
                        icon: Icons.label_outline_rounded,
                        label: document.keyword,
                      ),
                    if (document.sharingType.isNotEmpty)
                      StatusChip.fromString(document.sharingType),
                  ],
                ),

                if (document.details.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    document.details,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                // ── Action row ───────────────────────────────────────────────
                const SizedBox(height: 14),
                const Divider(color: AppColors.divider, height: 1),
                const SizedBox(height: 10),

                Row(
                  children: [
                    _ActionButton(
                      icon: Icons.download_rounded,
                      label: 'Download',
                      color: AppColors.success,
                      onTap: onDownload,
                    ),
                    const SizedBox(width: 8),
                    _ActionButton(
                      icon: Icons.history_rounded,
                      label: 'Versions',
                      color: AppColors.primary,
                      onTap: onViewVersions,
                    ),
                    const SizedBox(width: 8),
                    _ActionButton(
                      icon: Icons.share_rounded,
                      label: 'Share',
                      color: AppColors.warning,
                      onTap: onShare,
                    ),
                    const Spacer(),
                    // Delete — icon only, always last
                    _IconActionButton(
                      icon: Icons.delete_outline_rounded,
                      color: AppColors.error,
                      onTap: onDelete,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Internal helpers ─────────────────────────────────────────────────────────

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.xs),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withAlpha(14),
          borderRadius: BorderRadius.circular(AppRadius.xs),
          border: Border.all(color: color.withAlpha(45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _IconActionButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.xs),
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color.withAlpha(14),
          borderRadius: BorderRadius.circular(AppRadius.xs),
          border: Border.all(color: color.withAlpha(45)),
        ),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }
}
