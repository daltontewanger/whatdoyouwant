import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/user.dart';
import '../services/room_service.dart';
import 'room_screen.dart';
import 'join_screen.dart';

class HomeScreen extends StatefulWidget {
  final String currentUid;
  const HomeScreen({super.key, required this.currentUid});

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
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
          builder: (_) => RoomScreen(
            currentUser: _currentUser,
            isCreator: true,
            roomCode: code,
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error creating room: $e')),
      );
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
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.primary.withOpacity(0.10),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withOpacity(0.10),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/icon/wdywicon2.png',
                  width: 88,
                  height: 88,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 16),
                Text(
                  "What Do You Want?!",
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium!.copyWith(
                    fontSize: 36,
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    shadows: [
                      const Shadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: Offset(1, 2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Image.asset('assets/images/wdyw.gif', height: 180),
                const SizedBox(height: 36),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _createRoom,
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Create Room'),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _joinRoom,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.surface,
                      foregroundColor: theme.colorScheme.primary,
                      side: BorderSide(color: theme.colorScheme.primary, width: 2),
                      elevation: 0,
                    ),
                    child: const Text('Join Room'),
                  ),
                ),
                const SizedBox(height: 32),
                TextButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final url = Uri.parse(
                      'https://daltontewanger.github.io/whatdoyouwant/privacy.html',
                    );
                    if (await canLaunchUrl(url)) {
                      await launchUrl(url, mode: LaunchMode.externalApplication);
                    } else {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Could not open the privacy policy.'),
                        ),
                      );
                    }
                  },
                  child: Text(
                    'Privacy Policy',
                    style: theme.textTheme.bodyLarge!.copyWith(
                      decoration: TextDecoration.underline,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
