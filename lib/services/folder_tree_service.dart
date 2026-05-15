import 'package:flutter/foundation.dart';
import 'package:digi_sanchika/models/folder_tree_node.dart';
import 'package:digi_sanchika/services/api_client.dart';
import 'package:dio/dio.dart';

class FolderTreeService {
  static final FolderTreeService _instance = FolderTreeService._internal();
  factory FolderTreeService() => _instance;
  FolderTreeService._internal();

  List<FolderTreeNode>? _cachedTree;
  FolderTreeNode? _currentNode;
  DateTime? _lastFetchTime;
  static const _cacheDuration = Duration(minutes: 5);

  List<FolderTreeNode> _navigationHistory = [];

  List<FolderTreeNode>? get cachedTree => _cachedTree;
  FolderTreeNode? get currentNode => _currentNode;
  List<FolderTreeNode> get navigationHistory => _navigationHistory;

  Dio get _dio => ApiClient.instance.dio;

  /// Fetch direct child folders for a given parent folder using the `/documents` API,
  /// since `/folders` commonly returns only root-level folders (no recursion).
  Future<List<FolderTreeNode>> fetchChildFolders({
    required FolderTreeNode parent,
  }) async {
    try {
      final response = await _dio.get(
        '/documents',
        queryParameters: {'folderId': parent.id},
      );

      if (response.statusCode != 200) {
        if (kDebugMode) {
          print(
            '[Folders] children fetch failed parent=${parent.id} status=${response.statusCode}',
          );
        }
        return [];
      }

      final data = response.data;
      final Map<String, dynamic> map =
          data is Map<String, dynamic> ? Map<String, dynamic>.from(data) : {};
      final rawFolders = map['folders'];
      final List<dynamic> foldersList =
          rawFolders is List ? rawFolders : <dynamic>[];

      final children = <FolderTreeNode>[];
      for (final f in foldersList) {
        if (f is! Map && f is! Map<String, dynamic>) continue;
        final folder = Map<String, dynamic>.from(f as Map);
        final id = folder['id']?.toString();
        if (id == null || id.isEmpty) continue;
        children.add(
          FolderTreeNode(
            id: id,
            name: (folder['name'] ?? 'Unnamed').toString(),
            parentId: parent.id,
            createdAt:
                DateTime.tryParse(folder['created_at']?.toString() ?? '') ??
                    DateTime.now(),
            owner: folder['owner']?.toString() ?? 'Current User',
            depth: parent.depth + 1,
          ),
        );
      }

      // Ensure stable UX ordering
      children.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (kDebugMode) {
        print(
          '[Folders] loaded ${children.length} children for "${parent.name}" (${parent.id})',
        );
      }
      return children;
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching child folders for ${parent.id}: $e');
      }
      return [];
    }
  }

  Future<List<FolderTreeNode>> fetchFolderTree({bool forceRefresh = false}) async {
    try {
      if (!forceRefresh &&
          _cachedTree != null &&
          _lastFetchTime != null &&
          DateTime.now().difference(_lastFetchTime!) < _cacheDuration) {
        return _cachedTree!;
      }

      final response = await _dio.get('/folders');
      if (response.statusCode == 200) {
        final data = response.data;
        List<FolderTreeNode> tree;

        if (data is List) {
          tree = _buildTreeFromFlatList(data);
        } else if (data is Map<String, dynamic> && data['items'] is List) {
          tree = _buildTreeFromFlatList(data['items'] as List);
        } else {
          tree = _buildTreeFromNested(data);
        }

        for (var node in tree) {
          node.sortChildren();
        }

        _cachedTree = tree;
        _lastFetchTime = DateTime.now();
        return tree;
      }
      _cachedTree = [];
      _lastFetchTime = DateTime.now();
      return [];
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching folder tree: $e');
      }
      return _cachedTree ?? [];
    }
  }

  List<FolderTreeNode> _buildTreeFromNested(dynamic data) {
    if (data is List) {
      return buildTreeFromResponse(data);
    }
    if (data is Map<String, dynamic> && data['folders'] is List) {
      return buildTreeFromResponse(data['folders'] as List);
    }
    return [];
  }

  List<FolderTreeNode> _buildTreeFromFlatList(List<dynamic> data) {
    final nodes = <String, FolderTreeNode>{};
    final roots = <FolderTreeNode>[];

    for (var folderData in data) {
      final map = Map<String, dynamic>.from(folderData);
      final rawId = map['id'];
      if (rawId == null) {
        // Skip invalid rows rather than crashing / polluting the tree.
        continue;
      }

      final id = rawId.toString();
      final rawParentId = map['parent_id'] ?? map['parentId'];
      final parentId = rawParentId == null ? null : rawParentId.toString();
      final node = FolderTreeNode(
        id: id,
        name: map['name']?.toString() ?? 'Unnamed',
        parentId: parentId,
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
            DateTime.now(),
        owner: map['owner']?.toString() ?? 'Current User',
        depth: 0,
      );
      nodes[id] = node;
    }

    for (var node in nodes.values) {
      if (node.parentId != null && nodes.containsKey(node.parentId)) {
        final parent = nodes[node.parentId]!;
        parent.addChild(node);
      } else {
        roots.add(node);
      }
    }

    return roots;
  }

  List<FolderTreeNode> buildTreeFromResponse(List<dynamic> data,
      {int depth = 0}) {
    final nodes = <FolderTreeNode>[];
    for (var folderData in data) {
      final node = FolderTreeNode(
        id: folderData['id']?.toString() ?? '',
        name: (folderData['name'] ?? 'Unnamed').toString(),
        parentId: (folderData['parent_id'] ?? folderData['parentId'])?.toString(),
        createdAt: DateTime.tryParse(folderData['created_at']?.toString() ?? '') ??
            DateTime.now(),
        owner: 'Current User',
        depth: depth,
      );
      if (folderData['children'] != null && folderData['children'] is List) {
        final childrenData = folderData['children'] as List;
        for (var childData in childrenData) {
          final childNode = _buildSingleNode(childData, depth + 1);
          if (childNode != null) {
            node.addChild(childNode);
          }
        }
      }
      nodes.add(node);
    }
    return nodes;
  }

  FolderTreeNode? _buildSingleNode(dynamic data, int depth) {
    try {
      final node = FolderTreeNode(
        id: data['id']?.toString() ?? '',
        name: (data['name'] ?? 'Unnamed').toString(),
        parentId: (data['parent_id'] ?? data['parentId'])?.toString(),
        createdAt: DateTime.tryParse(data['created_at']?.toString() ?? '') ??
            DateTime.now(),
        owner: 'Current User',
        depth: depth,
      );
      if (data['children'] != null && data['children'] is List) {
        final childrenData = data['children'] as List;
        for (var childData in childrenData) {
          final childNode = _buildSingleNode(childData, depth + 1);
          if (childNode != null) {
            node.addChild(childNode);
          }
        }
      }
      return node;
    } catch (e) {
      if (kDebugMode) {
        print('Error building node: $e');
      }
      return null;
    }
  }

  void navigateToFolder(FolderTreeNode node) {
    _currentNode = node;
    _navigationHistory.add(node);
  }

  void navigateToParent() {
    if (_navigationHistory.length > 1) {
      _navigationHistory.removeLast();
      _currentNode = _navigationHistory.last;
    } else {
      navigateToRoot();
    }
  }

  void navigateToRoot() {
    _currentNode = null;
    _navigationHistory.clear();
  }

  List<FolderTreeNode> getBreadcrumbPath() {
    if (_currentNode == null || _cachedTree == null) {
      return [];
    }
    return _currentNode!.getPath(_cachedTree!);
  }

  FolderTreeNode? findNodeById(String id) {
    if (_cachedTree == null) return null;
    for (var rootNode in _cachedTree!) {
      final found = rootNode.findNodeById(id);
      if (found != null) return found;
    }
    return null;
  }

  void expandFolder(String folderId) {
    final node = findNodeById(folderId);
    if (node != null) node.isExpanded = true;
  }

  void collapseFolder(String folderId) {
    final node = findNodeById(folderId);
    if (node != null) node.isExpanded = false;
  }

  void toggleFolderExpansion(String folderId) {
    final node = findNodeById(folderId);
    if (node != null) node.toggleExpanded();
  }

  void expandAll() {
    if (_cachedTree == null) return;
    for (var node in _cachedTree!) {
      node.expandAll();
    }
  }

  void collapseAll() {
    if (_cachedTree == null) return;
    for (var node in _cachedTree!) {
      node.collapseAll();
    }
  }

  List<FolderTreeNode> getFlatList() {
    if (_cachedTree == null) return [];
    List<FolderTreeNode> flatList = [];
    void addToList(FolderTreeNode node) {
      flatList.add(node);
      for (var child in node.children) {
        addToList(child);
      }
    }
    for (var rootNode in _cachedTree!) {
      addToList(rootNode);
    }
    return flatList;
  }

  List<FolderTreeNode> getFoldersByParentId(String? parentId) {
    if (_cachedTree == null) return [];
    if (parentId == null) {
      return _cachedTree!;
    }
    final parentNode = findNodeById(parentId);
    return parentNode?.children ?? [];
  }

  List<FolderTreeNode> searchFolders(String query) {
    if (_cachedTree == null || query.isEmpty) return [];
    final results = <FolderTreeNode>[];
    final lowerQuery = query.toLowerCase();
    void searchInNode(FolderTreeNode node) {
      if (node.name.toLowerCase().contains(lowerQuery)) {
        results.add(node);
      }
      for (var child in node.children) {
        searchInNode(child);
      }
    }
    for (var rootNode in _cachedTree!) {
      searchInNode(rootNode);
    }
    return results;
  }

  void clearCache() {
    _cachedTree = null;
    _lastFetchTime = null;
    _currentNode = null;
    _navigationHistory.clear();
  }

  Map<String, int> getStatistics() {
    if (_cachedTree == null) {
      return {'total': 0, 'root': 0, 'max_depth': 0};
    }
    int totalCount = 0;
    int maxDepth = 0;
    void countNodes(FolderTreeNode node) {
      totalCount++;
      if (node.depth > maxDepth) {
        maxDepth = node.depth;
      }
      for (var child in node.children) {
        countNodes(child);
      }
    }
    for (var rootNode in _cachedTree!) {
      countNodes(rootNode);
    }
    return {'total': totalCount, 'root': _cachedTree!.length, 'max_depth': maxDepth};
  }

  bool get isCacheValid {
    return _cachedTree != null &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!) < _cacheDuration;
  }
}
