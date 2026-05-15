import 'package:flutter/material.dart';
import 'package:digi_sanchika/models/folder_tree_node.dart';
import 'package:digi_sanchika/utils/app_theme.dart';

class BreadcrumbWidget extends StatelessWidget {
  final List<FolderTreeNode> path;
  final Function(FolderTreeNode?) onFolderTap;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? activeColor;

  const BreadcrumbWidget({
    super.key,
    required this.path,
    required this.onFolderTap,
    this.backgroundColor,
    this.textColor,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.surface,
        border: const Border(
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHomeItem(),
            if (path.isNotEmpty) ..._buildPathItems(),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeItem() {
    final isActive = path.isEmpty;
    final color = activeColor ?? AppColors.primary;

    return _BreadcrumbItem(
      icon: Icons.home_rounded,
      label: 'Home',
      isActive: isActive,
      activeColor: color,
      inactiveColor: textColor ?? AppColors.textSecondary,
      onTap: isActive ? null : () => onFolderTap(null),
    );
  }

  List<Widget> _buildPathItems() {
    final items = <Widget>[];
    final shouldShowEllipsis = path.length > 4;
    final displayPath = shouldShowEllipsis
        ? [path.first, ...path.sublist(path.length - 2)]
        : path;

    for (int i = 0; i < displayPath.length; i++) {
      final node = displayPath[i];
      final isLast = i == displayPath.length - 1;
      final isActive = isLast && path.length == displayPath.length;

      // Separator
      items.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Icon(
            Icons.chevron_right_rounded,
            size: 16,
            color: AppColors.textTertiary,
          ),
        ),
      );

      // Ellipsis popup for hidden folders
      if (shouldShowEllipsis && i == 1) {
        items.add(
          PopupMenuButton<FolderTreeNode>(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            tooltip: 'Show hidden folders',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(AppRadius.xs),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(
                Icons.more_horiz_rounded,
                size: 14,
                color: AppColors.textSecondary,
              ),
            ),
            itemBuilder: (_) {
              final hidden = path.sublist(1, path.length - 2);
              return hidden
                  .map(
                    (f) => PopupMenuItem<FolderTreeNode>(
                      value: f,
                      child: Row(
                        children: [
                          const Icon(Icons.folder_rounded,
                              size: 15, color: AppColors.warning),
                          const SizedBox(width: 8),
                          Text(f.name,
                              style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                  )
                  .toList();
            },
            onSelected: (f) => onFolderTap(f),
          ),
        );

        items.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 2),
            child: Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: AppColors.textTertiary,
            ),
          ),
        );
      }

      items.add(
        _BreadcrumbItem(
          icon: Icons.folder_rounded,
          label: node.name,
          isActive: isActive,
          activeColor: activeColor ?? AppColors.primary,
          inactiveColor: textColor ?? AppColors.textSecondary,
          onTap: isActive ? null : () => onFolderTap(node),
        ),
      );
    }

    return items;
  }
}

class _BreadcrumbItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback? onTap;

  const _BreadcrumbItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.activeColor,
    required this.inactiveColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isActive
              ? activeColor.withAlpha(22)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.xs),
          border: isActive
              ? Border.all(color: activeColor.withAlpha(60))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isActive
                  ? (icon == Icons.folder_rounded
                      ? AppColors.warning
                      : activeColor)
                  : inactiveColor,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? activeColor : inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact breadcrumb for smaller spaces
class CompactBreadcrumbWidget extends StatelessWidget {
  final List<FolderTreeNode> path;
  final Function(FolderTreeNode?) onFolderTap;

  const CompactBreadcrumbWidget({
    super.key,
    required this.path,
    required this.onFolderTap,
  });

  @override
  Widget build(BuildContext context) {
    if (path.isEmpty) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.home_rounded, size: 15, color: AppColors.textSecondary),
          SizedBox(width: 5),
          Text(
            'Home',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }

    final current = path.last;

    return PopupMenuButton<FolderTreeNode?>(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppRadius.xs),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_rounded,
                size: 14, color: AppColors.warning),
            const SizedBox(width: 6),
            Text(
              current.name,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more_rounded,
                size: 16, color: AppColors.textSecondary),
          ],
        ),
      ),
      itemBuilder: (_) {
        final items = <PopupMenuEntry<FolderTreeNode?>>[];
        items.add(
          PopupMenuItem<FolderTreeNode?>(
            value: null,
            child: Row(
              children: const [
                Icon(Icons.home_rounded,
                    size: 15, color: AppColors.textSecondary),
                SizedBox(width: 8),
                Text('Home', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
        );
        for (final folder in path) {
          items.add(
            PopupMenuItem<FolderTreeNode?>(
              value: folder,
              child: Row(
                children: [
                  SizedBox(width: folder.depth * 12.0),
                  const Icon(Icons.folder_rounded,
                      size: 15, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Text(folder.name,
                      style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          );
        }
        return items;
      },
      onSelected: (f) => onFolderTap(f),
    );
  }
}
