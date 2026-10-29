import 'dart:async';
import 'package:flutter/material.dart';
import '../models/restaurant.dart';
import '../services/result_nudges.dart';
import '../services/room_backend.dart';
import 'place_card.dart';

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
  ResultNudges? _nudges;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_roomStream != null) return;
    _backend = RoomBackendScope.of(context).backend;
    _roomStream = _backend.watch(widget.roomCode);

    _nudges = ResultNudges(() => _backend.nudge(widget.roomCode))..start();
  }

  @override
  void dispose() {
    _nudges?.stop();
    super.dispose();
  }

  // Back to the app's own first screen, which keeps its bottom bar and
  // notices that the room is over.
  void _returnToHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      // A back gesture or button goes home too. When Back to Home pops this
      // screen itself, didPop is true and there is nothing left to do.
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _returnToHome();
      },
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
                            _nudges?.votingEndsAt(room.votingEndsAt);
                            return Center(
                              child: _ResultsLoader(
                                remaining: room.remainingVoters,
                                waiting: true,
                              ),
                            );
                          }

                          _nudges?.stop();
                          // Finished rooms are no longer offered on Home.
                          RoomBackendScope.of(context).activeRooms?.forget();

                          final results = room.results;
                          final Map<String, Restaurant> byId = {
                            for (final r in widget.restaurants) r.id: r,
                            for (final r in room.restaurants) r.id: r,
                          };
                          final Restaurant? winning =
                              results == null
                                  ? null
                                  : byId[results.winnerId] ??
                                      results.winnerCard;

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
                                PlaceCard(restaurant: winning),
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
