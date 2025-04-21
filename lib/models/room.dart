import 'package:cloud_firestore/cloud_firestore.dart';

class Room {
  final String roomCode;
  final String creatorId;
  final DateTime createdAt;
  final String status;
  final Map<String, bool> participants; // userId -> joined
  final Map<String, Map<String, bool>> votes; // userId -> (restaurantId -> liked)

  Room({
    required this.roomCode,
    required this.creatorId,
    required this.createdAt,
    required this.status,
    required this.participants,
    required this.votes,
  });

  /// Construct a Room from Firestore document snapshot
  factory Room.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final participantsMap = <String, bool>{};
    if (data['participants'] is Map) {
      (data['participants'] as Map<String, dynamic>)
          .forEach((key, value) => participantsMap[key] = value as bool);
    }
    final votesMap = <String, Map<String, bool>>{};
    if (data['votes'] is Map) {
      (data['votes'] as Map<String, dynamic>).forEach((userId, v) {
        final userVotes = <String, bool>{};
        if (v is Map<String, dynamic>) {
          v.forEach((resId, liked) {
            userVotes[resId] = liked as bool;
          });
        }
        votesMap[userId] = userVotes;
      });
    }
    return Room(
      roomCode: doc.id,
      creatorId: data['creator'] as String,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      status: data['status'] as String,
      participants: participantsMap,
      votes: votesMap,
    );
  }

  /// Convert Room to JSON for Firestore write
  Map<String, dynamic> toJson() {
    return {
      'creator': creatorId,
      'createdAt': FieldValue.serverTimestamp(),
      'status': status,
      'participants': participants,
      'votes': votes,
    };
  }
}
