import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/insights.dart';
import '../models/own_spot.dart';
import '../models/restaurant.dart';
import 'deck_loader.dart';
import 'device_location.dart';
import 'live_search.dart';
import 'room_backstop.dart';
import 'room_backend.dart';
import 'search_defaults.dart';
import 'site_links.dart';

export 'device_location.dart' show SearchOrigin;

/// Turns what someone typed into a join request: a six-character join code for
/// new members, or the longer room ID that existing members reconnect with.
Map<String, String>? joinRequestFor(String typed) {
  final cleaned = typed.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  if (RegExp(r'^[A-HJKMNP-Z2-9]{6}$').hasMatch(cleaned)) {
    return {'joinCode': cleaned};
  }
  if (RegExp(r'^[A-F0-9]{24}$').hasMatch(cleaned)) return {'roomId': cleaned};
  return null;
}

/// Thrown for input that cannot be a join code, before contacting the server.
class InvalidJoinCode implements Exception {
  @override
  String toString() =>
      'Enter the 6-character code shown on the host\'s screen.';
}

const _metersPerMile = 1609.344;

/// The search the server's startRoom expects. The location is rounded to
/// about 100 m first: plenty for a search measured in miles, and less
/// precise than where the person actually is. A [zip] code is sent instead
/// of a location, and the server searches around its centre.
Map<String, Object?> startSearchFor(
  SearchOrigin? origin,
  SearchPreferences search, {
  String? zip,
}) => {
  'origin':
      zip != null
          ? {'zip': zip}
          : {
            'lat': double.parse(origin!.lat.toStringAsFixed(3)),
            'lng': double.parse(origin.lng.toStringAsFixed(3)),
          },
  'radius': {'value': search.radius, 'unit': search.unit.label},
  'deckSize': search.deckSize,
  'includedCuisineIds': search.includedCuisineIds,
  'excludedCuisineIds': search.excludedCuisineIds,
  'openNowPreferred': search.openNowPreferred,
};

/// One card as the server stores it, in a deck or a room's results. Cards keep
/// meters; the app works in miles and shows the person's own unit.
Restaurant cardRestaurant(Map raw) => Restaurant(
  id: raw['id'] as String,
  name: raw['name'] as String,
  address: (raw['address'] as String?) ?? '',
  distance: ((raw['distanceMeters'] as num?) ?? 0) / _metersPerMile,
  latitude: (raw['latitude'] as num?)?.toDouble(),
  longitude: (raw['longitude'] as num?)?.toDouble(),
  phone: raw['phone'] as String?,
  website: raw['website'] as String?,
  userEntered: raw['userEntered'] == true,
  note: raw['note'] as String?,
  photoUrl: switch (raw['photoUrl']) {
    final String url when url.startsWith('https://') => url,
    _ => null,
  },
  foodLabels: _strings(raw['foodLabels']),
  dietary: _strings(raw['dietary']),
);

List<String> _strings(Object? raw) => [
  if (raw is List)
    for (final item in raw)
      if (item is String && item.isNotEmpty) item,
];

/// The cards of a stored deck, in deck order, with any notice cards placed
/// after the place they follow.
List<Restaurant> deckRestaurants(Map<String, dynamic> deck) {
  final places = [
    for (final raw in deck['candidates'] as List) cardRestaurant(raw as Map),
  ];
  final notices = deck['notices'];
  if (notices is! List || notices.isEmpty) return places;
  final after = <int, List<Restaurant>>{};
  for (final raw in notices) {
    if (raw is! Map ||
        raw['id'] is! String ||
        raw['after'] is! int ||
        raw['title'] is! String ||
        raw['text'] is! String) {
      continue;
    }
    (after[raw['after'] as int] ??= []).add(
      Restaurant.notice(
        id: raw['id'] as String,
        title: raw['title'] as String,
        text: raw['text'] as String,
      ),
    );
  }
  return [
    for (final (i, place) in places.indexed) ...[
      place,
      // Never after the last place, so the deck ends on one.
      if (i < places.length - 1) ...?after[i + 1],
    ],
  ];
}

/// The room's roster as people see it: host first, then you, then everyone
/// else by name, with guests last. Seats are the server's random keys; the
/// one matching [mySeat] is this person.
List<RoomPerson> roomPeople(Object? roster, String? mySeat) {
  if (roster is! Map) return const [];
  final people = [
    for (final entry in roster.entries)
      if (entry.value is Map)
        RoomPerson(
          name: (entry.value as Map)['name'] as String?,
          host: (entry.value as Map)['host'] == true,
          you: entry.key == mySeat,
        ),
  ];
  int rank(RoomPerson person) =>
      person.host
          ? 0
          : person.you
          ? 1
          : person.guest
          ? 3
          : 2;
  people.sort((a, b) {
    final order = rank(a).compareTo(rank(b));
    if (order != 0) return order;
    return (a.name ?? '').toLowerCase().compareTo((b.name ?? '').toLowerCase());
  });
  return people;
}

