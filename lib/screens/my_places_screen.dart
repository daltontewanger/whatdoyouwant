import 'package:flutter/material.dart';

import '../models/restaurant.dart';
import '../models/saved_place.dart';
import '../services/my_places.dart';
import '../services/room_backend.dart';
import 'place_marks.dart';

/// The person's favorites ("I know what I want") and never list ("Never
/// what I want"), with their own switches and a way to remove each place.
class MyPlacesScreen extends StatelessWidget {
  const MyPlacesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = RoomBackendScope.of(context);
    final store = scope.myPlaces!;
    return Scaffold(
      appBar: AppBar(title: const Text('Your lists')),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final places = store.places;
          final theme = Theme.of(context);
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  const _Heading(icon: FavoriteIcon(), title: favoritesList),
                  _Switch(
                    title: 'Use my favorites in rooms',
                    value: places.useFavorites,
                    onChanged:
                        (on) => _save(
                          context,
                          store,
                          places.copyWith(useFavorites: on),
                        ),
                  ),
                  if (places.favorites.isEmpty)
                    const _Empty(
                      'Tap Favorite on a card, or Save as favorite on a result.',
                    ),
                  for (final place in places.favorites)
                    _PlaceRow(
                      title:
                          place.name.isEmpty ? 'A saved favorite' : place.name,
                      subtitle:
                          place.name.isEmpty
                              ? 'Its details come back when it turns up in a search.'
                              : place.address,
                      onAddToList:
                          place.name.isEmpty || scope.ownList == null
                              ? null
                              : () => addToOwnList(
                                context,
                                Restaurant(
                                  id: place.id,
                                  name: place.name,
                                  address: place.address,
                                  distance: 0,
                                ),
                              ),
                      onRemove:
                          () => _remove(context, store, place, favoritesList),
                    ),
                  const SizedBox(height: 28),
                  const _Heading(icon: NeverIcon(), title: neverList),
                  _Switch(
                    title: 'Leave these out of rooms and picks',
                    value: places.useNever,
                    onChanged:
                        (on) => _save(
                          context,
                          store,
                          places.copyWith(useNever: on),
                        ),
                  ),
                  if (places.never.isEmpty)
                    const _Empty('Tap Never on a card to keep a place out.'),
                  for (final place in places.never)
                    _PlaceRow(
                      title: place.name.isEmpty ? 'A never place' : place.name,
                      onRemove: () => _remove(context, store, place, neverList),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    store.synced
                        ? 'Saved to your account. Nobody else in a room sees your lists.'
                        : 'Saved on this device. Sign in to keep them with your '
                            'account. Nobody else in a room sees your lists.',
                    style: theme.textTheme.bodySmall!.copyWith(
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static Future<void> _save(
    BuildContext context,
    MyPlacesStore store,
    MyPlaces next,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await store.save(next);
    } catch (_) {
      // An account's device copy keeps the change and sends it next time.
      if (!store.synced) {
        tell(messenger, 'That could not be saved. Try again.');
      }
    }
  }

  static Future<void> _remove(
    BuildContext context,
    MyPlacesStore store,
    SavedPlace place,
    String list,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final before = store.places;
    await _save(
      context,
      store,
      before.copyWith(
        favorites: before.favorites.where((p) => p.id != place.id).toList(),
        never: before.never.where((p) => p.id != place.id).toList(),
      ),
    );
    tell(
      messenger,
      'Removed from your "$list" list',
      undo: () => store.restore(before).catchError((_) {}),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.icon, required this.title});

  final Widget icon;
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        icon,
        const SizedBox(width: 10),
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
      ],
    ),
  );
}

class _Switch extends StatelessWidget {
  const _Switch({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    value: value,
    onChanged: onChanged,
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium!.copyWith(color: Colors.black54),
    ),
  );
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({
    required this.title,
    this.subtitle = '',
    this.onAddToList,
    required this.onRemove,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onAddToList;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Colors.black12)),
    ),
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onAddToList case final add?)
            IconButton(
              icon: const Icon(Icons.playlist_add),
              tooltip: "Add to We'll Decide What We Want",
              onPressed: add,
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remove $title',
            onPressed: onRemove,
          ),
        ],
      ),
    ),
  );
}
