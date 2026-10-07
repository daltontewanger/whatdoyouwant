import 'package:flutter/widgets.dart';

import '../models/restaurant.dart';
import 'account_service.dart';
import 'active_room_store.dart';

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
    this.everyoneDone = false,
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
  final bool everyoneDone;
  final bool resultsReady;
  final int? remainingVoters;
  final RoomResults? results;

  /// When the server stops taking votes, for backends that close rooms
  /// themselves.
  final DateTime? votingEndsAt;
}

class RoomResults {
  const RoomResults({
    required this.winnerId,
    required this.likes,
    required this.participants,
    this.backupId,
    this.winnerVotes,
  });

  final String? winnerId;
  final String? backupId;
  final Map<String, int> likes;
  final int participants;

  /// Set when the vote count shown for the winner is not simply its likes.
  final int? winnerVotes;

  int get winnerLikes => winnerVotes ?? likes[winnerId] ?? 0;
}

class CreatedRoom {
  const CreatedRoom(this.id, this.joinCode);
  final String id;
  final String joinCode;
}

/// Everything the room screens do, so the same UI can run on the original
/// client-managed rooms or the server-managed room callables.
abstract class RoomBackend {
  /// Creating rooms needs a signed-in account with a verified email.
  bool get requiresVerifiedHost;

  /// Starting a room uses the device location to search nearby.
  bool get usesDeviceLocation;

  /// Decks come from made-up test restaurants rather than a real provider.
  bool get usesFictionalRestaurants;

  /// Clients close finished rooms themselves rather than the server.
  bool get clientClosesRooms;

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

  /// Lets the backend settle stragglers or close a finished room.
  Future<void> nudge(String roomId);
  Future<void> close(String roomId);
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

  @override
  bool updateShouldNotify(RoomBackendScope oldWidget) =>
      backend != oldWidget.backend ||
      accounts != oldWidget.accounts ||
      activeRooms != oldWidget.activeRooms;
}
