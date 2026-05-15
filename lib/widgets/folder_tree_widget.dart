// lib/widgets/folder_tree_widget.dart

import 'package:flutter/material.dart';
import 'package:digi_sanchika/models/folder_tree_node.dart';

class FolderTreeWidget extends StatefulWidget {
  final List<FolderTreeNode> rootNodes;
  final Function(FolderTreeNode) onFolderTap;
  final Function(FolderTreeNode)? onFolderLongPress;
  final Function(FolderTreeNode)? onCreateSubfolder;
  final Function(FolderTreeNode)? onDeleteFolder;
  final FolderTreeNode? selectedFolder;
  final bool showActions;
  final bool enableSelection;

  const FolderTreeWidget({
    super.key,
    required this.rootNodes,
    required this.onFolderTap,
    this.onFolderLongPress,
    this.onCreateSubfolder,
    this.onDeleteFolder,
    this.selectedFolder,
    this.showActions = true,
    this.enableSelection = false,
  });

  @override
  State<FolderTreeWidget> createState() => _FolderTreeWidgetState();
}

class _FolderTreeWidgetState extends State<FolderTreeWidget>
    with SingleTickerProviderStateMixin {
  FolderTreeNode? _hoveredNode;

  @override
  Widget build(BuildContext context) {
    if (widget.rootNodes.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(), // FIX: Add this
      shrinkWrap: true, // FIX: Add this
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: widget.rootNodes.length,
      itemBuilder: (context, index) {
        return _buildTreeNode(widget.rootNodes[index]);
      },
    );
  }

  Color _folderTint(FolderTreeNode node) {
    final depth = node.depth.clamp(0, 6);
    final shades = <Color>[
      const Color(0xFF2B41BD), // primary
      const Color(0xFF5C6BC0),
      const Color(0xFF7E57C2),
      const Color(0xFF26A69A),
      const Color(0xFFFFA000),
      const Color(0xFFEF5350),
      const Color(0xFF546E7A),
    ];
    return shades[depth];
  }

  Widget _folderLeadingIcon(FolderTreeNode node, {required bool isSelected}) {
    final tint = _folderTint(node);
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: isSelected ? tint : tint.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        node.children.isNotEmpty ? Icons.folder_open_rounded : Icons.folder_rounded,
        size: 20,
        color: isSelected ? Colors.white : tint,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open_outlined,
            size: 80,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            'No Folders Yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create your first folder to get started',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildTreeNode(FolderTreeNode node) {
    final isSelected = widget.selectedFolder?.id == node.id;
    final isHovered = _hoveredNode?.id == node.id;
    final hasChildren = node.children.isNotEmpty;
    final leftIndent = (node.depth * 14.0).clamp(0.0, 84.0).toDouble();
    final bgColor = isSelected
        ? const Color(0xFFEFF2FF)
        : (isHovered ? Colors.grey.shade50 : Colors.transparent);
    final borderColor =
        isSelected ? const Color(0xFFBBC6FF) : Colors.transparent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Current folder row
        MouseRegion(
          onEnter: (_) => setState(() => _hoveredNode = node),
          onExit: (_) => setState(() => _hoveredNode = null),
          child: InkWell(
            onTap: () => widget.onFolderTap(node),
            onLongPress: widget.onFolderLongPress != null
                ? () => widget.onFolderLongPress!(node)
                : null,
            child: Container(
              margin: EdgeInsets.only(
                left: leftIndent,
                right: 12,
                bottom: 6,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: borderColor,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  // Expand/Collapse button
                  if (hasChildren)
                    InkWell(
                      onTap: () {
                        setState(() {
                          node.toggleExpanded();
                        });
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        child: AnimatedRotation(
                          turns: node.isExpanded ? 0.25 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            Icons.chevron_right,
                            size: 20,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 28),

                  _folderLeadingIcon(node, isSelected: isSelected),

                  const SizedBox(width: 10),

                  // Folder name + subtitle
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          node.name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                isSelected ? FontWeight.w800 : FontWeight.w600,
                            color: isSelected
                                ? const Color(0xFF1A237E)
                                : Colors.grey.shade900,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        if (hasChildren)
                          Text(
                            '${node.children.length} subfolder${node.children.length == 1 ? '' : 's'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                      ],
                    ),
                  ),

                  if (widget.enableSelection)
                    Radio<FolderTreeNode>(
                      value: node,
                      groupValue: widget.selectedFolder,
                      onChanged: (value) {
                        if (value != null) widget.onFolderTap(value);
                      },
                      activeColor: const Color(0xFF2B41BD),
                    )
                  else ...[
                    if (hasChildren)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Text(
                          '${node.children.length}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),

                    // Action buttons (show on hover or selected)
                    if (widget.showActions && (isHovered || isSelected))
                      _buildActionButtons(node),
                  ],
                ],
              ),
            ),
          ),
        ),

        // Children (if expanded)
        if (hasChildren && node.isExpanded)
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: Column(
              children: node.children
                  .map((child) => _buildTreeNode(child))
                  .toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildActionButtons(FolderTreeNode node) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Create subfolder button
        if (widget.onCreateSubfolder != null)
          IconButton(
            icon: const Icon(Icons.create_new_folder, size: 18),
            tooltip: 'Create subfolder',
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
            color: Colors.indigo.shade600,
            onPressed: () => widget.onCreateSubfolder!(node),
          ),

        const SizedBox(width: 4),

        // Delete folder button
        if (widget.onDeleteFolder != null)
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            tooltip: 'Delete folder',
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
            color: Colors.red.shade400,
            onPressed: () => widget.onDeleteFolder!(node),
          ),
      ],
    );
  }
}

