import 'package:digi_sanchika/services/folder_tree_service.dart';
import 'package:digi_sanchika/models/folder_tree_node.dart';

class FolderHelper {
  static Future<List<Map<String, dynamic>>> getFoldersFlatList() async {
    final tree = await FolderTreeService().fetchFolderTree(forceRefresh: true);
    return _flattenTree(tree);
  }

  static List<Map<String, dynamic>> _flattenTree(
    List<FolderTreeNode> folders, {
    String path = '',
  }) {
    final List<Map<String, dynamic>> flatList = [];

    for (var folder in folders) {
      final currentPath =
          path.isNotEmpty ? '$path/${folder.name}' : folder.name;
      flatList.add({
        'id': folder.id,
        'name': folder.name,
        'path': currentPath,
        'displayName': currentPath,
      });
      if (folder.children.isNotEmpty) {
        flatList.addAll(
          _flattenTree(folder.children, path: currentPath),
        );
      }
    }

    return flatList;
  }

  static Future<String?> findFolderIdByName(String folderName) async {
    if (folderName.isEmpty) return null;
    final folders = await getFoldersFlatList();
    for (var folder in folders) {
      if (folder['name']?.toString().toLowerCase() ==
          folderName.toLowerCase()) {
        return folder['id']?.toString();
      }
    }
    if (folderName.toLowerCase() == 'home') {
      return folders.isNotEmpty ? folders.first['id']?.toString() : null;
    }
    return null;
  }

  static Future<Map<String, dynamic>?> getDefaultFolder() async {
    final folders = await getFoldersFlatList();
    if (folders.isEmpty) return null;
    final homeFolder = folders.firstWhere(
      (folder) => folder['name']?.toString().toLowerCase() == 'home',
      orElse: () => folders.first,
    );
    return homeFolder;
  }
}
