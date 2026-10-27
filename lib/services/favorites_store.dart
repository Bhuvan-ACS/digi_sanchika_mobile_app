import 'package:flutter/foundation.dart';
import 'package:digi_sanchika/services/favorites_service.dart';

/// App-wide favourite state shared by My Files, Shared and Favourites.
///
/// The server stays the source of truth: [load] pulls the list, and toggles
/// update the local sets immediately (so every listening page redraws at
/// once) before confirming with the server, rolling back if that fails.
class FavoritesStore extends ChangeNotifier {
  FavoritesStore._();
  static final FavoritesStore instance = FavoritesStore._();

  final FavoritesService _service = FavoritesService();
  final Set<String> _documentIds = <String>{};
  final Set<String> _folderIds = <String>{};

  Iterable<String> get documentIds => _documentIds;
  Iterable<String> get folderIds => _folderIds;

  bool isFavorite(String documentId) => _documentIds.contains(documentId);
  bool isFavoriteFolder(String folderId) => _folderIds.contains(folderId);

  Future<void> load() async {
    final items = await _service.listFavorites();
    _documentIds
      ..clear()
      ..addAll(
        items
            .where((i) => i.entityType.toLowerCase().contains('doc'))
            .map((i) => i.entityId),
      );
    _folderIds
      ..clear()
      ..addAll(
        items
            .where((i) => i.entityType.toLowerCase().contains('folder'))
            .map((i) => i.entityId),
      );
    notifyListeners();
  }

  /// Adds or removes a document. Returns false if the server call failed.
  Future<bool> toggleDocument(String documentId) =>
      _toggle(_documentIds, documentId, 'document');

  /// Adds or removes a folder. Returns false if the server call failed.
  Future<bool> toggleFolder(String folderId) =>
      _toggle(_folderIds, folderId, 'folder');

  /// Removes without toggling (safe to call when already removed).
  Future<bool> removeDocument(String documentId) async =>
      !isFavorite(documentId) || await toggleDocument(documentId);

  Future<bool> removeFolder(String folderId) async =>
      !isFavoriteFolder(folderId) || await toggleFolder(folderId);

  Future<bool> _toggle(Set<String> ids, String id, String entityType) async {
    final wasFavorite = ids.contains(id);
    wasFavorite ? ids.remove(id) : ids.add(id);
    notifyListeners();

    bool ok;
    try {
      ok = wasFavorite
          ? await _service.removeFavorite(entityId: id, entityType: entityType)
          : await _service.addFavorite(entityId: id, entityType: entityType);
    } catch (_) {
      ok = false;
    }

    if (!ok) {
      wasFavorite ? ids.add(id) : ids.remove(id);
      notifyListeners();
    }
    return ok;
  }
}
