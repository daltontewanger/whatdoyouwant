import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/room_service.dart';
import 'room_screen.dart';

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
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => RoomScreen(
            currentUser: widget.currentUser,
            isCreator: false,
            roomCode: code,
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error joining room: \$e')),
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
