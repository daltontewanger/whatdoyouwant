import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/own_spot.dart';
import '../models/user.dart';
import '../services/active_room_store.dart';
import '../services/room_backend.dart';
import '../services/search_defaults.dart';
import '../services/site_links.dart';
import 'account_action_screen.dart';
import 'account_screen.dart';
import 'quick_pick_screen.dart';
import 'room_screen.dart';
import 'join_screen.dart';
import 'main_shell.dart';
import 'own_list_screen.dart';
import 'search_setup_screen.dart';
import 'bubble_icons.dart';
import 'step_card.dart';

const _inkSoft = Color(0xFF4A5A52);

/// How the app works, then the other ways to decide.
const _steps = [
  HomeStep(
    1,
    'Start a room',
    'Invite friends with a code, link or QR code.',
    StepColor.yellow,
  ),
  HomeStep(
    2,
    'Everyone swipes',
    'Yes or no on nearby spots, each on your own phone.',
    StepColor.blue,
  ),
  HomeStep(
    3,
    'See where to eat',
    'The winner, a backup and directions.',
    StepColor.green,
  ),
  quickPickStep,
  ownListStep,
];

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
  // white card; dark brown text on it keeps AA contrast. One compact row: a
  // bobbing alert bubble, the message, and the same arrow as the step cards.
  Widget _activeRoomBanner(ThemeData theme) {
    const brown = Color(0xFF5A4300);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: const Color(0xFFFFF1C9),
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFFF7C948), width: 1.5),
          borderRadius: BorderRadius.circular(18),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _isLoading ? null : _returnToRoom,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              children: [
                const ExcludeSemantics(
                  child: _Bobbing(
                    child: BubbleIcon(BubbleGlyph.notice, size: 36),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Semantics(
                    button: true,
                    label: 'You have a room in progress. Return to room',
                    excludeSemantics: true,
                    child: Text(
                      'You have a room in progress',
                      style: theme.textTheme.bodyLarge!.copyWith(
                        color: brown,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                Tooltip(
                  message: 'Return to room',
                  child: ExcludeSemantics(
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_forward,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Dismiss',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, color: brown, size: 20),
                  onPressed:
                      _isLoading
                          ? null
                          : () async {
                            await RoomBackendScope.of(
                              context,
                            ).activeRooms?.forget();
                            await _loadActiveRoom();
                          },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Live searches need a verified account; guests can still join rooms.
  /// Signing in lands back here on home rather than in what was asked for.
  Future<bool> _verifiedOrSignIn(String toDo) async {
    if (_verifiedHost) return true;
    final messenger = ScaffoldMessenger.of(context);
    await _openAccount();
    if (!mounted || _verifiedHost) return false;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Sign in with a verified email to $toDo. Guests can join without an account.',
        ),
      ),
    );
    return false;
  }

  /// The extra ways to decide, shared by the step cards and the bar's menu.
  Future<void> openQuickPick() => _quickPick();
  Future<void> openOwnList() => _ownList();
  Future<void> openSearchSettings() => _searchSettings();
  void openJoin() => _joinRoom();

  VoidCallback? _stepAction(HomeStep step) => switch (step.number) {
    4 => _isLoading ? null : _quickPick,
    5 => _isLoading ? null : _ownList,
    _ => null,
  };

  Future<void> _ownList() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => OwnListScreen(onStartRoom: _createRoom),
    ),
  );

  /// Saved search choices, edited without starting a room or pick.
  Future<void> _searchSettings() async {
    final defaults = RoomBackendScope.of(context).searchDefaults;
    final current = await defaults?.load() ?? const SearchPreferences();
    if (!mounted) return;
    final chosen = await Navigator.push<SearchSetup>(
      context,
      MaterialPageRoute(
        builder:
            (_) =>
                SearchSetupScreen(initial: current, initialZip: defaults?.zip),
      ),
    );
    if (chosen == null) return;
    defaults?.zip = chosen.zip;
    await defaults?.save(chosen.search);
  }

  Future<void> _quickPick() async {
    if (!await _verifiedOrSignIn('use Tell Me What I Want') || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QuickPickScreen()),
    );
  }

  /// Creates a room and opens its lobby; with [ownSpots], the room swipes on
  /// those spots from the person's own list instead of a search.
  Future<void> _createRoom([List<OwnSpot>? ownSpots]) async {
    final scope = RoomBackendScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (!await _verifiedOrSignIn('create a room')) return;
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
                ownSpots: ownSpots,
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
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
                      const SizedBox(height: 8),
                      Text(
                        "I know, it's not that simple. Swipe together and let "
                        'the group decide where to eat.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: _inkSoft,
                          height: 1.4,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                        child: ScaleTransition(
                          scale: _scaleAnimation,
                          child: AspectRatio(
                            aspectRatio: 1.83,
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: theme.colorScheme.primary,
                                  width: 3,
                                ),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.25),
                                    blurRadius: 14,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(17),
                                child: FittedBox(
                                  fit: BoxFit.contain,
                                  child: Image.asset('assets/images/wdyw.png'),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_activeRoom != null) _activeRoomBanner(theme),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed:
                                  _isLoading ? null : () => _createRoom(),
                              child: const Text(
                                'Create Room',
                                style: TextStyle(fontSize: 16),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
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
                      // The buttons come first so regulars can get going;
                      // the steps below are there for first-timers.
                      const SizedBox(height: 24),
                      for (final step in _steps) ...[
                        StepCard(step: step, onTap: _stepAction(step)),
                        const SizedBox(height: 10),
                      ],
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

/// Bobs its child gently up and down, like the site's speech bubbles. Still
/// when the device asks for reduced motion.
class _Bobbing extends StatefulWidget {
  const _Bobbing({required this.child});

  final Widget child;

  @override
  State<_Bobbing> createState() => _BobbingState();
}

class _BobbingState extends State<_Bobbing>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder:
        (context, child) => Transform.translate(
          offset: Offset(0, -4 * Curves.easeInOut.transform(_controller.value)),
          child: child,
        ),
    child: widget.child,
  );
}
