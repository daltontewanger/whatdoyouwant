import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user.dart';
import '../services/active_room_store.dart';
import '../services/room_backend.dart';
import '../services/site_links.dart';
import 'account_action_screen.dart';
import 'account_screen.dart';
import 'room_screen.dart';
import 'join_screen.dart';
import 'main_shell.dart';

class HomeScreen extends StatefulWidget {
  final String currentUid;
  const HomeScreen({super.key, required this.currentUid});

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  // Read on use: signing in, out or deleting an account changes the user.
  AppUser get _currentUser {
    final user = FirebaseAuth.instance.currentUser;
    return AppUser(
      id: user != null && user.uid.isNotEmpty ? user.uid : 'guest',
      name: 'Guest',
    );
  }

  bool _isLoading = false;
  ActiveRoom? _activeRoom;
  ActiveRoomStore? _activeRooms;

  late final AnimationController _animationController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1650),
    );
    _scaleAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.elasticOut),
    );
    _animationController.forward();
    // A shared join link or a button on the public site opened the app.
    final link = kIsWeb ? takeLaunchLink(Uri.base) : null;
    if (link != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        switch (link.target) {
          case AppLinkTarget.host:
            _createRoom();
          case AppLinkTarget.join:
            _joinRoom(code: link.joinCode);
          case AppLinkTarget.account:
            _openAccount();
          case AppLinkTarget.accountAction:
            _finishAccountLink(link.mode!, link.code!);
        }
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _activeRooms?.removeListener(_loadActiveRoom);
    super.dispose();
  }

  bool get _verifiedHost {
    final user = FirebaseAuth.instance.currentUser;
    return user != null && !user.isAnonymous && user.emailVerified;
  }

  Future<void> _openAccount() async {
    final accounts = RoomBackendScope.of(context).accounts;
    if (accounts == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AccountScreen(accounts: accounts)),
    );
  }

  // A verification or reset email brought the person back to the app.
  Future<void> _finishAccountLink(String mode, String code) async {
    final accounts = RoomBackendScope.of(context).accounts;
    if (accounts == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) =>
                AccountActionScreen(accounts: accounts, mode: mode, code: code),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = RoomBackendScope.of(context).activeRooms;
    if (store == _activeRooms) return;
    _activeRooms?.removeListener(_loadActiveRoom);
    _activeRooms = store?..addListener(_loadActiveRoom);
    _loadActiveRoom();
  }

  Future<void> _loadActiveRoom() async {
    final room = await _activeRooms?.load();
    if (mounted) setState(() => _activeRoom = room);
  }

  /// Takes someone back into the room they were in before the app closed.
  Future<void> _returnToRoom() async {
    final scope = RoomBackendScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final active = _activeRoom;
    if (active == null) return;
    setState(() => _isLoading = true);
    try {
      final room = await scope.backend
          .watch(active.id)
          .first
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (room.status == 'closed' && room.restaurants.isEmpty) {
        throw StateError('Room closed');
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) =>
                  active.host && room.status == 'lobby'
                      ? RoomScreen(
                        currentUser: _currentUser,
                        isCreator: true,
                        roomCode: active.id,
                        joinCode: room.joinCode,
                      )
                      : WaitingForOptionsScreen(
                        roomCode: active.id,
                        currentUser: _currentUser,
                      ),
        ),
      );
    } catch (_) {
      await scope.activeRooms?.forget();
      messenger.showSnackBar(
        const SnackBar(content: Text('That room is no longer available.')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
      await _loadActiveRoom();
    }
  }

  // The logo's butter yellow makes the room in progress stand out from the
  // white card; dark brown text on it keeps AA contrast.
  Widget _activeRoomBanner(ThemeData theme) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF1C9),
      border: Border.all(color: const Color(0xFFF7C948), width: 1.5),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(44, 14, 44, 16),
          child: Column(
            children: [
              Text(
                'You have a room in progress.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge!.copyWith(
                  color: const Color(0xFF5A4300),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _returnToRoom,
                  child: const Text(
                    'Return to room',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: IconButton(
            tooltip: 'Dismiss',
            icon: const Icon(Icons.close, color: Color(0xFF5A4300)),
            onPressed:
                _isLoading
                    ? null
                    : () async {
                      await RoomBackendScope.of(context).activeRooms?.forget();
                      await _loadActiveRoom();
                    },
          ),
        ),
      ],
    ),
  );

  Future<void> _createRoom() async {
    final scope = RoomBackendScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (!_verifiedHost) {
      // Hosts need a verified account; guests can still join without one.
      // Signing in lands back here on home rather than in a new room.
      await _openAccount();
      if (!mounted || _verifiedHost) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Sign in with a verified email to create a room. Guests can join without an account.',
          ),
        ),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final room = await scope.backend.createRoom();
      await scope.activeRooms?.remember(ActiveRoom(room.id, host: true));
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => RoomScreen(
                currentUser: _currentUser,
                isCreator: true,
                roomCode: room.id,
                joinCode: room.joinCode,
              ),
        ),
      ).then((_) => _loadActiveRoom());
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Could not create a room. Check your connection and try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _joinRoom({String? code}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => JoinRoomScreen(currentUser: _currentUser, initialCode: code),
      ),
    ).then((_) => _loadActiveRoom());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.10),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            const maxCardWidth = 420.0;

            final card = Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxCardWidth,
                  minHeight: constraints.maxHeight,
                ),
                child: Container(
                  // Room at the bottom for the floating bar, which sits
                  // inside this card just under Join Room.
                  padding: EdgeInsets.fromLTRB(
                    20,
                    20,
                    20,
                    20 + FloatingBarInset.of(context),
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.10,
                        ),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Top - Logo and Title
                      Column(
                        children: [
                          Image.asset(
                            'assets/icon/wdywicon2.png',
                            width: 88,
                            height: 88,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(height: 8),
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
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 20.0, bottom: 10.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "1. ",
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 17,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    "Create a room and invite your friends, or join one with a code.",
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 17,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "2. ",
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 17,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    "Swipe through food options and vote on your favorites.",
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 17,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "3. ",
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 17,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    "When everyone matches on a spot, you'll instantly see where to eat!",
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 17,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Center - Image
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: ScaleTransition(
                          scale: _scaleAnimation,
                          child: AspectRatio(
                            aspectRatio: 1.83,
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: theme.colorScheme.primary,
                                  width: 4,
                                ),
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.33),
                                    blurRadius: 18,
                                    spreadRadius: 2,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: FittedBox(
                                  fit: BoxFit.contain,
                                  child: Image.asset('assets/images/wdyw.png'),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Bottom - Buttons and Privacy
                      Column(
                        children: [
                          if (_activeRoom != null) _activeRoomBanner(theme),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _createRoom,
                              child: const Text(
                                'Create Room',
                                style: TextStyle(fontSize: 16),
                              ),
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
                                side: BorderSide(
                                  color: theme.colorScheme.primary,
                                  width: 2,
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                'Join Room',
                                style: TextStyle(fontSize: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );

            // Allow scroll if content does not fit
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: card,
              ),
            );
          },
        ),
      ),
    );
  }
}
