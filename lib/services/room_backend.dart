import 'package:flutter/widgets.dart';

import '../models/restaurant.dart';
import 'account_service.dart';
import 'active_room_store.dart';
import 'live_search.dart';

/// A room as the screens need to see it, whichever backend stores it.
class RoomState {
  const RoomState({
    required this.id,
    required this.joinCode,
    required this.creatorId,
    required this.status,
    required this.memberCount,
    required this.restaurants,
    required this.myVoteCount,
    required this.resultsReady,
    this.remainingVoters,
    this.results,
    this.votedIds = const {},
    this.votingEndsAt,
  });

  /// Identifier used for every later call; also how members reconnect.
  final String id;

  /// Code people type to join, while the room still accepts new members.
  final String? joinCode;
  final String creatorId;

  /// `lobby`, `voting` or `closed`.
  final String status;
  final int memberCount;

  /// The deck, empty until voting starts.
  final List<Restaurant> restaurants;
  final int myVoteCount;

  /// Restaurants this person already voted on, where the backend reports them;
  /// votes cannot be changed, so a returning voter skips these.
  final Set<String> votedIds;
  final bool resultsReady;
  final int? remainingVoters;
  final RoomResults? results;

  /// When the server stops taking votes.
  final DateTime? votingEndsAt;
}

class RoomResults {
  const RoomResults({
    required this.winnerId,
    required this.likes,
    required this.participants,
    this.backupId,
    this.winnerVotes,
    this.winnerCard,
    this.backupCard,
  });

  final String? winnerId;
  final String? backupId;
  final Map<String, int> likes;
  final int participants;

  /// Set when the vote count shown for the winner is not simply its likes.
  final int? winnerVotes;

  /// The winner and backup as the room keeps them once its deck is gone.
  final Restaurant? winnerCard;
  final Restaurant? backupCard;

  int get winnerLikes => winnerVotes ?? likes[winnerId] ?? 0;
}

class CreatedRoom {
  const CreatedRoom(this.id, this.joinCode);
  final String id;
  final String joinCode;
}

/// Everything the room screens do, so they can run on the room callables or
/// on a fake in tests.
abstract class RoomBackend {
  /// Starting a room uses the device location to search nearby.
  bool get usesDeviceLocation;

  /// Decks come from made-up test restaurants rather than a real provider.
  bool get usesFictionalRestaurants;

  Future<CreatedRoom> createRoom();

  /// Joins with what the person typed and returns the room's [RoomState.id].
  Future<String> joinRoom(String typedCode);
  Stream<RoomState> watch(String roomId);

  /// Starts voting and returns the deck.
  Future<List<Restaurant>> start(
    String roomId, {
    required double radiusMiles,
    required int maxOptions,
  });
  Future<void> vote(
    String roomId,
    Restaurant restaurant, {
    required bool liked,
    required int index,
    required int total,
  });

  /// Gets ready to start while the host waits in the lobby, for example by
  /// finding the device location. Never prompts the person.
  Future<void> prepareStart();

  /// Lets the backend settle stragglers or close a finished room.
  Future<void> nudge(String roomId);

  /// Whether the backend no longer serves this build of the app.
  Future<bool> updateRequired(int build);

  /// The link that joins a room by its code, where rooms can be joined by link.
  Uri? joinLinkFor(String joinCode);

  /// A page of the public site, such as `/privacy`; `/` is its home.
  Uri sitePage(String path);

  /// This week's live searches, or null where there is no allowance to show
  /// (guests, unverified accounts, and backends without one).
  Future<LiveSearchAllowance?> liveSearchAllowance();
}

/// Makes the backend and, where accounts exist, the account service available
/// to every screen without passing them through each constructor.
class RoomBackendScope extends InheritedWidget {
  const RoomBackendScope({
    super.key,
    required this.backend,
    this.accounts,
    this.activeRooms,
    required super.child,
  });

  final RoomBackend backend;
  final AccountService? accounts;

  /// Remembers the room in progress where the backend lets members return.
  final ActiveRoomStore? activeRooms;

  static RoomBackendScope of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<RoomBackendScope>();
    assert(scope != null, 'No RoomBackendScope above this widget.');
    return scope!;
  }

  /// The scope, where there is one; widgets shown outside the app return null.
  static RoomBackendScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RoomBackendScope>();

  @override
  bool updateShouldNotify(RoomBackendScope oldWidget) =>
      backend != oldWidget.backend ||
      accounts != oldWidget.accounts ||
      activeRooms != oldWidget.activeRooms;
}