/// Compact folder tree for selection dialogs
class CompactFolderTreeWidget extends StatefulWidget {
  final List<FolderTreeNode> rootNodes;
  final Function(FolderTreeNode) onFolderSelect;
  final FolderTreeNode? selectedFolder;

  const CompactFolderTreeWidget({
    super.key,
    required this.rootNodes,
    required this.onFolderSelect,
    this.selectedFolder,
  });

  @override
  State<CompactFolderTreeWidget> createState() =>
      _CompactFolderTreeWidgetState();
}

class _CompactFolderTreeWidgetState extends State<CompactFolderTreeWidget> {
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(), // FIX: Add this
      shrinkWrap: true, // FIX: Add this
      padding: const EdgeInsets.all(8),
      itemCount: widget.rootNodes.length,
      itemBuilder: (context, index) {
        return _buildCompactNode(widget.rootNodes[index]);
      },
    );
  }

  Widget _buildCompactNode(FolderTreeNode node) {
    final isSelected = widget.selectedFolder?.id == node.id;
    final hasChildren = node.children.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => widget.onFolderSelect(node),
          child: Container(
            margin: EdgeInsets.only(left: node.depth * 16.0, bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? Colors.indigo.shade50 : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSelected ? Colors.indigo.shade300 : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                // Expand/collapse
                if (hasChildren)
                  InkWell(
                    onTap: () => setState(() => node.toggleExpanded()),
                    child: Icon(
                      node.isExpanded ? Icons.expand_more : Icons.chevron_right,
                      size: 18,
                      color: Colors.grey.shade600,
                    ),
                  )
                else
                  const SizedBox(width: 18),

                const SizedBox(width: 4),

                // Folder icon
                Icon(
                  Icons.folder,
                  size: 18,
                  color: isSelected
                      ? Colors.amber.shade700
                      : Colors.amber.shade600,
                ),

                const SizedBox(width: 8),

                // Folder name
                Expanded(
                  child: Text(
                    node.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: isSelected
                          ? Colors.indigo.shade700
                          : Colors.grey.shade800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // Selection indicator
                if (isSelected)
                  Icon(
                    Icons.check_circle,
                    size: 18,
                    color: Colors.indigo.shade600,
                  ),
              ],
            ),
          ),
        ),

        // Children
        if (hasChildren && node.isExpanded)
          Column(
            children: node.children
                .map((child) => _buildCompactNode(child))
                .toList(),
          ),
      ],
    );
  }
}

/// Folder grid view (alternative layout)
/// Folder grid view (alternative layout)
class FolderGridWidget extends StatelessWidget {
  final List<FolderTreeNode> folders;
  final Function(FolderTreeNode) onFolderTap;
  final Function(FolderTreeNode)? onFolderLongPress;
  final FolderTreeNode? selectedFolder;

  const FolderGridWidget({
    super.key,
    required this.folders,
    required this.onFolderTap,
    this.onFolderLongPress,
    this.selectedFolder,
  });

  Color _tintFor(FolderTreeNode node) {
    final depth = node.depth.clamp(0, 6);
    final shades = <Color>[
      const Color(0xFF2B41BD),
      const Color(0xFF5C6BC0),
      const Color(0xFF7E57C2),
      const Color(0xFF26A69A),
      const Color(0xFFFFA000),
      const Color(0xFFEF5350),
      const Color(0xFF546E7A),
    ];
    return shades[depth];
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      padding: const EdgeInsets.all(12), // Reduced padding
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, // Changed from 3 to 2 for more horizontal space
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.1, // Slightly wider
      ),
      itemCount: folders.length,
      itemBuilder: (context, index) {
        final folder = folders[index];
        final isSelected = selectedFolder?.id == folder.id;
        final tint = _tintFor(folder);

        return InkWell(
          onTap: () => onFolderTap(folder),
          onLongPress: onFolderLongPress != null
              ? () => onFolderLongPress!(folder)
              : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isSelected
                    ? [
                        const Color(0xFFEFF2FF),
                        const Color(0xFFF7F8FF),
                      ]
                    : [
                        Colors.white,
                        Colors.grey.shade50,
                      ],
              ),
              border: Border.all(
                color: isSelected ? const Color(0xFFBBC6FF) : Colors.grey.shade200,
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.max,
              children: [
                // Icon container with proper sizing
                Container(
                  height: 50, // Fixed height for icon container
                  width: 50, // Fixed width for icon container
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: tint.withOpacity(isSelected ? 0.18 : 0.12),
                  ),
                  child: Icon(
                    folder.children.isNotEmpty
                        ? Icons.folder_open_rounded
                        : Icons.folder_rounded,
                    size: 30,
                    color: tint,
                  ),
                ),
                const SizedBox(height: 8),

                // Folder name with proper constraints
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    folder.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: isSelected ? const Color(0xFF1A237E) : Colors.grey.shade900,
                      height: 1.2,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // Item count (only show if there are children)
                if (folder.children.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Text(
                        '${folder.children.length} subfolder${folder.children.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
