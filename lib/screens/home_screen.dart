import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user.dart';
import '../services/room_service.dart';
import 'room_screen.dart';
import 'join_screen.dart';

class HomeScreen extends StatefulWidget {
  final String currentUid;
  const HomeScreen({super.key, required this.currentUid});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late AppUser _currentUser;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _currentUser = AppUser(
      id: user != null && user.uid.isNotEmpty ? user.uid : 'guest',
      name: 'Guest',
    );
  }

  Future<void> _createRoom() async {
    setState(() => _isLoading = true);
    try {
      final String code = await RoomService().createRoom(_currentUser.id);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => RoomScreen(
                currentUser: _currentUser,
                isCreator: true,
                roomCode: code,
              ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error creating room: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _joinRoom() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JoinRoomScreen(currentUser: _currentUser),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('What Do You Want?!')),
      body: Center(
        child:
            _isLoading
                ? const CircularProgressIndicator()
                : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset('assets/images/wdyw.gif', height: 200),
                    const SizedBox(height: 40),
                    ElevatedButton(
                      onPressed: _createRoom,
                      child: const Text('Create Room'),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _joinRoom,
                      child: const Text('Join Room'),
                    ),
                  ],
                ),
      ),
    );
  }
}
