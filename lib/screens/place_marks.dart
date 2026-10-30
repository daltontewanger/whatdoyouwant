import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/own_spot.dart';
import '../models/restaurant.dart';
import '../models/saved_place.dart';
import '../services/my_places.dart';
import '../services/room_backend.dart';

const favoriteColor = Color(0xFFB83A6B);

/// The app's speech bubble holding a heart: the mark for a favorite.
class FavoriteIcon extends StatelessWidget {
  const FavoriteIcon({super.key, this.size = 24, this.color = favoriteColor});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Icon(Icons.chat_bubble_outline, size: size, color: color),
        Padding(
          padding: EdgeInsets.only(bottom: size * 0.12),
          child: Icon(Icons.favorite, size: size * 0.42, color: color),
        ),
      ],
    ),
  );
}

/// Shown on a card that is already one of the person's favorites.
class FavoriteBadge extends StatelessWidget {
  const FavoriteBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(6, 3, 10, 3),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FavoriteIcon(size: 16),
        SizedBox(width: 4),
        Text(
          'Your favorite',
          style: TextStyle(color: favoriteColor, fontSize: 12),
        ),
      ],
    ),
  );
}

void _tell(
  ScaffoldMessengerState? messenger,
  String text, {
  VoidCallback? undo,
}) {
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        action:
            undo == null
                ? null
                : SnackBarAction(label: 'Undo', onPressed: undo),
      ),
    );
}

/// Adds [restaurant] to the favorites or the never list, or takes it off
/// again when [remove] is set, and says so with an Undo. Never throws: a
/// failure is shown instead.
Future<void> markPlace(
  BuildContext context,
  Restaurant restaurant, {
  required bool never,
  bool remove = false,
}) async {
  final store = RoomBackendScope.maybeOf(context)?.myPlaces;
  if (store == null || !SavedPlace.canSave(restaurant)) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final before = store.places;
  final list = never ? 'your never list' : 'your favorites';
  try {
    if (remove) {
      await store.remove(restaurant.id);
    } else if (never) {
      await store.addNever(restaurant);
    } else {
      await store.addFavorite(restaurant);
    }
  } on ListFull catch (full) {
    _tell(messenger, full.toString());
    return;
  } catch (_) {
    // The device copy already has the change and sends it next time.
    if (!store.synced) {
      _tell(messenger, 'That could not be saved. Try again.');
      return;
    }
  }
  _tell(
    messenger,
    remove ? 'Removed from $list' : 'Saved to $list',
    undo: () => store.restore(before).catchError((_) {}),
  );
}

/// Adds a place to the person's own list for We'll Decide What We Want.
Future<void> addToOwnList(BuildContext context, Restaurant restaurant) async {
  final store = RoomBackendScope.maybeOf(context)?.ownList;
  if (store == null) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final spot = OwnSpot(
    id: const Uuid().v4(),
    name: _fit(restaurant.name, OwnSpot.maxName),
    address: _fit(restaurant.address, OwnSpot.maxAddress),
  );
  if (store.spots.any((s) => s.matchKey == spot.matchKey)) {
    _tell(messenger, "It's already on your list");
    return;
  }
  if (store.spots.length >= OwnSpot.maxSpots) {
    _tell(
      messenger,
      'Your list has ${OwnSpot.maxSpots} spots. Remove one to add this.',
    );
    return;
  }
  final before = store.spots;
  try {
    await store.save([...store.spots, spot]);
  } catch (_) {
    if (!store.synced) {
      _tell(messenger, 'That could not be saved. Try again.');
      return;
    }
  }
  _tell(
    messenger,
    "Added to We'll Decide What We Want",
    undo: () => store.save(before).catchError((_) {}),
  );
}

String _fit(String text, int max) {
  final trimmed = text.trim();
  return trimmed.length <= max ? trimmed : trimmed.substring(0, max).trim();
}

bool _onOwnList(BuildContext context, Restaurant restaurant) {
  final store = RoomBackendScope.maybeOf(context)?.ownList;
  final key = OwnSpot(id: '', name: restaurant.name).matchKey;
  return store?.spots.any((spot) => spot.matchKey == key) ?? false;
}

/// "Save as favorite" and "Add to my list" for a place from a search.
class PlaceListButtons extends StatelessWidget {
  const PlaceListButtons({
    super.key,
    required this.restaurant,
    this.alignment = WrapAlignment.start,
  });

  final Restaurant restaurant;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final scope = RoomBackendScope.maybeOf(context);
    final places = scope?.myPlaces;
    if (places == null || !SavedPlace.canSave(restaurant)) {
      return const SizedBox.shrink();
    }
    return ListenableBuilder(
      listenable: Listenable.merge([
        places,
        if (scope?.ownList case final list?) list,
      ]),
      builder: (context, _) {
        final saved = places.isFavorite(restaurant.id);
        final onList = _onOwnList(context, restaurant);
        return Wrap(
          alignment: alignment,
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: favoriteColor,
                side: BorderSide(color: saved ? favoriteColor : Colors.black26),
              ),
              icon: const FavoriteIcon(size: 20),
              label: Text(saved ? 'Saved to favorites' : 'Save as favorite'),
              onPressed:
                  () => markPlace(
                    context,
                    restaurant,
                    never: false,
                    remove: saved,
                  ),
            ),
            if (scope?.ownList != null)
              OutlinedButton.icon(
                icon: Icon(
                  onList ? Icons.playlist_add_check : Icons.playlist_add,
                ),
                label: Text(onList ? 'On my list' : 'Add to my list'),
                onPressed:
                    onList ? null : () => addToOwnList(context, restaurant),
              ),
          ],
        );
      },
    );
  }
}
