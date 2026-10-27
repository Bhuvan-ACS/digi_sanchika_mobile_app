import 'package:flutter/material.dart';
import 'package:digi_sanchika/services/favorites_store.dart';

/// Menu value used by [favoriteMenuItem].
const String favoriteMenuValue = 'favorite';

/// "Add to Favourites" / "Remove from Favourites" entry for a document's
/// overflow menu, labelled from the shared [FavoritesStore].
PopupMenuItem<String> favoriteMenuItem(String documentId) {
  final isFavorite = FavoritesStore.instance.isFavorite(documentId);
  return PopupMenuItem(
    value: favoriteMenuValue,
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
        color: Colors.amber,
      ),
      title: Text(isFavorite ? 'Remove from Favourites' : 'Add to Favourites'),
    ),
  );
}

/// Toggles a document's favourite state and confirms with a snackbar.
Future<void> toggleFavoriteWithFeedback(
  BuildContext context,
  String documentId,
) async {
  final store = FavoritesStore.instance;
  final wasFavorite = store.isFavorite(documentId);
  final ok = await store.toggleDocument(documentId);
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(
    SnackBar(
      content: Text(
        !ok
            ? (wasFavorite
                  ? 'Failed to remove from favourites'
                  : 'Failed to add to favourites')
            : (wasFavorite
                  ? 'Removed from favourites'
                  : 'Added to favourites'),
      ),
      backgroundColor: ok ? null : Colors.red,
    ),
  );
}
