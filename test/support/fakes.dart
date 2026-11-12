// Fakes and helpers shared by the widget tests.
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatdoyouwant/models/user.dart';
import 'package:whatdoyouwant/screens/room_screen.dart';
import 'package:whatdoyouwant/models/insights.dart';
import 'package:whatdoyouwant/models/own_spot.dart';
import 'package:whatdoyouwant/models/restaurant.dart';
import 'package:whatdoyouwant/services/active_room_store.dart';
import 'package:whatdoyouwant/services/live_search.dart';
import 'package:whatdoyouwant/services/my_places.dart';
import 'package:whatdoyouwant/services/own_list.dart';
import 'package:whatdoyouwant/services/room_backend.dart';
import 'package:whatdoyouwant/services/search_defaults.dart';

class FakeRoomBackend implements RoomBackend {
  final room = StreamController<RoomState>.broadcast();
  final joined = <String>[];
  int nudges = 0;
  Object? createError;
  Object? startError;
  Object? voteError;

  @override
  bool usesDeviceLocation = false;
  @override
  bool get usesFictionalRestaurants => true;

  @override
  Future<String> joinRoom(String typedCode) async {
    joined.add(typedCode);
    return 'ROOM-ID';
  }

  @override
  Stream<RoomState> watch(String roomId) => room.stream;
  String? savedNickname;
  Object? nicknameError;
  final nicknames = <String>[];
  @override
  Future<String?> nickname() async => savedNickname;
  @override
  Future<String?> setNickname(String nickname) async {
    nicknames.add(nickname);
    if (nicknameError case final error?) throw error;
    return savedNickname = nickname.isEmpty ? null : nickname;
  }

  @override
  Future<HostProgress?> nudge(String roomId) async {
    nudges++;
    return progress;
  }

  /// What the host's waiting screen hears back from a nudge.
  HostProgress? progress;
  int finishes = 0;

  @override
  Future<void> finishWithoutInactive(String roomId) async => finishes++;

  /// What the server says when the screen asks whether voting has ended.
  bool closed = false;

  @override
  Future<bool> votingClosed(String roomId) async => closed;
  LiveSearchAllowance? allowance;
  @override
  Future<LiveSearchAllowance?> liveSearchAllowance() async => allowance;
  @override
  Uri? joinLinkFor(String joinCode) =>
      Uri.parse('https://example.test/app/join/$joinCode');
  @override
  Uri sitePage(String path) => Uri.parse('https://example.test$path');
  bool tooOld = false;
  @override
  Future<bool> updateRequired(int build) async => tooOld;
  final events = <String>[];
  @override
  Future<void> countEvent(String name) async => events.add(name);
  InsightsReport? insights;
  Object? insightsError;
  final insightsAsked = <(DateTime, DateTime)>[];
  @override
  Future<InsightsReport> insightsReport(DateTime from, DateTime to) async {
    insightsAsked.add((from, to));
    if (insightsError case final error?) throw error;
    return insights ?? InsightsReport.fromCallable(const {});
  }

  int prepared = 0;
  @override
  Future<void> prepareStart() async => prepared++;
  @override
  Future<CreatedRoom> createRoom() async =>
      throw createError ?? UnimplementedError();
  final started = <SearchPreferences>[];
  final startedZips = <String?>[];
  final startedLists = <DeckLists>[];
  final shared = <(String, List<String>, List<String>)>[];
  final sharedClosed = <List<String>>[];
  @override
  Future<void> shareLists(
    String roomId, {
    required List<String> favorites,
    required List<String> never,
    List<String> closed = const [],
  }) async {
    shared.add((roomId, favorites, never));
    sharedClosed.add(closed);
  }

  final reports = <(String, PlaceProblem, String)>[];
  Object? reportError;
  @override
  Future<void> reportPlace(
    Restaurant place,
    PlaceProblem problem,
    ReportedFrom from,
  ) async {
    if (reportError case final error?) throw error;
    reports.add((place.id, problem, from.roomId ?? from.quickPickId!));
  }

  @override
  Future<List<Restaurant>> start(
    String roomId, {
    required SearchPreferences search,
    String? zip,
    DeckLists lists = DeckLists.none,
  }) async {
    started.add(search);
    startedZips.add(zip);
    startedLists.add(lists);
    throw startError ?? UnimplementedError();
  }

