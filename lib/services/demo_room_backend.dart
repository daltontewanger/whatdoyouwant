import 'dart:async';
import 'dart:math';

import '../models/own_spot.dart';
import '../models/restaurant.dart';
import 'live_search.dart';
import 'room_backend.dart';
import 'search_defaults.dart';

/// A made-up restaurant for the demo: what the cards show, plus the
/// cuisines a demo search filters on.
class DemoPlace {
  const DemoPlace(this.name, this.address, this.miles, this.cuisines);

  final String name;
  final String address;
  final double miles;
  final List<String> cuisines;
}

/// Fictional places only. None of them is a real business, and the demo says
/// so on every screen.
const demoPlaces = [
  DemoPlace('Taco Spot', '412 Main St', 1.8, ['mexican']),
  DemoPlace('Pho House', '88 Elm Ave', 2.4, ['vietnamese']),
  DemoPlace('Slice Society', '17 Market St', 0.6, ['pizza', 'italian']),
  DemoPlace('Noodle Nook', '230 Pine St', 1.2, ['chinese']),
  DemoPlace('Sushi Stop', '9 Harbor Rd', 3.1, ['japanese', 'seafood']),
  DemoPlace('Curry Corner', '501 Oak St', 2.9, ['indian']),
  DemoPlace('Burger Barn', '64 Mill Rd', 0.9, ['burgers', 'american']),
  DemoPlace('Pancake Porch', '12 Sunrise Ln', 1.5, ['breakfast', 'american']),
  DemoPlace('Smoke & Oak BBQ', '780 Ridge Rd', 4.2, ['bbq', 'american']),
  DemoPlace('Falafel Friends', '33 Cedar St', 2.1, ['middle_eastern']),
  DemoPlace('Gyro Garden', '145 Olive Way', 3.6, ['greek_mediterranean']),
  DemoPlace('Little Bistro', '6 Rue Lane', 5.4, ['french']),
  DemoPlace('Thai Basil', '290 Lotus St', 1.9, ['thai']),
  DemoPlace('Trattoria Nona', '71 Vine St', 4.8, ['italian']),
  DemoPlace('Catch of the Day', '3 Pier Ave', 6.3, ['seafood']),
  DemoPlace('Prime Cut', '400 Grand Ave', 7.5, ['steakhouse']),
  DemoPlace('Deli Delight', '58 Baker St', 0.4, ['sandwiches']),
  DemoPlace('Cluck Shack', '910 Farm Rd', 2.7, ['chicken', 'fast_food']),
  DemoPlace('Scoop Dreams', '22 Sugar St', 1.1, ['dessert']),
  DemoPlace('Ramen Road', '377 Hill St', 3.9, ['japanese']),
  DemoPlace('Dumpling Den', '15 Lantern Ln', 4.4, ['chinese']),
  DemoPlace('Cantina Sol', '612 Sunset Blvd', 5.9, ['mexican']),
  DemoPlace('Corner Cafe', '1 Square Pl', 0.8, []),
  DemoPlace('Fireside Grill', '250 Lake Rd', 9.6, ['american']),
  DemoPlace('Mezze Table', '87 Spice Rd', 11.2, ['middle_eastern']),
];

/// The friends who join a demo room, in the order they arrive.
const demoFriends = ['Sam', 'Alex', 'Jordan'];

/// The app's room backend played out on the device: made-up restaurants,
/// a few friends who join and vote on their own, and nothing sent anywhere
/// or saved. The real screens run on it, so the demo shows the app as it is.
class DemoRoomBackend implements RoomBackend {
  DemoRoomBackend({
    int seed = 7,
    this.pace = const Duration(milliseconds: 1200),
    DateTime Function()? now,
  }) : _random = Random(seed),
       _now = now ?? DateTime.now;

  /// How long a friend takes to join, and the step their voting is timed by.
  /// Zero settles everything at once, as tests and screenshots need.
  final Duration pace;

  final Random _random;
  final DateTime Function() _now;
  final _rooms = <String, _DemoRoom>{};
  final _changes = StreamController<String>.broadcast();
  final _timers = <Timer>[];
  var _roomCount = 0;
  var _pickCount = 0;
  String? _nickname;

  static const joinCode = 'YUM4ME';
  static const _you = 'demo-you';