RoomResults? callableResults(Object? raw, int members) {
  if (raw is! Map) return null;
  final likes = <String, int>{
    for (final entry in Map<String, dynamic>.from(raw['likes'] as Map).entries)
      entry.key: (entry.value as num).toInt(),
  };
  final winnerCard = raw['winnerCard'];
  final backupCard = raw['backupCard'];
  return RoomResults(
    winnerId: raw['winner'] as String?,
    backupId: raw['backup'] as String?,
    likes: likes,
    participants: members,
    winnerCard: winnerCard is Map ? cardRestaurant(winnerCard) : null,
    backupCard: backupCard is Map ? cardRestaurant(backupCard) : null,
  );
}

/// Rooms managed by the server-side room callables. The server owns
/// membership, the deck and results; clients only write their own ballots.
class CallableRoomBackend implements RoomBackend {
  CallableRoomBackend({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
    Future<SearchOrigin> Function()? locate,
    DeviceLocator? locator,
    this.usesFictionalRestaurants = false,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _functions = functions ?? FirebaseFunctions.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _locator = locator ?? DeviceLocator(),
       _fixedLocate = locate;

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;
  final DeviceLocator _locator;
  final Future<SearchOrigin> Function()? _fixedLocate;

  Future<SearchOrigin> _locate() => _fixedLocate?.call() ?? _locator.locate();
  final _expiries = <String, Timestamp>{};

  String get _uid => _auth.currentUser!.uid;

  @override
  bool get usesDeviceLocation => true;
  // Only the local emulators deal decks from the server's fake provider.
  @override
  final bool usesFictionalRestaurants;
  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, Object?> data,
  ) async {
    final result = await _functions
        .httpsCallable(
          name,
          // The searching callables accept each App Check token only once.
          options:
              _searching.contains(name)
                  ? HttpsCallableOptions(limitedUseAppCheckToken: true)
                  : null,
        )
        .call(data);
    return Map<String, dynamic>.from(result.data as Map);
  }

  static const _searching = {'startRoom', 'createQuickPick'};

  @override
  Future<CreatedRoom> createRoom() async {
    final result = await _call('createRoom', {'requestId': const Uuid().v4()});
    return CreatedRoom(
      result['roomId'] as String,
      result['joinCode'] as String,
    );
  }

  @override
  Future<String> joinRoom(String typedCode) async {
    final request = joinRequestFor(typedCode);
    if (request == null) throw InvalidJoinCode();
    return (await _call('joinRoom', request))['roomId'] as String;
  }

  @override
  Stream<RoomState> watch(String roomId) {
    final room = _db.doc('rooms/$roomId');
    late final StreamController<RoomState> controller;
    final subscriptions = <StreamSubscription<Object?>>[];
    Map<String, dynamic>? roomData;
    String? mySeat;
    var deck = <Restaurant>[];
    var myVotes = <String>{};

    void emit() {
      final data = roomData;
      if (data == null || controller.isClosed) return;
      final status = data['status'] as String;
      final members = (data['memberCount'] as num?)?.toInt() ?? 1;
      controller.add(
        RoomState(
          id: roomId,
          joinCode: data['joinCode'] as String?,
          creatorId: data['creator'] as String,
          status: status,
          memberCount: members,
          restaurants: deck,
          myVoteCount: myVotes.length,
          votedIds: myVotes,
          resultsReady: status == 'closed',
          results: callableResults(data['results'], members),
          votingEndsAt: (data['votingEndsAt'] as Timestamp?)?.toDate(),
          untimed: data['untimed'] == true,
          people: roomPeople(data['roster'], mySeat),
        ),
      );
    }

    // Re-runs [apply] on the room as last known; set once [apply] exists.
    late final void Function() refresh;

    final deckLoader = DeckLoader<Map<String, dynamic>>(
      (deckId) async => (await _db.doc('restaurantDecks/$deckId').get()).data(),
    );
    void loadDeck(String deckId) {
      deckLoader.load(deckId, (stored) {
        if (controller.isClosed) return;
        // The deck may already have come with a catch-up answer.
        if (deck.isEmpty) deck = deckRestaurants(stored);
        // With the cards known, a finished voter starts waiting for results.
        refresh();
      });
    }

    late final RoomBackstop backstop;
    // What the server said when the listener was behind; kept until the
    // listener catches up, so a late snapshot cannot take the room backwards.
    Map<String, dynamic>? ahead;
    void apply(Map<String, dynamic>? data) {
      final caughtUp = ahead;
      if (data != null && caughtUp != null) {
        if (roomStage(data['status'] as String?) <
            roomStage(caughtUp['status'] as String?)) {
          data = {...data, ...caughtUp};
        } else {
          ahead = null;
        }
      }
      roomData = data;
      if (data == null) return;
      final status = data['status'];
      final votable = deck.where((place) => place.votable).length;
      // Waiting on the room to move on: a guest in the lobby (the host starts
      // it), anyone whose deck has not arrived yet, or anyone who has voted
      // on every card and waits for results.
      final waiting =
          (status == 'lobby' && data['creator'] != _uid) ||
          (status == 'voting' && deck.isEmpty) ||
          (status == 'voting' && votable > 0 && myVotes.length >= votable);
      if (waiting) {
        backstop.start();
      } else {
        backstop.stop();
      }
      _expiries[roomId] = data['expiresAt'] as Timestamp;
      final deckId = data['deckId'] as String?;
      // A closed room's deck is removed soon after; its results carry
      // the winner and backup instead.
      if (deckId != null && data['status'] != 'closed') loadDeck(deckId);
      emit();
    }

    refresh = () => apply(roomData);

    backstop = RoomBackstop(
      ask: () => _call('roomResults', {'roomId': roomId, 'view': 'room'}),
      // Voting without the cards is still the lobby as far as the screen
      // goes, so a deck read that stalls is caught up too.
      shown: () {
        final status = roomData?['status'] as String?;
        return status == 'voting' && deck.isEmpty ? 'lobby' : status;
      },
      onAhead: (view) {
        final room = Map<String, dynamic>.from(view['room'] as Map);
        final endsAt = room['votingEndsAt'] as num?;
        ahead = {
          'status': room['status'],
          'creator': room['creator'],
          'memberCount': room['memberCount'],
          'untimed': room['untimed'] == true,
          'deckId': room['deckId'],
          'votingEndsAt':
              endsAt == null
                  ? null
                  : Timestamp.fromMillisecondsSinceEpoch(endsAt.toInt()),
          'expiresAt': Timestamp.fromMillisecondsSinceEpoch(
            (room['expiresAt'] as num).toInt(),
          ),
          if (room['status'] == 'closed') 'results': view['results'],
        };
        // The deck comes with the answer, so nothing waits on another read.
        final cards = view['deck'];
        if (cards is Map && deck.isEmpty) {
          deck = deckRestaurants(Map<String, dynamic>.from(cards));
          deckLoader.markLoaded();
        }
        // Before any snapshot, the server's view is all there is.
        apply(roomData ?? ahead);
      },
      // Reconnecting makes Firestore resend the room as it is now.
      reconnect: () async {
        await _db.disableNetwork();
        await _db.enableNetwork();
      },
    );

    controller = StreamController<RoomState>(
      onListen: () {
        // Until the listener's first snapshot, the backstop is the only way
        // to learn the room if the live connection is slow from the start.
        backstop.start();
        subscriptions.add(
          room.snapshots().listen(
            (snapshot) => apply(snapshot.data()),
            onError: controller.addError,
          ),
        );
        // Only this person's own membership is readable; it says which seat
        // on the roster is theirs. Without it the roster just has no "you".
        subscriptions.add(
          room.collection('members').doc(_uid).snapshots().listen((snapshot) {
            mySeat = snapshot.data()?['seat'] as String?;
            emit();
          }, onError: (Object _) {}),
        );
        subscriptions.add(
          room.collection('votes/$_uid/ballot').snapshots().listen((snapshot) {
            myVotes = {for (final doc in snapshot.docs) doc.id};
            // A last vote can mean waiting for results now.
            refresh();
          }, onError: controller.addError),
        );
      },
      onCancel: () async {
        backstop.stop();
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
        await controller.close();
      },
    );
    return controller.stream;
  }

  @override
  Future<List<Restaurant>> start(
    String roomId, {
    required SearchPreferences search,
    String? zip,
    DeckLists lists = DeckLists.none,
  }) async {
    final origin = zip == null ? await _locate() : null;
    final started = await _call('startRoom', {
      'roomId': roomId,
      'search': startSearchFor(origin, search, zip: zip),
      'lists': lists.toJson(),
    });
    // A fresh start returns its cards; a repeat start points at the stored deck.
    if (started['candidates'] is List) return deckRestaurants(started);
    final deck = await _db.doc('restaurantDecks/${started['deckId']}').get();
    return deckRestaurants(deck.data()!);
  }

  @override
  Future<void> shareLists(
    String roomId, {
    required List<String> favorites,
    required List<String> never,
    List<String> closed = const [],
  }) => _call('shareRoomLists', {
    'roomId': roomId,
    'favorites': favorites,
    'never': never,
    'closed': closed,
  });

  @override
  Future<void> reportPlace(
    Restaurant place,
    PlaceProblem problem,
    ReportedFrom from,
  ) => _call('reportPlace', {
    'cardId': place.id,
    'kind': problem.name,
    ...from.toJson(),
  });

  @override
  Future<List<Restaurant>> startFromList(
    String roomId,
    List<OwnSpot> spots,
  ) async {
    final started = await _call('startRoomFromList', {
      'roomId': roomId,
      'spots': [for (final spot in spots) spot.toJson()],
    });
    if (started['candidates'] is List) return deckRestaurants(started);
    final deck = await _db.doc('restaurantDecks/${started['deckId']}').get();
    return deckRestaurants(deck.data()!);
  }

  Future<Timestamp> _expiryOf(String roomId) async {
    final known = _expiries[roomId];
    if (known != null) return known;
    final room = await _db.doc('rooms/$roomId').get();
    return _expiries[roomId] = room.data()!['expiresAt'] as Timestamp;
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
    // Ballots carry the room's expiry so they are cleaned up with it.
    await _db.doc('rooms/$roomId/votes/$_uid/ballot/${restaurant.id}').set({
      'liked': liked,
      'at': FieldValue.serverTimestamp(),
      'expiresAt': await _expiryOf(roomId),
      if (auto) 'auto': true,
    });
  }

  @override
  Future<void> setNoTimer(String roomId, {required bool noTimer}) =>
      _call('setNoTimer', {'roomId': roomId, 'noTimer': noTimer});

  @override
  Future<void> nudge(String roomId) async {
    // Closes the room on the server once everyone has voted or time is up.
    await _call('roomResults', {'roomId': roomId});
  }

  // Finds the location while the host waits for guests, so Start does not.
  @override
  Future<void> prepareStart() async {
    if (_fixedLocate == null) await _locator.warmUp();
  }

  String get _siteOrigin => siteOrigin(
    _functions.app.options.projectId,
    current: kIsWeb ? Uri.base : null,
  );

  @override
  Uri? joinLinkFor(String joinCode) => joinLink(_siteOrigin, joinCode);

  @override
  Uri sitePage(String path) => sitePageLink(_siteOrigin, path);

  @override
  Future<bool> updateRequired(int build) async =>
      (await _call('appStatus', {
        'build': build,
        if (_platform case final platform?) 'platform': platform,
      }))['updateRequired'] ==
      true;

  // Sent with the app-open check for the daily count of sessions by platform.
  static String? get _platform {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => null,
    };
  }

