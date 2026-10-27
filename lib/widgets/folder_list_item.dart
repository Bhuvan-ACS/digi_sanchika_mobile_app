import 'package:flutter/material.dart';
import 'package:digi_sanchika/widgets/folder_illustration.dart';

/// The non-distorting folder presentation used by the folders list view.
class FolderListItem extends StatelessWidget {
  const FolderListItem({
    super.key,
    required this.name,
    required this.fileCount,
    required this.sizeLabel,
    required this.timeAgo,
    required this.onTap,
    this.onLongPress,
    this.trailing,
    this.favorite = false,
  });

  final String name;
  final int fileCount;
  final String sizeLabel;
  final String timeAgo;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  /// Shows an amber star before [trailing] when true.
  final bool favorite;

  @override
  Widget build(BuildContext context) {
    final files = '$fileCount ${fileCount == 1 ? 'file' : 'files'}';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      shadowColor: Colors.black.withOpacity(0.04),
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const SizedBox(
                  width: 46,
                  height: 46,
                  child: _FolderIconBadge(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF1E293B),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [files, sizeLabel, timeAgo]
                            .where((part) => part.isNotEmpty)
                            .join('  \u2022  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                if (favorite)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.star_rounded,
                      size: 18,
                      color: Colors.amber,
                      semanticLabel: 'Favourite',
                    ),
                  ),
                if (trailing != null) ...[
                  const SizedBox(width: 4),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FolderIconBadge extends StatelessWidget {
  const _FolderIconBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFEBF3FF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Center(
        child: FolderIllustration(size: 34),
      ),
    );
  }
}