  /// Stops the friends' timers when the demo closes.
  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _changes.close();
  }

  void _later(Duration delay, void Function() action) {
    if (delay == Duration.zero) {
      action();
      return;
    }
    _timers.add(Timer(delay, action));
  }

  void _changed(String roomId) {
    if (!_changes.isClosed) _changes.add(roomId);
  }

  @override
  bool get usesDeviceLocation => false;

  // The demo marks itself on every screen, so the build notes about test
  // restaurants would only repeat it.
  @override
  bool get usesFictionalRestaurants => false;

  @override
  Future<CreatedRoom> createRoom() async {
    final id = 'demo-room-${++_roomCount}';
    final room = _rooms[id] = _DemoRoom();
    for (final (i, _) in demoFriends.indexed) {
      _later(pace * (i + 1), () {
        if (room.status != 'lobby') return;
        room.friends++;
        _changed(id);
      });
    }
    return CreatedRoom(id, joinCode);
  }

  @override
  Future<String> joinRoom(String typedCode) async =>
      throw UnsupportedError('The demo hosts its own room.');

  @override
  Stream<RoomState> watch(String roomId) async* {
    yield _state(roomId);
    await for (final changed in _changes.stream) {
      if (changed == roomId) yield _state(roomId);
    }
  }

  RoomState _state(String roomId) {
    final room = _rooms[roomId]!;
    final voters = room.voters;
    final left =
        [
          if (room.myVotes.length < room.deck.length) 'you',
          for (var i = 0; i < voters; i++)
            if (room.friendDone.length <= i || !room.friendDone[i]) 'friend',
        ].length;
    return RoomState(
      id: roomId,
      joinCode: room.status == 'lobby' ? joinCode : null,
      creatorId: _you,
      status: room.status,
      memberCount: 1 + room.friends,
      restaurants: room.deck,
      myVoteCount: room.myVotes.length,
      votedIds: room.myVotes.keys.toSet(),
      resultsReady: room.status == 'closed',
      remainingVoters: room.status == 'voting' ? left : null,
      results: room.results,
      votingEndsAt: room.endsAt,
      people: [
        RoomPerson(name: _nickname, host: true, you: true),
        for (final name in demoFriends.take(room.friends))
          RoomPerson(name: name),
      ],
    );
  }

  /// The places a search with [search] finds, nearest first, with chosen
  /// cuisines moved to the front.
  List<Restaurant> _search(SearchPreferences search) {
    final reach = search.radius * search.unit.meters / DistanceUnit.mi.meters;
    final found = [
      for (final (i, place) in demoPlaces.indexed)
        if (place.miles <= reach &&
            !place.cuisines.any(search.excludedCuisineIds.contains))
          (i, place),
    ]..shuffle(_random);
    bool wanted((int, DemoPlace) entry) =>
        entry.$2.cuisines.any(search.includedCuisineIds.contains);
    final ordered = [...found.where(wanted), ...found.where((e) => !wanted(e))];
    return [
      for (final (i, place) in ordered.take(search.deckSize))
        Restaurant(
          id: 'demo-$i',
          name: place.name,
          address: place.address,
          distance: place.miles,
          // Somewhere believable, so the map buttons show; the demo never
          // opens them.
          latitude: 40.0 + i / 1000,
          longitude: -75.0 - i / 1000,
        ),
    ];
  }

  @override
  Future<List<Restaurant>> start(
    String roomId, {
    required SearchPreferences search,
    String? zip,
    DeckLists lists = DeckLists.none,
  }) async {
    final deck = _search(search);
    if (deck.isEmpty) {
      throw StateError('No demo places fit that search.');
    }
    return _begin(roomId, deck);
  }

  @override
  Future<List<Restaurant>> startFromList(
    String roomId,
    List<OwnSpot> spots,
  ) async => _begin(roomId, [
    for (final spot in spots)
      Restaurant(
        id: spot.id,
        name: spot.name,
        address: spot.address,
        distance: 0,
        userEntered: true,
        note: spot.note.isEmpty ? null : spot.note,
      ),
  ]);

  List<Restaurant> _begin(String roomId, List<Restaurant> deck) {
    final room = _rooms[roomId]!;
    room
      ..deck = deck
      ..status = 'voting'
      ..voters = room.friends
      ..endsAt = _now().add(const Duration(minutes: 10))
      ..friendDone = List.filled(room.friends, false);
    // Each friend likes a few places, some more popular than others, so the
    // group lands on a winner the way a real room does.
    final appeal = [for (final _ in deck) 0.2 + _random.nextDouble() * 0.6];
    for (var f = 0; f < room.voters; f++) {
      final likes = {
        for (final (i, card) in deck.indexed)
          if (_random.nextDouble() < appeal[i]) card.id,
      };
      if (likes.isEmpty) likes.add(deck[_random.nextInt(deck.length)].id);
      room.friendLikes.add(likes);
      _later(pace * (3 + 2 * f), () {
        room.friendDone[f] = true;
        _settle(roomId);
      });
    }
    _changed(roomId);
    return deck;
  }

  void _settle(String roomId) {
    final room = _rooms[roomId]!;
    if (room.status != 'voting') return;
    final done =
        room.myVotes.length >= room.deck.length &&
        room.friendDone.every((done) => done);
    if (done) {
      final likes = {for (final card in room.deck) card.id: 0};
      for (final entry in room.myVotes.entries) {
        if (entry.value) likes[entry.key] = likes[entry.key]! + 1;
      }
      for (final friend in room.friendLikes) {
        for (final id in friend) {
          likes[id] = likes[id]! + 1;
        }
      }
      // Most likes wins; a tie goes to the card dealt first, as on the server.
      final ranking = [for (final card in room.deck) card.id]
        ..sort((a, b) => likes[b]!.compareTo(likes[a]!));
      room
        ..status = 'closed'
        ..results = RoomResults(
          winnerId: ranking.first,
          backupId:
              ranking.length > 1 && likes[ranking[1]]! > 0 ? ranking[1] : null,
          likes: likes,
          participants: 1 + room.voters,
        );
    }
    _changed(roomId);
  }

  @override
  Future<void> vote(
    String roomId,
    Restaurant restaurant, {
    required bool liked,
    required int index,
    required int total,
    bool auto = false,
  }) async {
    final room = _rooms[roomId]!;
    if (room.status != 'voting') return;
    room.myVotes[restaurant.id] = liked;
    _settle(roomId);
  }

  @override
  Future<void> nudge(String roomId) async => _settle(roomId);

  @override
  Future<void> shareLists(
    String roomId, {
    required List<String> favorites,
    required List<String> never,
  }) async {}

  @override
  Future<void> setNoTimer(String roomId, {required bool noTimer}) async {}

  @override
  Future<void> prepareStart() async {}

  @override
  Future<bool> updateRequired(int build) async => false;

  // Demo rooms can't be joined from another device.
  @override
  Uri? joinLinkFor(String joinCode) => null;

  @override
  Uri sitePage(String path) => Uri.parse('https://getwhatdoyouwant.app$path');

  // The demo never spends a search, so there is no allowance to show.
  @override
  Future<LiveSearchAllowance?> liveSearchAllowance() async => null;

  final _picks = <String, List<Restaurant>>{};

  @override
  Future<QuickPick> createQuickPick({
    required String requestId,
    required SearchPreferences search,
    String? zip,
  }) async {
    final deck = _search(search.copyWith(deckSize: 6));
    if (deck.isEmpty) throw StateError('No demo places fit that search.');
    final id = 'demo-pick-${++_pickCount}';
    _picks[id] = deck;
    return _pick(id, 0);
  }

  @override
  Future<QuickPick> rerollQuickPick(QuickPick pick) async =>
      _pick(pick.id, pick.position + 1);

  QuickPick _pick(String id, int position) {
    final deck = _picks[id]!;
    return QuickPick(
      id: id,
      position: position,
      restaurant: deck[position % deck.length],
      rerollsLeft: max(0, deck.length - 1 - position),
      cards: {for (final card in deck) card.id: card},
    );
  }

  @override
  Future<String?> nickname() async => _nickname;

  @override
  Future<String?> setNickname(String nickname) async =>
      _nickname = nickname.isEmpty ? null : nickname;
}

class _DemoRoom {
  String status = 'lobby';
  int friends = 0;

  /// Friends present when voting started; later arrivals are turned away,
  /// as in a real room.
  int voters = 0;
  List<Restaurant> deck = const [];
  final myVotes = <String, bool>{};
  final friendLikes = <Set<String>>[];
  List<bool> friendDone = const [];
  DateTime? endsAt;
  RoomResults? results;
}