  final startedFromList = <List<OwnSpot>>[];
  @override
  Future<List<Restaurant>> startFromList(
    String roomId,
    List<OwnSpot> spots,
  ) async {
    startedFromList.add(spots);
    throw startError ?? UnimplementedError();
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
    if (voteError != null) throw voteError!;
    votes.add((index, liked));
    autoVotes.add(auto);
  }

  final votes = <(int, bool)>[];
  final autoVotes = <bool>[];
  final noTimers = <bool>[];
  @override
  Future<void> setNoTimer(String roomId, {required bool noTimer}) async =>
      noTimers.add(noTimer);

  /// Each Quick Pick request as (requestId, search).
  final picks = <(String, SearchPreferences)>[];
  final pickZips = <String?>[];
  Object? pickError;
  int rerolls = 0;
  @override
  Future<QuickPick> createQuickPick({
    required String requestId,
    required SearchPreferences search,
    String? zip,
  }) async {
    picks.add((requestId, search));
    pickZips.add(zip);
    if (pickError != null) throw pickError!;
    return quickPickAt(0);
  }

  @override
  Future<QuickPick> rerollQuickPick(QuickPick pick) async {
    rerolls++;
    return quickPickAt(pick.position + 1);
  }
}

/// A pick over [deck] that allows one reroll, like a two-card deck.
QuickPick quickPickAt(int position) => QuickPick(
  id: 'PICK',
  position: position,
  restaurant: deck[position],
  rerollsLeft: deck.length - 1 - position,
  cards: {for (final card in deck) card.id: card},
);

final deck = [
  Restaurant(id: 'a', name: 'Demo Pizza', address: '1 Example', distance: 0.25),
  Restaurant(id: 'b', name: 'Demo Tacos', address: '2 Example', distance: 0.5),
];

RoomState state({
  String status = 'voting',
  bool ready = false,
  int? remaining,
  RoomResults? results,
  Set<String> voted = const {},
  List<Restaurant>? restaurants,
  DateTime? votingEndsAt,
  bool untimed = false,
  List<RoomPerson> people = const [],
}) => RoomState(
  id: 'ROOM-ID',
  joinCode: null,
  creatorId: 'host',
  status: status,
  memberCount: 3,
  restaurants: restaurants ?? deck,
  myVoteCount: voted.length,
  votedIds: voted,
  resultsReady: ready,
  remainingVoters: remaining,
  results: results,
  votingEndsAt: votingEndsAt,
  untimed: untimed,
  people: people,
);

/// The screen under test inside the room backend scope, with any stores it needs.
Widget app(
  FakeRoomBackend backend,
  Widget home, {
  ActiveRoomStore? rooms,
  SearchDefaultsStore? defaults,
  MyPlacesStore? places,
  OwnListStore? ownList,
}) => RoomBackendScope(
  backend: backend,
  activeRooms: rooms,
  searchDefaults: defaults,
  myPlaces: places,
  ownList: ownList,
  child: MaterialApp(home: home),
);

Widget hostLobby(FakeRoomBackend backend, {SearchDefaultsStore? defaults}) =>
    app(
      backend,
      RoomScreen(
        currentUser: AppUser(id: 'host', name: 'Host'),
        roomCode: 'ROOM-ID',
        joinCode: 'AB3K7X',
      ),
      defaults: defaults,
    );

/// Signed out, with nothing else needed to draw the Account tab.
class ShellAuth extends Fake implements FirebaseAuth {
  @override
  User? get currentUser => null;

  @override
  Stream<User?> userChanges() => Stream.value(null);
}

class FakeUser extends Fake implements User {
  bool anonymous = true;
  bool verified = false;
  bool failLink = false;
  bool failReauth = false;
  String? reloadError;
  String? reloadMessage;
  List<String> providers = ['password'];
  final calls = <String>[];
  @override
  List<UserInfo> get providerData => [for (final id in providers) FakeInfo(id)];
  @override
  Future<UserCredential> linkWithProvider(AuthProvider provider) async {
    calls.add('link:${provider.providerId}');
    if (failLink) {
      // Google hands back the credential it just issued, as the SDKs do.
      throw FirebaseAuthException(
        code: 'credential-already-in-use',
        credential: GoogleAuthProvider.credential(idToken: 'fixture'),
      );
    }
    anonymous = false;
    return FakeCredential();
  }

  @override
  Future<UserCredential> linkWithPopup(AuthProvider provider) async {
    calls.add('popup:${provider.providerId}');
    anonymous = false;
    return FakeCredential();
  }

