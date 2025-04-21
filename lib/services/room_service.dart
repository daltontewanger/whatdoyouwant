import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

class RoomService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const int _roomCodeLength = 6;
  static const String _chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  /// Generates a random alphanumeric room code of a fixed length.
  static String _generateRoomCode() {
    final Random random = Random();
    return String.fromCharCodes(Iterable.generate(
      _roomCodeLength,
      (_) => _chars.codeUnitAt(random.nextInt(_chars.length)),
    ));
  }

  /// Creates a new room in Firestore, returning the generated room code.
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

  /// Adds a user to an existing room's participants list.
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

  /// Submits or updates a user's votes in the specified room.
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

  /// Returns a stream of the room document for real-time updates.
  Stream<DocumentSnapshot> roomStream(String roomCode) {
    return _firestore.collection('rooms').doc(roomCode).snapshots();
  }

  /// Fetches the room document once.
  Future<DocumentSnapshot> getRoomSnapshot(String roomCode) {
    return _firestore.collection('rooms').doc(roomCode).get();
  }
}
