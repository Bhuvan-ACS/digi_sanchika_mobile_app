// lib/models/folder_tree_node.dart

class FolderTreeNode {
  // Backend uses UUID strings for ids. Keep this as String to avoid cast issues.
  final String id;
  final String name;
  final String? parentId;
  final DateTime createdAt;
  final String owner;
  final List<FolderTreeNode> children;
  bool isExpanded;
  int depth;
  bool isSelected;

  FolderTreeNode({
    required this.id,
    required this.name,
    this.parentId,
    required this.createdAt,
    required this.owner,
    List<FolderTreeNode>? children,
    this.isExpanded = false,
    this.depth = 0,
    this.isSelected = false,
  }) : children = children ?? [];

  // Add child to this node
  void addChild(FolderTreeNode child) {
    child.depth = depth + 1;
    children.add(child);
  }

  // Remove child by ID
  bool removeChild(String childId) {
    children.removeWhere((child) => child.id == childId);
    return true;
  }

  // Find node by ID recursively
  FolderTreeNode? findNodeById(String id) {
    if (this.id == id) return this;

    for (var child in children) {
      final found = child.findNodeById(id);
      if (found != null) return found;
    }

    return null;
  }

  // Get path from root to this node
  List<FolderTreeNode> getPath(List<FolderTreeNode> rootNodes) {
    List<FolderTreeNode> path = [];

    FolderTreeNode? findParentPath(
        FolderTreeNode? target, List<FolderTreeNode> currentPath) {
      if (target == null) return null;

      for (var node in rootNodes) {
        final result = _searchPath(node, target, [...currentPath]);
        if (result != null) {
          path = result;
          return target;
        }
      }
      return null;
    }

    findParentPath(this, []);
    return path;
  }

  List<FolderTreeNode>? _searchPath(
      FolderTreeNode current, FolderTreeNode target, List<FolderTreeNode> path) {
    path.add(current);

    if (current.id == target.id) {
      return path;
    }

    for (var child in current.children) {
      final result = _searchPath(child, target, List.from(path));
      if (result != null) return result;
    }

    return null;
  }

  // Get total count of all descendants
  int getTotalChildCount() {
    int count = children.length;
    for (var child in children) {
      count += child.getTotalChildCount();
    }
    return count;
  }

  // Get direct document count (would need to be passed from backend)
  int getDocumentCount() {
    // This should be populated from backend data
    return 0; // Placeholder
  }

  // Sort children alphabetically
  void sortChildren() {
    children.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    for (var child in children) {
      child.sortChildren();
    }
  }

  // Toggle expansion state
  void toggleExpanded() {
    isExpanded = !isExpanded;
  }

  // Expand all descendants
  void expandAll() {
    isExpanded = true;
    for (var child in children) {
      child.expandAll();
    }
  }

  // Collapse all descendants
  void collapseAll() {
    isExpanded = false;
    for (var child in children) {
      child.collapseAll();
    }
  }

  // Check if this folder has children
  bool get hasChildren => children.isNotEmpty;

  // Check if this is a root folder
  bool get isRoot => parentId == null;

  // Get display name with item count
  String get displayName => hasChildren ? '$name (${children.length})' : name;

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'parent_id': parentId,
      'created_at': createdAt.toIso8601String(),
      'owner': owner,
      'children': children.map((c) => c.toJson()).toList(),
      'is_expanded': isExpanded,
      'depth': depth,
    };
  }

  // Create from JSON
  factory FolderTreeNode.fromJson(Map<String, dynamic> json, {int depth = 0}) {
    final node = FolderTreeNode(
      id: json['id']?.toString() ?? '',
      name: (json['name'] ?? 'Unnamed').toString(),
      parentId: (json['parent_id'] ?? json['parentId'])?.toString(),
      createdAt:
          DateTime.tryParse((json['created_at'] ?? json['createdAt']).toString()) ??
              DateTime.now(),
      owner: json['owner'] as String? ?? 'Unknown',
      depth: depth,
      isExpanded: json['is_expanded'] as bool? ?? false,
    );

    if (json['children'] != null) {
      final childrenList = json['children'] as List;
      for (var childJson in childrenList) {
        node.addChild(FolderTreeNode.fromJson(
          childJson as Map<String, dynamic>,
          depth: depth + 1,
        ));
      }
    }

    return node;
  }

  // Create a copy with modifications
  FolderTreeNode copyWith({
    String? id,
    String? name,
    String? parentId,
    DateTime? createdAt,
    String? owner,
    List<FolderTreeNode>? children,
    bool? isExpanded,
    int? depth,
    bool? isSelected,
  }) {
    return FolderTreeNode(
      id: id ?? this.id,
      name: name ?? this.name,
      parentId: parentId ?? this.parentId,
      createdAt: createdAt ?? this.createdAt,
      owner: owner ?? this.owner,
      children: children ?? List.from(this.children),
      isExpanded: isExpanded ?? this.isExpanded,
      depth: depth ?? this.depth,
      isSelected: isSelected ?? this.isSelected,
    );
  }

  @override
  String toString() {
    return 'FolderTreeNode(id: $id, name: $name, depth: $depth, children: ${children.length})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FolderTreeNode && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
