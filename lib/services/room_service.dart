import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/restaurant.dart';

class RoomService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const int _roomCodeLength = 6;
  static const String _chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  static String _generateRoomCode() {
    final Random random = Random();
    return String.fromCharCodes(Iterable.generate(
      _roomCodeLength,
      (_) => _chars.codeUnitAt(random.nextInt(_chars.length)),
    ));
  }

  Future<String> createRoom(String creatorId) async {
    final String roomCode = _generateRoomCode();
    await _firestore.collection('rooms').doc(roomCode).set({
      'creator': creatorId,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'active',
      'participants': { creatorId: true },
      'votes': {},
    });
    return roomCode;
  }

  Future<void> setRoomOptionsAndStart({
    required String roomCode,
    required double radius,
    required int maxOptions,
    required List<Restaurant> options,
  }) async {
    final roomRef = _firestore.collection('rooms').doc(roomCode);
    final restaurantMaps = options.map((r) => r.toJson()).toList();
    await roomRef.update({
      'settings': {
        'radius': radius,
        'maxOptions': maxOptions,
      },
      'restaurants': restaurantMaps,
      'status': 'started',
    });
  }

  Future<void> joinRoom(String roomCode, String userId) async {
    final DocumentReference roomRef = _firestore.collection('rooms').doc(roomCode);
    final snap = await roomRef.get();
    if (!snap.exists) {
      throw Exception('Room not found');
    }
    await roomRef.update({
      'participants.$userId': true,
    });
  }

  Future<void> submitUserVotes(
    String roomCode,
    String userId,
    Map<String, bool> userVotes,
  ) async {
    final DocumentReference roomRef = _firestore.collection('rooms').doc(roomCode);
    await roomRef.update({
      'votes.$userId': userVotes,
    });
  }

  Stream<DocumentSnapshot> roomStream(String roomCode) {
    return _firestore.collection('rooms').doc(roomCode).snapshots();
  }

  Future<DocumentSnapshot> getRoomSnapshot(String roomCode) {
    return _firestore.collection('rooms').doc(roomCode).get();
  }
}
