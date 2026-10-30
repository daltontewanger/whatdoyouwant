import 'package:flutter/foundation.dart';

import 'restaurant.dart';

/// A restaurant on one of the person's lists, known by its deck card ID.
/// Favorites keep the details the card showed, with when it was last seen;
/// never places keep only a name.
@immutable
class SavedPlace {
  const SavedPlace({
    required this.id,
    this.name = '',
    this.address = '',
    this.seenAt,
  });

  /// Place details are kept this long after the place last turned up.
  static const detailsFor = Duration(days: 30);

  final String id;
  final String name;
  final String address;

  /// When the details were last refreshed, in milliseconds since the epoch.
  final int? seenAt;

  static final _id = RegExp(r'^c[0-9a-f]{20}$');

  /// Whether a card can go on a list: one from a search, not a typed spot.
  static bool canSave(Restaurant restaurant) =>
      !restaurant.userEntered && _id.hasMatch(restaurant.id);

  factory SavedPlace.favorite(Restaurant restaurant, DateTime now) =>
      SavedPlace(
        id: restaurant.id,
        name: restaurant.name,
        address: restaurant.address,
        seenAt: now.millisecondsSinceEpoch,
      );

  factory SavedPlace.never(Restaurant restaurant) =>
      SavedPlace(id: restaurant.id, name: restaurant.name);

  /// The same place with details older than [detailsFor] dropped.
  SavedPlace current(DateTime now) {
    final seen = seenAt;
    if (seen == null ||
        now.millisecondsSinceEpoch - seen < detailsFor.inMilliseconds) {
      return this;
    }
    return SavedPlace(id: id);
  }

  Map<String, Object> favoriteJson() => {
    'id': id,
    if (name.isNotEmpty && seenAt != null) ...{
      'name': name,
      if (address.isNotEmpty) 'address': address,
      'seenAt': seenAt!,
    },
  };

  Map<String, Object> neverJson() => {
    'id': id,
    if (name.isNotEmpty) 'name': name,
  };

  /// Null for anything that is not a usable entry.
  static SavedPlace? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || !_id.hasMatch(id)) return null;
    String text(Object? value) => value is String ? value : '';
    final seenAt = raw['seenAt'];
    return SavedPlace(
      id: id,
      name: text(raw['name']),
      address: text(raw['address']),
      seenAt: seenAt is num ? seenAt.toInt() : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SavedPlace &&
      other.id == id &&
      other.name == name &&
      other.address == address &&
      other.seenAt == seenAt;

  @override
  int get hashCode => Object.hash(id, name, address, seenAt);
}

/// Both lists and the person's own switches for them.
@immutable
class MyPlaces {
  const MyPlaces({
    this.favorites = const [],
    this.never = const [],
    this.useFavorites = true,
    this.useNever = true,
  });

  static const maxPlaces = 200;

  final List<SavedPlace> favorites;
  final List<SavedPlace> never;

  /// Whether this person's favorites go into rooms' decks.
  final bool useFavorites;

  /// Whether this person's never list is left out of decks.
  final bool useNever;

  bool get isEmpty => favorites.isEmpty && never.isEmpty;

  MyPlaces copyWith({
    List<SavedPlace>? favorites,
    List<SavedPlace>? never,
    bool? useFavorites,
    bool? useNever,
  }) => MyPlaces(
    favorites: favorites ?? this.favorites,
    never: never ?? this.never,
    useFavorites: useFavorites ?? this.useFavorites,
    useNever: useNever ?? this.useNever,
  );

  /// The lists with expired details dropped.
  MyPlaces current(DateTime now) =>
      copyWith(favorites: [for (final place in favorites) place.current(now)]);

  Map<String, Object> toJson() => {
    'favorites': [for (final place in favorites) place.favoriteJson()],
    'never': [for (final place in never) place.neverJson()],
    'useFavorites': useFavorites,
    'useNever': useNever,
  };

  static MyPlaces fromJson(Object? raw) {
    if (raw is! Map) return const MyPlaces();
    final seen = <String>{};
    List<SavedPlace> places(Object? value) => [
      if (value is List)
        for (final item in value)
          if (SavedPlace.fromJson(item) case final place?)
            if (seen.add(place.id)) place,
    ];
    return MyPlaces(
      favorites: places(raw['favorites']).take(maxPlaces).toList(),
      never: places(raw['never']).take(maxPlaces).toList(),
      useFavorites: raw['useFavorites'] != false,
      useNever: raw['useNever'] != false,
    );
  }

  /// [other]'s places added to these, up to the limit; switches stay as here.
  MyPlaces merged(MyPlaces other) {
    final ids = {
      for (final place in [...favorites, ...never]) place.id,
    };
    List<SavedPlace> add(List<SavedPlace> base, List<SavedPlace> extra) =>
        [
          ...base,
          ...extra.where((place) => ids.add(place.id)),
        ].take(maxPlaces).toList();
    return copyWith(
      favorites: add(favorites, other.favorites),
      never: add(never, other.never),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MyPlaces &&
      listEquals(other.favorites, favorites) &&
      listEquals(other.never, never) &&
      other.useFavorites == useFavorites &&
      other.useNever == useNever;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(favorites),
    Object.hashAll(never),
    useFavorites,
    useNever,
  );
}
