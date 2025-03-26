import 'user.dart';

class Room {
  final String roomCode;
  final List<AppUser> users;

  Room({
    required this.roomCode,
    this.users = const [],
  });

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      roomCode: json['roomCode'] as String,
      users: (json['users'] as List<dynamic>)
          .map((user) => AppUser.fromJson(user))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'roomCode': roomCode,
      'users': users.map((user) => user.toJson()).toList(),
    };
  }
}
