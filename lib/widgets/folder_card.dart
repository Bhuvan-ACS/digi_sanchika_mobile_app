import 'package:flutter/material.dart';
import 'package:digi_sanchika/models/folder.dart';
import 'package:digi_sanchika/utils/app_theme.dart';

class FolderCard extends StatelessWidget {
  final Folder folder;
  final int index;
  final VoidCallback onDelete;
  final VoidCallback onShare;

  const FolderCard({
    super.key,
    required this.folder,
    required this.index,
    required this.onDelete,
    required this.onShare,
  });

  // Cycle through accent colours so folders feel visually distinct
  static const _accents = [
    AppColors.primary,
    Color(0xFF0891B2), // cyan
    Color(0xFF9333EA), // purple
    Color(0xFFEA580C), // orange
    Color(0xFF16A34A), // green
    Color(0xFFDB2777), // pink
  ];

  Color get _accent => _accents[index % _accents.length];

  @override
  Widget build(BuildContext context) {
    final color = _accent;
    final count = folder.documents.length;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.sm,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Opening folder: ${folder.name}'),
              behavior: SnackBarBehavior.floating,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Gradient icon container
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            color.withAlpha(200),
                            color,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        boxShadow: [
                          BoxShadow(
                            color: color.withAlpha(70),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.folder_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),

                    const Spacer(),

                    // Three-dot menu
                    PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      icon: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius:
                              BorderRadius.circular(AppRadius.xs),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Icon(
                          Icons.more_horiz_rounded,
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'share',
                          child: Row(
                            children: const [
                              Icon(Icons.share_rounded,
                                  size: 16, color: AppColors.primary),
                              SizedBox(width: 10),
                              Text('Share Folder'),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(height: 1),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: const [
                              Icon(Icons.delete_outline_rounded,
                                  size: 16, color: AppColors.error),
                              SizedBox(width: 10),
                              Text('Delete',
                                  style:
                                      TextStyle(color: AppColors.error)),
                            ],
                          ),
                        ),
                      ],
                      onSelected: (v) {
                        if (v == 'share') onShare();
                        if (v == 'delete') onDelete();
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Folder name
                Text(
                  folder.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 6),

                // Item count badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withAlpha(16),
                    borderRadius:
                        BorderRadius.circular(AppRadius.pill),
                    border: Border.all(color: color.withAlpha(45)),
                  ),
                  child: Text(
                    '$count ${count == 1 ? 'item' : 'items'}',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
