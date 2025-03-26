import 'dart:math';
import '../models/room.dart';
import '../models/user.dart';

class RoomService {
  static const int _roomCodeLength = 6;
  static const String _chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  /// Generates a random alphanumeric room code of a fixed length.
  static String generateRoomCode() {
    final Random random = Random();
    return String.fromCharCodes(Iterable.generate(
      _roomCodeLength,
      (_) => _chars.codeUnitAt(random.nextInt(_chars.length)),
    ));
  }

  /// Creates a new room with an optional initial list of users.
  static Room createRoom({List<AppUser>? initialUsers}) {
    final String roomCode = generateRoomCode();
    return Room(roomCode: roomCode, users: initialUsers ?? []);
  }
}