  @override
  Future<UserCredential> reauthenticateWithProvider(
    AuthProvider provider,
  ) async {
    calls.add('reauth:${provider.providerId}');
    return FakeCredential();
  }

  @override
  bool get isAnonymous => anonymous;
  @override
  bool get emailVerified => verified;
  @override
  String get email => 'fixture@example.test';
  @override
  Future<UserCredential> linkWithCredential(AuthCredential credential) async {
    calls.add('link');
    if (failLink) {
      throw FirebaseAuthException(code: 'credential-already-in-use');
    }
    anonymous = false;
    return FakeCredential();
  }

  @override
  Future<void> sendEmailVerification([ActionCodeSettings? settings]) async {
    calls.add('verify');
    verifySettings = settings;
  }

  ActionCodeSettings? verifySettings;

  @override
  Future<void> reload() async {
    calls.add('reload');
    if (reloadError != null) {
      throw FirebaseAuthException(code: reloadError!, message: reloadMessage);
    }
  }

  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    calls.add('token:$forceRefresh');
    return null;
  }

  @override
  Future<UserCredential> reauthenticateWithCredential(
    AuthCredential credential,
  ) async {
    calls.add('reauth');
    if (failReauth) throw FirebaseAuthException(code: 'invalid-credential');
    return FakeCredential();
  }

  @override
  Future<void> delete() async {
    calls.add('delete');
  }
}

class FakeCredential extends Fake implements UserCredential {}

class FakeInfo extends Fake implements UserInfo {
  FakeInfo(this.providerId);
  @override
  final String providerId;
}

class FakeAuth extends Fake implements FirebaseAuth {
  User? user;
  int creates = 0;
  int guests = 0;
  int signOuts = 0;
  int providerSignIns = 0;
  int credentialSignIns = 0;
  int emailSignIns = 0;
  String? resetError;
  ActionCodeSettings? resetSettings;
  String? resetSentTo;
  // One-time codes from emailed links, and what they belong to.
  final resetCodes = <String, String>{};
  final applyCodes = <String>{};
  final changedPasswords = <String, String>{};
  String? signInError;
  bool signInVerified = false;
  final _changes = StreamController<User?>.broadcast();
  FakeAuth(this.user);
  void _set(User? next) {
    user = next;
    _changes.add(next);
  }

  @override
  User? get currentUser => user;
  @override
  Future<void> signOut() async {
    signOuts++;
    _set(null);
  }

  @override
  Future<UserCredential> signInAnonymously() async {
    guests++;
    _set(FakeUser());
    return FakeCredential();
  }

  @override
  Stream<User?> userChanges() async* {
    yield user;
    yield* _changes.stream;
  }

  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    credentialSignIns++;
    _set(FakeUser()..anonymous = false);
    return FakeCredential();
  }

  @override
  Future<UserCredential> signInWithProvider(AuthProvider provider) async {
    providerSignIns++;
    _set(FakeUser()..anonymous = false);
    return FakeCredential();
  }

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    emailSignIns++;
    if (signInError != null) throw FirebaseAuthException(code: signInError!);
    _set(
      FakeUser()
        ..anonymous = false
        ..verified = signInVerified,
    );
    return FakeCredential();
  }

  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    creates++;
    return FakeCredential();
  }

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    ActionCodeSettings? actionCodeSettings,
  }) async {
    if (resetError != null) throw FirebaseAuthException(code: resetError!);
    resetSentTo = email;
    resetSettings = actionCodeSettings;
  }

  @override
  Future<String> verifyPasswordResetCode(String code) async {
    final email = resetCodes[code];
    if (email == null) throw FirebaseAuthException(code: 'invalid-action-code');
    return email;
  }

  @override
  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  }) async {
    final email = resetCodes.remove(code);
    if (email == null) throw FirebaseAuthException(code: 'expired-action-code');
    changedPasswords[email] = newPassword;
  }

  @override
  Future<void> applyActionCode(String code) async {
    if (!applyCodes.remove(code)) {
      throw FirebaseAuthException(code: 'invalid-action-code');
    }
  }
}

String placeId(int n) => 'c${n.toRadixString(16).padLeft(20, '0')}';

Restaurant place(int n, String name) => Restaurant(
  id: placeId(n),
  name: name,
  address: '$n Example Street',
  distance: 0.5,
);

/// Lets a card fly off and a snack bar slide in.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
