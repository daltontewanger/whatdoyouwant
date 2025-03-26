import 'package:flutter/material.dart';
import 'room_screen.dart';
import '../services/room_service.dart';
import '../models/room.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('What Do You Want?!'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/wdyw.gif',
              height: 200, // Adjust the size as needed
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                // Create a new room using the RoomService
                Room newRoom = RoomService.createRoom();
                // Navigate to RoomScreen, passing the generated room code
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RoomScreen(
                      isCreator: true,
                      roomCode: newRoom.roomCode,
                    ),
                  ),
                );
              },
              child: const Text('Create Room'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                // Navigate to a placeholder Join Room screen
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const JoinRoomScreenPlaceholder(),
                  ),
                );
              },
              child: const Text('Join Room'),
            ),
          ],
        ),
      ),
    );
  }
}

class JoinRoomScreenPlaceholder extends StatelessWidget {
  const JoinRoomScreenPlaceholder({super.key});
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Join Room'),
      ),
      body: const Center(
        child: Text(
          'This is a placeholder for the Join Room screen',
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
