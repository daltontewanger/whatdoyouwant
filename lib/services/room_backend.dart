import 'package:flutter/widgets.dart';

import '../models/own_spot.dart';
import '../models/restaurant.dart';
import 'account_service.dart';
import 'active_room_store.dart';
import 'live_search.dart';
import 'accessibility.dart';
import 'my_places.dart';
import 'own_list.dart';
import 'search_defaults.dart';

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
    this.untimed = false,
  });

  /// Someone in the room votes without a card timer, so it may take longer.
  final bool untimed;

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

/// One person's Quick Pick: a stored deck shown one card at a time.
class QuickPick {
  const QuickPick({
    required this.id,
    required this.position,
    required this.restaurant,
    required this.rerollsLeft,
    required this.cards,
  });

  final String id;

  /// Which card of the deck is showing; rerolls continue from here.
  final int position;
  final Restaurant restaurant;
  final int rerollsLeft;

  /// Every card in the pick's deck by ID, so a reroll needs no extra read.
  final Map<String, Restaurant> cards;
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

  /// Starts voting and returns the deck. With a [zip] code the search starts
  /// there instead of at the device. [lists] are the host's switches for the
  /// members' favorites and never lists.
  Future<List<Restaurant>> start(
    String roomId, {
    required SearchPreferences search,
    String? zip,
    DeckLists lists = DeckLists.none,
  });

  /// Shares this person's favorites and never card IDs with a room while it
  /// waits, for the deck the host starts.
  Future<void> shareLists(
    String roomId, {
    required List<String> favorites,
    required List<String> never,
  });

  /// Starts voting on spots from the host's own list. No search runs, so it
  /// never uses a live search.
  Future<List<Restaurant>> startFromList(String roomId, List<OwnSpot> spots);

  /// Records a vote. [auto] marks a No the app cast because the card's time
  /// ran out, which does not count as the person taking part.
  Future<void> vote(
    String roomId,
    Restaurant restaurant, {
    required bool liked,
    required int index,
    required int total,
    bool auto = false,
  });

  /// Tells the room this person votes without a card timer. The room only
  /// learns that someone does, never who or why.
  Future<void> setNoTimer(String roomId, {required bool noTimer});

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

  /// Spends one live search on a deck for this person and shows its first
  /// card. Repeating a [requestId] returns the same pick rather than
  /// searching again, so a retry after a lost reply costs nothing.
  Future<QuickPick> createQuickPick({
    required String requestId,
    required SearchPreferences search,
    String? zip,
  });

  /// The next card from the same deck, without a search or a charge.
  Future<QuickPick> rerollQuickPick(QuickPick pick);
}

/// Makes the backend and, where accounts exist, the account service available
/// to every screen without passing them through each constructor.
/// The host's room switches: whether members' favorites go into the deck
/// and whether their never places are left out.
@immutable
class DeckLists {
  const DeckLists({required this.favorites, required this.never});

  static const none = DeckLists(favorites: false, never: false);
  static const all = DeckLists(favorites: true, never: true);

  final bool favorites;
  final bool never;

  DeckLists copyWith({bool? favorites, bool? never}) => DeckLists(
    favorites: favorites ?? this.favorites,
    never: never ?? this.never,
  );

  Map<String, bool> toJson() => {'favorites': favorites, 'never': never};

  @override
  bool operator ==(Object other) =>
      other is DeckLists &&
      other.favorites == favorites &&
      other.never == never;

  @override
  int get hashCode => Object.hash(favorites, never);
}

class RoomBackendScope extends InheritedWidget {
  const RoomBackendScope({
    super.key,
    required this.backend,
    this.accounts,
    this.activeRooms,
    this.searchDefaults,
    this.ownList,
    this.myPlaces,
    this.accessibility,
    required super.child,
  });

  /// The person's accessibility choices on this device.
  final AccessibilitySettings? accessibility;

  final RoomBackend backend;
  final AccountService? accounts;

  /// Remembers the room in progress where the backend lets members return.
  final ActiveRoomStore? activeRooms;

  /// The setup each search starts from, saved for the person.
  final SearchDefaultsStore? searchDefaults;

  /// The person's own list for We'll Decide What We Want.
  final OwnListStore? ownList;

  /// The person's favorites and never list.
  final MyPlacesStore? myPlaces;

  static RoomBackendScope of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<RoomBackendScope>();
    assert(scope != null, 'No RoomBackendScope above this widget.');
    return scope!;
  }

  /// The unit this person reads distances in; each member sees their own.
  static DistanceUnit distanceUnitOf(BuildContext context) =>
      maybeOf(context)?.searchDefaults?.current.unit ?? DistanceUnit.mi;

  /// The scope, where there is one; widgets shown outside the app return null.
  static RoomBackendScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RoomBackendScope>();

  @override
  bool updateShouldNotify(RoomBackendScope oldWidget) =>
      backend != oldWidget.backend ||
      accounts != oldWidget.accounts ||
      activeRooms != oldWidget.activeRooms ||
      searchDefaults != oldWidget.searchDefaults ||
      ownList != oldWidget.ownList ||
      myPlaces != oldWidget.myPlaces ||
      accessibility != oldWidget.accessibility;
}
