import 'dart:async';
import 'package:flutter/material.dart';
import '../models/restaurant.dart';
import '../services/result_nudges.dart';
import '../services/room_backend.dart';
import 'home_screen.dart';

class ResultsScreen extends StatefulWidget {
  final String roomCode;
  final List<Restaurant> restaurants;

  const ResultsScreen({
    super.key,
    required this.roomCode,
    required this.restaurants,
  });

  @override
  ResultsScreenState createState() => ResultsScreenState();
}

class ResultsScreenState extends State<ResultsScreen> {
  Stream<RoomState>? _roomStream;
  late RoomBackend _backend;
  bool _closedOnce = false;
  Timer? _kickTimer;
  ResultNudges? _nudges;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_roomStream != null) return;
    _backend = RoomBackendScope.of(context).backend;
    _roomStream = _backend.watch(widget.roomCode);

    if (_backend.clientClosesRooms) {
      // Client-closed rooms also time out idle voters on each nudge, so they
      // keep the frequent kick until results are ready.
      _kickTimer = Timer.periodic(const Duration(seconds: 6), (_) async {
        try {
          await _backend.nudge(widget.roomCode);
        } catch (_) {}
      });
    } else {
      _nudges = ResultNudges(() => _backend.nudge(widget.roomCode))..start();
    }
  }

  @override
  void dispose() {
    _kickTimer?.cancel();
    _nudges?.stop();
    super.dispose();
  }

  void _returnToHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen(currentUid: '')),
      (route) => false,
    );
  }

  void _closeRoomOnce() {
    if (_closedOnce) return;
    _closedOnce = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _backend.close(widget.roomCode);
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) => _returnToHome(),
      child: Scaffold(
        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.10),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Center(
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 420),
                      padding: const EdgeInsets.symmetric(
                        vertical: 38,
                        horizontal: 18,
                      ),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
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
                      child: StreamBuilder<RoomState>(
                        stream: _roomStream,
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return Center(
                              child:
                                  snapshot.hasError
                                      ? const Text('No result data.')
                                      : const _ResultsLoader(),
                            );
                          }
                          final room = snapshot.data!;

                          if (!room.resultsReady) {
                            if (_backend.clientClosesRooms) {
                              _backend
                                  .nudge(widget.roomCode)
                                  .catchError((_) {});
                            } else {
                              _nudges?.votingEndsAt(room.votingEndsAt);
                            }
                            return Center(
                              child: _ResultsLoader(
                                remaining: room.remainingVoters,
                                waiting: true,
                              ),
                            );
                          }

                          _kickTimer?.cancel();
                          _nudges?.stop();
                          // Finished rooms are no longer offered on Home.
                          RoomBackendScope.of(context).activeRooms?.forget();

                          final results = room.results;
                          final Map<String, Restaurant> byId = {
                            for (final r in widget.restaurants) r.id: r,
                            for (final r in room.restaurants) r.id: r,
                          };
                          final Restaurant? winning =
                              results == null ? null : byId[results.winnerId];

                          if (winning == null || results == null) {
                            return Center(
                              child: Text(
                                'No results available.',
                                style: theme.textTheme.bodyLarge,
                              ),
                            );
                          }
                          final int winnerLikes = results.winnerLikes;
                          final int participantsCount = results.participants;

                          // Close room once there are results
                          if (_backend.clientClosesRooms) _closeRoomOnce();

                          return IntrinsicHeight(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Center(
                                  child: Text(
                                    'Results',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.headlineMedium!
                                        .copyWith(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 34,
                                          letterSpacing: 1.2,
                                          color: theme.colorScheme.primary,
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
                                const SizedBox(height: 12),

                                const Spacer(),

                                Text(
                                  'Winning Restaurant:',
                                  style: theme.textTheme.titleLarge!.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 22,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Container(
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary.withValues(
                                      alpha: 0.08,
                                    ),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 18,
                                    horizontal: 18,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        winning.name,
                                        style: theme.textTheme.headlineSmall!
                                            .copyWith(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 24,
                                            ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        winning.address,
                                        style: theme.textTheme.bodyLarge,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Distance: ${winning.distance.toStringAsFixed(2)} miles',
                                        style: theme.textTheme.bodyMedium!
                                            .copyWith(color: Colors.black54),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Center(
                                  child: Text(
                                    'Votes: $winnerLikes of $participantsCount',
                                    style: theme.textTheme.bodyLarge!.copyWith(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 18,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),

                                const Spacer(),

                                Center(
                                  child: ElevatedButton(
                                    onPressed: _returnToHome,
                                    style: theme.elevatedButtonTheme.style,
                                    child: const Text('Back to Home'),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// Loader/waiting state
class _ResultsLoader extends StatelessWidget {
  final int? remaining;
  final bool waiting;
  const _ResultsLoader({this.remaining, this.waiting = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 20),
        CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 28),
        Text(
          remaining != null
              ? 'Waiting for $remaining more vote${remaining! > 1 ? 's' : ''}...'
              : waiting
              ? 'Waiting for everyone to finish voting...'
              : 'Loading results...',
          style: Theme.of(context).textTheme.bodyLarge!.copyWith(fontSize: 18),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
