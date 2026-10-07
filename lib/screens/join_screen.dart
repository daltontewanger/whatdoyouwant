import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/user.dart';
import '../services/active_room_store.dart';
import '../services/callable_room_backend.dart';
import '../services/room_backend.dart';
import 'results_screen.dart';
import 'swipe_screen.dart';

/// What to tell someone whose join failed. The server answers a wrong code,
/// a started room and a closed room the same way, so codes cannot be probed.
String joinErrorMessage(Object error) {
  if (error is InvalidJoinCode) return error.toString();
  if (error is FirebaseFunctionsException) {
    switch (error.code) {
      case 'permission-denied':
      case 'not-found':
        return 'No open room uses that code. Check it with the host; rooms stop taking new people once voting starts.';
      case 'failed-precondition':
        return 'This room is full. Rooms hold up to 15 people.';
      case 'resource-exhausted':
        return 'Too many attempts. Wait a minute and try again.';
      case 'unauthenticated':
        return 'This device could not be verified. Restart the app and try again.';
    }
  }
  return 'Could not join the room. Check your connection and try again.';
}

class JoinRoomScreen extends StatefulWidget {
  final AppUser currentUser;

  const JoinRoomScreen({super.key, required this.currentUser});

  @override
  JoinRoomScreenState createState() => JoinRoomScreenState();
}

class JoinRoomScreenState extends State<JoinRoomScreen> {
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _joinRoom() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a room code.')),
      );
      return;
    }
    // Go to waiting screen while generating options
    final scope = RoomBackendScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isLoading = true);
    try {
      final roomId = await scope.backend.joinRoom(code);
      await scope.activeRooms?.remember(ActiveRoom(roomId, host: false));
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder:
              (_) => WaitingForOptionsScreen(
                roomCode: roomId,
                currentUser: widget.currentUser,
              ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(joinErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.10),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.10),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back,
                        color: Colors.black54,
                        size: 28,
                      ),
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    "Join a Room",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium!.copyWith(
                      fontSize: 30,
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.3,
                      shadows: const [
                        Shadow(
                          color: Colors.black12,
                          blurRadius: 4,
                          offset: Offset(1, 2),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    UpperCaseTextFormatter(),
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Room Code',
                    hintText: 'Enter 6‑character code',
                  ),
                ),
                const SizedBox(height: 26),
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
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
        ),
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

class WaitingForOptionsScreen extends StatefulWidget {
  final String roomCode;
  final AppUser currentUser;

  const WaitingForOptionsScreen({
    super.key,
    required this.roomCode,
    required this.currentUser,
  });

  @override
  State<WaitingForOptionsScreen> createState() =>
      _WaitingForOptionsScreenState();
}

class _WaitingForOptionsScreenState extends State<WaitingForOptionsScreen> {
  Stream<RoomState>? _room;
  bool _navigated = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _room ??= RoomBackendScope.of(context).backend.watch(widget.roomCode);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.10),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.10),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back,
                        color: Colors.black54,
                        size: 28,
                      ),
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    "Waiting for Host...",
                    style: theme.textTheme.headlineMedium!.copyWith(
                      fontSize: 26,
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                StreamBuilder<RoomState>(
                  stream: _room,
                  builder: (context, snapshot) {
                    // A room the host closed or deleted can no longer be read.
                    if (snapshot.hasError ||
                        (snapshot.data?.status == 'closed' &&
                            snapshot.data!.restaurants.isEmpty)) {
                      RoomBackendScope.of(context).activeRooms?.forget();
                      return _RoomEnded(
                        message:
                            snapshot.hasError
                                ? 'This room is no longer available.'
                                : 'The host closed this room.',
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final room = snapshot.data!;

                    if (room.status != 'lobby' && room.restaurants.isNotEmpty) {
                      // Someone returning mid-vote continues where they left off.
                      final remaining = [
                        for (final r in room.restaurants)
                          if (!room.votedIds.contains(r.id)) r,
                      ];
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (_navigated || !mounted) return;
                        _navigated = true;
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder:
                                (_) =>
                                    remaining.isEmpty || room.status == 'closed'
                                        ? ResultsScreen(
                                          roomCode: widget.roomCode,
                                          restaurants: room.restaurants,
                                        )
                                        : SwipeScreen(
                                          roomCode: widget.roomCode,
                                          currentUser: widget.currentUser,
                                          radius: 5.0,
                                          maxOptions: remaining.length,
                                          restaurants: remaining,
                                        ),
                          ),
                        );
                      });
                      // Show an interim loading widget
                      return const Center(child: CircularProgressIndicator());
                    }

                    return Column(
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 20),
                        Text(
                          'Waiting for host to choose restaurant options...',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontSize: 18,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoomEnded extends StatelessWidget {
  const _RoomEnded({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      const SizedBox(height: 16),
      ElevatedButton(
        onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
        child: const Text('Back to Home'),
      ),
    ],
  );
}
