import 'my_places.dart';
import 'room_backend.dart';

/// Shares this person's favorites and never card IDs with a waiting room,
/// and again whenever the lists or their switches change, so the deck the
/// host starts sees the latest. A switch that is off shares nothing from
/// that list. Failures are ignored: the room still starts without them.
class RoomListSharer {
  RoomListSharer({
    required this.backend,
    required this.places,
    required this.roomId,
  }) {
    places.addListener(share);
    share();
  }

  final RoomBackend backend;
  final MyPlacesStore places;
  final String roomId;
  bool _disposed = false;

  Future<void> share() async {
    if (_disposed) return;
    final current = places.places;
    try {
      await backend.shareLists(
        roomId,
        favorites:
            current.useFavorites
                ? [for (final place in current.favorites) place.id]
                : const [],
        never:
            current.useNever
                ? [for (final place in current.never) place.id]
                : const [],
      );
    } catch (_) {}
  }

  void dispose() {
    _disposed = true;
    places.removeListener(share);
  }
}
