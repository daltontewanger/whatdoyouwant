import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user.dart';
import '../models/restaurant.dart';
import '../services/room_service.dart';
import 'swipe_screen.dart';

class JoinRoomScreen extends StatefulWidget {
  final AppUser currentUser;

  const JoinRoomScreen({super.key, required this.currentUser});

  @override
  _JoinRoomScreenState createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends State<JoinRoomScreen> {
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _joinRoom() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a room code.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await RoomService().joinRoom(code, widget.currentUser.id);
      if (!mounted) return;
      // Go to waiting screen while generating options
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => WaitingForOptionsScreen(
            roomCode: code,
            currentUser: widget.currentUser,
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error joining room: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join Room')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)),
                labelText: 'Room Code',
                hintText: 'Enter 6‑character code',
              ),
            ),
            const SizedBox(height: 20),
            _isLoading
                ? const CircularProgressIndicator()
                : SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _joinRoom,
                      child: const Text('Join'),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

class WaitingForOptionsScreen extends StatelessWidget {
  final String roomCode;
  final AppUser currentUser;

  const WaitingForOptionsScreen({
    super.key,
    required this.roomCode,
    required this.currentUser,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Waiting for Host')),
      body: StreamBuilder<DocumentSnapshot>(
        stream: RoomService().roomStream(roomCode),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('Error joining room.'));
          }
          final data = snapshot.data!.data() as Map<String, dynamic>;

          // Check if restaurants are present
          final restaurantsData = data['restaurants'] as List<dynamic>?;
          final settings = data['settings'] as Map<String, dynamic>?;

          if (restaurantsData != null &&
              settings != null &&
              restaurantsData.isNotEmpty) {
            // Parse restaurants and settings
            final List<Restaurant> restaurants = restaurantsData
                .map((r) => Restaurant.fromJson(Map<String, dynamic>.from(r)))
                .toList();
            final double radius = (settings['radius'] as num?)?.toDouble() ?? 5.0;
            final int maxOptions = (settings['maxOptions'] as num?)?.toInt() ?? 5;

            // Navigate to SwipeScreen automatically
            // Use addPostFrameCallback to prevent navigation build conflicts
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => SwipeScreen(
                    roomCode: roomCode,
                    currentUser: currentUser,
                    radius: radius,
                    maxOptions: maxOptions,
                    restaurants: restaurants,
                  ),
                ),
              );
            });
            // Show an interim loading widget
            return const Center(child: CircularProgressIndicator());
          }

          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                CircularProgressIndicator(),
                SizedBox(height: 20),
                Text('Waiting for host to choose restaurant options...'),
              ],
            ),
          );
        },
      ),
    );
  }
}
