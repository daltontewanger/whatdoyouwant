import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/restaurant.dart';

class RoomService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Code generation 
  static const int _roomCodeLength = 6;
  static const String _chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  static String _randomCode() {
    final r = Random();
    return String.fromCharCodes(Iterable.generate(
      _roomCodeLength,
      (_) => _chars.codeUnitAt(r.nextInt(_chars.length)),
    ));
  }

  static Future<String> _generateUniqueRoomCode() async {
    for (int i = 0; i < 5; i++) {
      final code = _randomCode();
      if (!(await _firestore.collection('rooms').doc(code).get()).exists) {
        return code;
      }
    }
    return DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase();
  }

  //  Create room (lobby)
  Future<String> createRoom(String creatorId) async {
    final code = await _generateUniqueRoomCode();
    final ref = _firestore.collection('rooms').doc(code);

    final expiresAt = Timestamp.fromDate(
      DateTime.now().add(const Duration(hours: 72)),
    );

    await ref.set({
      'creator': creatorId,
      'createdAt': FieldValue.serverTimestamp(),
      'startedAt': null,
      'closedAt': null,
      'expiresAt': expiresAt,

      'status': 'lobby',          // lobby -> voting -> closed
      'participants': {creatorId: true},

      'settings': {'radius': null, 'maxOptions': null},
      'restaurants': [],

      // Aggregated votes map: votes[uid][restaurantId] = bool
      'votes': {},

      // Per-user progress and timing
      // votesMeta[uid] = { done: bool, lastVoteAt: TS, count: int }
      'votesMeta': {},

      // Stats to avoid expensive scans
      // stats = { restaurantsCount, participantsCount, doneCount }
      'stats': {
        'restaurantsCount': 0,
        'participantsCount': 1,
        'doneCount': 0,
      },
    });

    return code;
  }

  // Join rules/helpers 
  bool _isExpired(Map<String, dynamic> data) {
    final expires = data['expiresAt'];
    if (expires is Timestamp) {
      return expires.toDate().isBefore(DateTime.now());
    }
    return false;
  }

  Future<bool> isRoomJoinable(String roomCode) async {
    final snap = await _firestore.collection('rooms').doc(roomCode).get();
    if (!snap.exists) return false;
    final data = snap.data()!;
    if (_isExpired(data)) return false;
    return (data['status'] ?? 'closed') == 'lobby';
  }

  Future<void> joinRoom(String roomCode, String userId) async {
    final ref = _firestore.collection('rooms').doc(roomCode);
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('Room not found');
      final data = snap.data() as Map<String, dynamic>;
      if (_isExpired(data)) throw Exception('This room has expired.');

      final status = (data['status'] ?? 'closed') as String;
      if (status != 'lobby') {
        throw Exception('This room is no longer joinable.');
      }

      final participants = Map<String, dynamic>.from(data['participants'] ?? {});
      if (!participants.containsKey(userId)) {
        participants[userId] = true;
        final stats = Map<String, dynamic>.from(data['stats'] ?? {});
        final int pCount = (stats['participantsCount'] ?? participants.length) as int;
        tx.update(ref, {
          'participants': participants,
          'stats.participantsCount': pCount + 1,
        });
      }
    });
  }

  // Start voting 
  Future<void> setRoomOptionsAndStart({
    required String roomCode,
    required double radius,
    required int maxOptions,
    required List<Restaurant> options,
  }) async {
    final ref = _firestore.collection('rooms').doc(roomCode);

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('Room not found');
      final data = snap.data() as Map<String, dynamic>;
      if (_isExpired(data)) throw Exception('This room has expired.');

      final participants = Map<String, dynamic>.from(data['participants'] ?? {});
      if (participants.isEmpty) {
        throw Exception('No participants in room.');
      }

      final restaurantMaps = options.map((r) => r.toJson()).toList();
      final restaurantsCount = restaurantMaps.length;

      // Initialize votesMeta for each participant so no one is immediately stale.
      final Map<String, Object?> metaUpdates = {};
      final nowTS = FieldValue.serverTimestamp();
      for (final uid in participants.keys) {
        metaUpdates['votesMeta.$uid.done'] = false;
        metaUpdates['votesMeta.$uid.lastVoteAt'] = nowTS;
        metaUpdates['votesMeta.$uid.count'] = 0;
      }

      tx.update(ref, {
        'settings': {'radius': radius, 'maxOptions': maxOptions},
        'restaurants': restaurantMaps,
        'status': 'voting',
        'startedAt': FieldValue.serverTimestamp(),
        'stats.restaurantsCount': restaurantsCount,
        'stats.participantsCount': participants.length,
        'stats.doneCount': 0,
        ...metaUpdates,
      });
    });
  }

  // Incremental vote
  // Records a single vote and updates per-user meta and global done stats atomically.
  Future<void> submitIncrementalVote({
    required String roomCode,
    required String userId,
    required String restaurantId,
    required bool liked,
    required int currentIndex,
    required int totalCount,
  }) async {
    final roomRef = _firestore.collection('rooms').doc(roomCode);
    final ballotRef = roomRef.collection('votes').doc(userId).collection('ballot').doc(restaurantId);

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(roomRef);
      if (!snap.exists) throw Exception('Room not found');
      final data = snap.data() as Map<String, dynamic>;
      if (_isExpired(data)) throw Exception('This room has expired.');
      if ((data['status'] ?? 'closed') != 'voting') {
        throw Exception('Voting is not active in this room.');
      }

      // Stats & existing votes/meta
      final stats = Map<String, dynamic>.from(data['stats'] ?? {});
      final int restaurantsCount =
          (stats['restaurantsCount'] ?? (data['restaurants'] as List?)?.length ?? totalCount) as int;

      final votes = Map<String, dynamic>.from(data['votes'] ?? {});
      final myVotes = Map<String, dynamic>.from(votes[userId] ?? {});

      // If this restaurant already has a value for user, ignore
      if (myVotes.containsKey(restaurantId)) {
        return;
      }

      // Add this vote locally
      myVotes[restaurantId] = liked;

      // Determine if this vote makes user "done"
      final wasDone = Map<String, dynamic>.from(data['votesMeta']?[userId] ?? {})['done'] == true;
      final bool nowDone = myVotes.length >= restaurantsCount;

      // Prepare updates
      final Map<String, Object?> updates = {
        'votes.$userId.$restaurantId': liked,
        'votesMeta.$userId.lastVoteAt': FieldValue.serverTimestamp(),
        'votesMeta.$userId.count': myVotes.length,
      };

      if (!wasDone && nowDone) {
        updates['votesMeta.$userId.done'] = true;
        updates['stats.doneCount'] = FieldValue.increment(1);
      }

      tx.update(roomRef, updates);

      // Also write to per-user ballot subcollection (diagnostic/history)
      tx.set(ballotRef, {
        'liked': liked,
        'at': FieldValue.serverTimestamp(),
        'index': currentIndex,
      }, SetOptions(merge: true));
    });
  }

  // Watchdog: vote-idle (no vote in 30s)
  // For each participant not done and with lastVoteAt older than [idle],
  // fills remaining restaurants as NO and marks them done. Closes room if all done.
  Future<void> timeoutStaleByVote({
    required String roomCode,
    Duration idle = const Duration(seconds: 30),
  }) async {
    final roomRef = _firestore.collection('rooms').doc(roomCode);
    final snap = await roomRef.get();
    if (!snap.exists) return;
    final data = snap.data() as Map<String, dynamic>;

    if ((data['status'] ?? 'closed') != 'voting') return;

    final participants = Map<String, dynamic>.from(data['participants'] ?? {});
    if (participants.isEmpty) return;

    final stats = Map<String, dynamic>.from(data['stats'] ?? {});
    final int restaurantsCount =
        (stats['restaurantsCount'] ?? (data['restaurants'] as List?)?.length ?? 0) as int;
    if (restaurantsCount == 0) return;

    final restaurants = List<Map<String, dynamic>>.from(data['restaurants'] ?? const []);
    final restaurantIds = restaurants.map((e) => (e['id'] ?? '') as String).where((id) => id.isNotEmpty).toList();
    if (restaurantIds.isEmpty) return;

    final votes = Map<String, dynamic>.from(data['votes'] ?? {});
    final votesMeta = Map<String, dynamic>.from(data['votesMeta'] ?? {});
    int doneInThisPass = 0;

    final Map<String, Object?> updates = {};

    final now = DateTime.now();
    for (final uid in participants.keys) {
      final meta = Map<String, dynamic>.from(votesMeta[uid] ?? {});
      final bool done = meta['done'] == true;
      if (done) continue;

      final lastTS = meta['lastVoteAt'];
      final last = (lastTS is Timestamp) ? lastTS.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
      final tooOld = now.isAfter(last.add(idle));

      if (!tooOld) continue;

      // Fill missing as NO
      final myVotes = Map<String, dynamic>.from(votes[uid] ?? {});
      int added = 0;
      for (final rid in restaurantIds) {
        if (!myVotes.containsKey(rid)) {
          updates['votes.$uid.$rid'] = false;
          added++;
        }
      }

      // Mark done if added any or if already had full set
      if (added > 0 || myVotes.length >= restaurantsCount) {
        updates['votesMeta.$uid.done'] = true;
        updates['votesMeta.$uid.count'] = restaurantsCount;
        updates['votesMeta.$uid.lastVoteAt'] = FieldValue.serverTimestamp();
        doneInThisPass++;
      }
    }

    if (updates.isEmpty) return;

    // Increment doneCount accordingly and close
    updates['stats.doneCount'] = FieldValue.increment(doneInThisPass);

    // After we stage updates, check if this would close the room
    final int currentDone = (stats['doneCount'] ?? 0) as int;
    final int participantsCount = (stats['participantsCount'] ?? participants.length) as int;
    final int finalDone = currentDone + doneInThisPass;
    final bool allDone = finalDone >= participantsCount;

    if (allDone) {
      updates['status'] = 'closed';
      updates['closedAt'] = FieldValue.serverTimestamp();
    }

    await roomRef.update(updates);
  }

  // Close room
  Future<void> closeRoom(String roomCode) async {
    final ref = _firestore.collection('rooms').doc(roomCode);
    await ref.set({
      'status': 'closed',
      'closedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // Streams and fetch
  Stream<DocumentSnapshot> roomStream(String roomCode) {
    return _firestore.collection('rooms').doc(roomCode).snapshots();
  }

  Future<DocumentSnapshot> getRoomSnapshot(String roomCode) {
    return _firestore.collection('rooms').doc(roomCode).get();
  }
}
