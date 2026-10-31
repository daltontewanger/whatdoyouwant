import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/own_spot.dart';
import '../models/restaurant.dart';
import '../models/saved_place.dart';
import '../services/my_places.dart';
import '../services/room_backend.dart';
import 'bubble_icons.dart';

const favoriteColor = Color(0xFF8E2F55);
const neverColor = Color(0xFF3A3A37);

/// The two lists as the app names them.
const favoritesList = 'I know what I want';
const neverList = 'Never what I want';

/// The mark for a favorite: a heart in a pink speech bubble.
class FavoriteIcon extends StatelessWidget {
  const FavoriteIcon({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) =>
      BubbleIcon(BubbleGlyph.favorite, size: size);
}

/// The mark for a never place: a crossed-out plate in a grey bubble.
class NeverIcon extends StatelessWidget {
  const NeverIcon({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) =>
      BubbleIcon(BubbleGlyph.never, size: size, tailRight: true);
}

/// Shown in the corner of a card already on one of the person's lists.
/// Tapping it says which list.
class ListBadge extends StatelessWidget {
  const ListBadge({super.key, required this.never});

  final bool never;

  @override
  Widget build(BuildContext context) {
    final text = 'This is on your "${never ? neverList : favoritesList}" list';
    return Semantics(
      button: true,
      label: text,
      excludeSemantics: true,
      child: Tooltip(
        message: text,
        child: InkResponse(
          radius: 22,
          onTap: () => tell(ScaffoldMessenger.maybeOf(context), text),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: never ? const NeverIcon() : const FavoriteIcon(),
          ),
        ),
      ),
    );
  }
}

/// A short message with a close button, and an Undo when given one. Gone
/// after a few seconds, so it never hangs over the next card.
void tell(
  ScaffoldMessengerState? messenger,
  String text, {
  VoidCallback? undo,
}) {
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 3),
        // An Undo would otherwise keep it up until it is closed.
        persist: false,
        showCloseIcon: true,
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
  final list = 'your "${never ? neverList : favoritesList}" list';
  try {
    if (remove) {
      await store.remove(restaurant.id);
    } else if (never) {
      await store.addNever(restaurant);
    } else {
      await store.addFavorite(restaurant);
    }
  } on ListFull catch (full) {
    tell(messenger, full.toString());
    return;
  } catch (_) {
    // The device copy already has the change and sends it next time.
    if (!store.synced) {
      tell(messenger, 'That could not be saved. Try again.');
      return;
    }
  }
  tell(
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
    tell(messenger, "It's already on your list");
    return;
  }
  if (store.spots.length >= OwnSpot.maxSpots) {
    tell(
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
      tell(messenger, 'That could not be saved. Try again.');
      return;
    }
  }
  tell(
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

/// "Save as favorite" for a place from a search.
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
    final places = RoomBackendScope.maybeOf(context)?.myPlaces;
    if (places == null || !SavedPlace.canSave(restaurant)) {
      return const SizedBox.shrink();
    }
    return ListenableBuilder(
      listenable: places,
      builder: (context, _) {
        final saved = places.isFavorite(restaurant.id);
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
              icon: const FavoriteIcon(size: 24),
              label: Text(saved ? 'Saved to favorites' : 'Save as favorite'),
              onPressed:
                  () => markPlace(
                    context,
                    restaurant,
                    never: false,
                    remove: saved,
                  ),
            ),
          ],
        );
      },
    );
  }
}

/// The "⋯" in a place card's corner for the less common steps, such as
/// adding the place to the person's own list.
class PlaceMenu extends StatelessWidget {
  const PlaceMenu({super.key, required this.restaurant});

  final Restaurant restaurant;

  @override
  Widget build(BuildContext context) {
    final ownList = RoomBackendScope.maybeOf(context)?.ownList;
    if (ownList == null || !SavedPlace.canSave(restaurant)) {
      return const SizedBox.shrink();
    }
    return PopupMenuButton<void>(
      tooltip: 'More options',
      icon: const Icon(Icons.more_horiz),
      itemBuilder: (context) {
        final onList = _onOwnList(context, restaurant);
        return [
          PopupMenuItem(
            enabled: !onList,
            onTap: () => addToOwnList(context, restaurant),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                onList ? Icons.playlist_add_check : Icons.playlist_add,
              ),
              title: Text(
                onList
                    ? "Already on We'll Decide What We Want"
                    : "Add to We'll Decide What We Want",
              ),
            ),
          ),
        ];
      },
    );
  }
}
