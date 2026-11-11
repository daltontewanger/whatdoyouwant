import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/demo_room_backend.dart';
import '../services/my_places.dart';
import '../services/room_backend.dart';
import '../themes/main_theme.dart';
import 'quick_pick_screen.dart';
import 'room_screen.dart';
import 'step_card.dart';
import '../services/usage_counts.dart';

/// The app's own screens on [DemoRoomBackend]: host a room with friends who
/// join and vote on their own, or have one place picked. Made-up places,
/// nothing saved and nothing sent, with a banner on every screen saying so.
class DemoScreen extends StatefulWidget {
  const DemoScreen({super.key, this.backend});

  /// Supplied by tests; otherwise each demo starts afresh.
  final DemoRoomBackend? backend;

  static Route<void> route() => MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => const DemoScreen(),
  );

  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen> {
  late final _backend = widget.backend ?? DemoRoomBackend();
  // Favorites and never marks work in the demo but are forgotten with it.
  final _places = MemoryMyPlaces();
  final _navigator = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      countTap(context, UsageEvent.demoStarted);
      RoomBackendScope.maybeOf(context)?.usageCounts?.markDemoSeen();
    });
  }

  @override
  void dispose() {
    if (widget.backend == null) _backend.dispose();
    _places.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final outer = RoomBackendScope.maybeOf(context);
    return Scaffold(
      backgroundColor: screenBackground,
      body: Column(
        children: [
          _DemoBanner(onExit: () => Navigator.of(context).pop()),
          Expanded(
            child: RoomBackendScope(
              backend: _backend,
              myPlaces: _places,
              // The person's own text size and timer choices carry over.
              accessibility: outer?.accessibility,
              demo: true,
              child: NavigatorPopHandler(
                onPopWithResult: (_) => _navigator.currentState?.maybePop(),
                child: Navigator(
                  key: _navigator,
                  onGenerateRoute:
                      (_) => MaterialPageRoute<void>(
                        builder: (_) => const _DemoStart(),
                      ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoBanner extends StatelessWidget {
  const _DemoBanner({required this.onExit});

  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    const brown = Color(0xFF5A4300);
    return Material(
      color: const Color(0xFFFFF1C9),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: Row(
            children: [
              const Icon(Icons.science_outlined, color: brown, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'Demo: made-up places, nothing is saved',
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      color: brown,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: onExit,
                style: TextButton.styleFrom(foregroundColor: brown),
                child: const Text(
                  'Exit demo',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where the demo begins: the two things it can show.
class _DemoStart extends StatelessWidget {
  const _DemoStart();

  static final you = AppUser(id: 'demo-you', name: 'You');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: screenBackground,
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Try the demo',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium!.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Every screen and button works like the real app. A few '
                    'friends join your room and vote along with you.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge!.copyWith(
                      color: const Color(0xFF4A5A52),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  StepCard(
                    step: const HomeStep(
                      'Host a room',
                      'Set up a search, watch friends join, swipe and see '
                          'where the group wants to eat.',
                      icon: Icons.groups_outlined,
                    ),
                    onTap:
                        () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder:
                                (_) => RoomScreen(
                                  currentUser: you,
                                  isCreator: true,
                                ),
                          ),
                        ),
                  ),
                  const SizedBox(height: 10),
                  StepCard(
                    step: const HomeStep(
                      'Tell Me What I Want',
                      'Get one place picked for you, and ask for another.',
                      icon: Icons.auto_awesome,
                    ),
                    onTap:
                        () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => const QuickPickScreen(),
                          ),
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