  @override
  Future<void> countEvent(String name) async {
    await _call('countEvent', {'name': name});
  }

  @override
  Future<InsightsReport> insightsReport(DateTime from, DateTime to) async =>
      InsightsReport.fromCallable(
        await _call('insightsReport', {
          'from': insightsDay(from),
          'to': insightsDay(to),
        }),
      );

  @override
  Future<LiveSearchAllowance?> liveSearchAllowance() async =>
      LiveSearchAllowance.fromCallable(await _call('liveSearchStatus', {}));

  @override
  Future<QuickPick> createQuickPick({
    required String requestId,
    required SearchPreferences search,
    String? zip,
  }) async {
    final origin = zip == null ? await _locate() : null;
    final view = await _call('createQuickPick', {
      'requestId': requestId,
      'search': startSearchFor(origin, search, zip: zip),
    });
    final deck = await _db.doc('restaurantDecks/${view['deckId']}').get();
    return quickPickFrom(view, {
      for (final card in deckRestaurants(deck.data()!)) card.id: card,
    });
  }

  @override
  Future<QuickPick> rerollQuickPick(QuickPick pick) async {
    // `from` is the card on screen, so a retried reroll cannot skip one.
    final view = await _call('rerollQuickPick', {
      'quickPickId': pick.id,
      'from': pick.position,
    });
    return quickPickFrom(view, pick.cards);
  }

  @override
  Future<String?> nickname() async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous || !user.emailVerified) return null;
    final profile = await _db.doc('userProfiles/${user.uid}').get();
    return profile.data()?['nickname'] as String?;
  }

  @override
  Future<String?> setNickname(String nickname) async =>
      (await _call('setNickname', {'nickname': nickname}))['nickname']
          as String?;
}

/// A Quick Pick as the server reports it, with the deck's cards.
QuickPick quickPickFrom(
  Map<String, dynamic> view,
  Map<String, Restaurant> cards,
) => QuickPick(
  id: view['quickPickId'] as String,
  position: (view['position'] as num).toInt(),
  restaurant: cards[view['candidateId']]!,
  rerollsLeft: (view['rerollsLeft'] as num).toInt(),
  cards: cards,
);
