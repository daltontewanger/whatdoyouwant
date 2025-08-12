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
  late Stream<DocumentSnapshot> _roomStream;

  @override
  void initState() {
    super.initState();
    _roomStream = RoomService().roomStream(widget.roomCode);
  }

  void _returnToHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen(currentUid: '')),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        _returnToHome();
      },
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
                            // Small, centered loader — does NOT stretch the card
                            return const Center(child: _ResultsLoader());
                          }

                          final rawData = snapshot.data?.data();
                          if (rawData == null) {
                            return const Center(child: Text('No result data.'));
                          }

                          final data = rawData as Map<String, dynamic>;
                          final participantsMap = Map<String, dynamic>.from(data['participants'] ?? {});
                          final votesRaw = Map<String, dynamic>.from(data['votes'] ?? {});
                          final int totalParticipants = participantsMap.length;

                          // Waiting until all have voted
                          if (votesRaw.length < totalParticipants) {
                            final remaining = totalParticipants - votesRaw.length;
                            // Keep the loader small & centered
                            return Center(child: _ResultsLoader(remaining: remaining));
                          }

                          // Aggregate vote counts
                          final Map<String, int> voteCounts = {};
                          votesRaw.forEach((userId, userVotes) {
                            if (userVotes is Map<String, dynamic>) {
                              userVotes.forEach((resId, liked) {
                                if (liked == true) {
                                  voteCounts[resId] = (voteCounts[resId] ?? 0) + 1;
                                }
                              });
                            }
                          });

                          // Determine winner
                          Restaurant? winning;
                          for (var r in widget.restaurants) {
                            if ((voteCounts[r.id] ?? 0) == totalParticipants) {
                              winning = r;
                              break;
                            }
                          }
                          if (winning == null) {
                            int maxVotes = -1;
                            List<Restaurant> top = [];
                            for (var r in widget.restaurants) {
                              final v = voteCounts[r.id] ?? 0;
                              if (v > maxVotes) {
                                maxVotes = v;
                                top = [r];
                              } else if (v == maxVotes) {
                                top.add(r);
                              }
                            }
                            if (top.isNotEmpty) {
                              top.sort((a, b) => a.distance.compareTo(b.distance));
                              winning = top.first;
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

                          // Full-height, evenly spaced layout for results
                          return IntrinsicHeight(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // TOP — Title
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

                                // Spacer pushes middle content to vertical center
                                const Spacer(),

                                // MIDDLE — Winner & votes
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
                                        style: theme.textTheme.bodyMedium!.copyWith(color: Colors.black54),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Center(
                                  child: Text(
                                    'Votes: ${voteCounts[winning.id] ?? 0} of $totalParticipants',
                                    style: theme.textTheme.bodyLarge!.copyWith(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 18,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),

                                // Spacer pushes button to bottom
                                const Spacer(),

                                // BOTTOM — Button
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

// Loader/waiting state for consistent style
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
