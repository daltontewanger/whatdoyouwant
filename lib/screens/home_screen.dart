import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/user.dart';
import '../services/room_backend.dart';
import 'account_preview_screen.dart';
import 'room_screen.dart';
import 'join_screen.dart';

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
  }

  @override
  void dispose() {
    _animationController.dispose();
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
      MaterialPageRoute(
        builder:
            (_) => AccountPreviewScreen(
              accounts: accounts,
              showRoomPreview: false,
            ),
      ),
    );
  }

  Widget _accountStatus(ThemeData theme) {
    final accounts = RoomBackendScope.of(context).accounts!;
    return StreamBuilder<User?>(
      stream: accounts.auth.userChanges(),
      initialData: accounts.auth.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        final registered = user != null && !user.isAnonymous;
        return Column(
          children: [
            Text(
              registered
                  ? 'Signed in as ${user.email ?? user.displayName ?? 'your account'}'
                  : 'Playing as a guest',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                TextButton(
                  onPressed: _isLoading ? null : _openAccount,
                  child: Text(registered ? 'Account' : 'Sign in'),
                ),
                if (registered)
                  TextButton(
                    onPressed:
                        _isLoading
                            ? null
                            : () async {
                              final messenger = ScaffoldMessenger.of(context);
                              try {
                                await accounts.signOut();
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Signed out. You are playing as a guest.',
                                    ),
                                  ),
                                );
                              } catch (_) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('Could not sign out.'),
                                  ),
                                );
                              }
                            },
                    child: const Text('Sign out'),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _createRoom() async {
    final scope = RoomBackendScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (scope.backend.requiresVerifiedHost && !_verifiedHost) {
      // Hosts need a verified account; guests can still join without one.
      await _openAccount();
      if (!mounted) return;
      if (!_verifiedHost) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Sign in with a verified email to create a room. Guests can join without an account.',
            ),
          ),
        );
        return;
      }
    }
    setState(() => _isLoading = true);
    try {
      final room = await scope.backend.createRoom();
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
      );
    } catch (e) {
      messenger.showSnackBar(
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
                  padding: const EdgeInsets.symmetric(
                    vertical: 20,
                    horizontal: 20,
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
                          if (RoomBackendScope.of(context).accounts !=
                              null) ...[
                            const SizedBox(height: 12),
                            _accountStatus(theme),
                          ],
                          const SizedBox(height: 32),
                          TextButton(
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final url = Uri.parse(
                                'https://daltontewanger.github.io/whatdoyouwant/privacy.html',
                              );
                              try {
                                final opened = await launchUrl(
                                  url,
                                  mode: LaunchMode.externalApplication,
                                );
                                if (!opened) {
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Could not open the privacy policy.',
                                      ),
                                    ),
                                  );
                                }
                              } catch (e) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Could not open the privacy policy.',
                                    ),
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
