import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/restaurant.dart';
import '../services/room_service.dart';
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
  late final Stream<DocumentSnapshot> _roomStream;
  bool _closedOnce = false;
  Timer? _kickTimer;

  @override
  void initState() {
    super.initState();
    _roomStream = RoomService().roomStream(widget.roomCode);

    // Starts a kicker and stops once throttled in RoomService, then cancels as soon as results are ready
    _kickTimer = Timer.periodic(const Duration(seconds: 6), (_) async {
      try {
        await RoomService().timeoutStaleByVote(roomCode: widget.roomCode);
      } catch (_) {
      }
    });
  }

  @override
  void dispose() {
    _kickTimer?.cancel();
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
        await RoomService().closeRoom(widget.roomCode);
      } catch (_) {
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) => _returnToHome(),
      child: Scaffold(
        backgroundColor: theme.colorScheme.primary.withOpacity(0.10),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Center(
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 420),
                      padding: const EdgeInsets.symmetric(vertical: 38, horizontal: 18),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.primary.withOpacity(0.10),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: StreamBuilder<DocumentSnapshot>(
                        stream: _roomStream,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: _ResultsLoader());
                          }

                          final rawData = snapshot.data?.data();
                          if (rawData == null) {
                            return const Center(child: Text('No result data.'));
                          }

                          final data = rawData as Map<String, dynamic>;

                          final Map<String, dynamic> participants =
                              Map<String, dynamic>.from(data['participants'] ?? {});
                          final Map<String, dynamic> votesRaw =
                              Map<String, dynamic>.from(data['votes'] ?? {});
                          final Map<String, dynamic> stats =
                              Map<String, dynamic>.from(data['stats'] ?? {});
                          final List<dynamic> restaurantsDoc =
                              List<dynamic>.from(data['restaurants'] ?? const []);

                          final String status = (data['status'] ?? 'closed') as String;

                          // Count with fallbacks
                          final int participantsCount =
                              (stats['participantsCount'] ?? participants.length) is int
                                  ? (stats['participantsCount'] ?? participants.length) as int
                                  : participants.length;

                          final int restaurantsCount =
                              (stats['restaurantsCount'] ?? restaurantsDoc.length) is int
                                  ? (stats['restaurantsCount'] ?? restaurantsDoc.length) as int
                                  : restaurantsDoc.length;

                          int doneCount = (stats['doneCount'] ?? 0) is int
                              ? stats['doneCount'] as int
                              : 0;

                          // Fallback compute if doneCount is missing
                          if (doneCount == 0 && participantsCount > 0 && restaurantsCount > 0) {
                            int computed = 0;
                            for (final uid in participants.keys) {
                              final mv = Map<String, dynamic>.from(votesRaw[uid] ?? {});
                              if (mv.length >= restaurantsCount) computed++;
                            }
                            doneCount = computed;
                          }

                          // Ensure the kicker is running if still waiting
                          final bool waitingForOthers =
                              (status == 'voting') &&
                              (participantsCount > 0) &&
                              (restaurantsCount > 0) &&
                              (doneCount < participantsCount);

                          if (waitingForOthers) {
                            // Extra nudge right here just in case
                            RoomService().timeoutStaleByVote(roomCode: widget.roomCode)
                              .catchError((_) {});
                            final remaining = (participantsCount - doneCount).clamp(0, 9999);
                            return Center(child: _ResultsLoader(remaining: remaining));
                          }

                          // Stop the kicker.
                          _kickTimer?.cancel();

                          final Map<String, Restaurant> byId = {
                            for (final r in widget.restaurants) r.id: r
                          };

                          final Map<String, int> likeCounts = {};
                          votesRaw.forEach((uid, userVotes) {
                            if (userVotes is Map<String, dynamic>) {
                              userVotes.forEach((resId, liked) {
                                if (liked == true) {
                                  likeCounts[resId] = (likeCounts[resId] ?? 0) + 1;
                                }
                              });
                            }
                          });

                          Restaurant? winning;
                          int winnerLikes = 0;

                          if (likeCounts.isEmpty) {
                            if (widget.restaurants.isNotEmpty) {
                              final sorted = [...widget.restaurants]
                                ..sort((a, b) => a.distance.compareTo(b.distance));
                              winning = sorted.first;
                              winnerLikes = 0;
                            }
                          } else {
                            int maxLikes = -1;
                            for (final c in likeCounts.values) {
                              if (c > maxLikes) maxLikes = c;
                            }
                            final topIds = likeCounts.entries
                                .where((e) => e.value == maxLikes)
                                .map((e) => e.key)
                                .toList();

                            if (topIds.length == 1) {
                              winning = byId[topIds.first];
                              winnerLikes = maxLikes;
                            } else {
                              final candidates = <Restaurant>[];
                              for (final id in topIds) {
                                final r = byId[id];
                                if (r != null) candidates.add(r);
                              }
                              if (candidates.isEmpty && widget.restaurants.isNotEmpty) {
                                candidates.addAll(widget.restaurants);
                              }
                              if (candidates.isNotEmpty) {
                                candidates.sort((a, b) => a.distance.compareTo(b.distance));
                                winning = candidates.first;
                                winnerLikes = likeCounts[winning.id] ?? maxLikes;
                              }
                            }
                          }

                          if (winning == null) {
                            return Center(
                              child: Text(
                                'No results available.',
                                style: theme.textTheme.bodyLarge,
                              ),
                            );
                          }

                          // Close room once there are results
                          _closeRoomOnce();

                          return IntrinsicHeight(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Center(
                                  child: Text(
                                    'Results',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.headlineMedium!.copyWith(
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
                                    color: theme.colorScheme.primary.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        winning.name,
                                        style: theme.textTheme.headlineSmall!.copyWith(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 24,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(winning.address, style: theme.textTheme.bodyLarge),
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
  const _ResultsLoader({this.remaining});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 20),
        CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 28),
        Text(
          remaining == null
              ? 'Loading results...'
              : 'Waiting for $remaining more vote${remaining! > 1 ? 's' : ''}...',
          style: Theme.of(context).textTheme.bodyLarge!.copyWith(fontSize: 18),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
