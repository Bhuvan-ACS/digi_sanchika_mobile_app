import 'package:flutter/foundation.dart';

/// Shared selection state for folder/document browsing surfaces.
///
/// The controller deliberately stores IDs only, so screens can keep their
/// existing domain models and use the same batch-action toolbar everywhere.
class MultiSelectController extends ChangeNotifier {
  final Set<String> documentIds = <String>{};
  final Set<String> folderIds = <String>{};

  int get count => documentIds.length + folderIds.length;
  bool get isSelecting => count > 0;

  void toggleDocument(String id) {
    _toggle(documentIds, id);
    notifyListeners();
  }

  void toggleFolder(String id) {
    _toggle(folderIds, id);
    notifyListeners();
  }

  void clear() {
    documentIds.clear();
    folderIds.clear();
    notifyListeners();
  }

  void _toggle(Set<String> ids, String id) {
    if (!ids.remove(id)) ids.add(id);
  }
}
