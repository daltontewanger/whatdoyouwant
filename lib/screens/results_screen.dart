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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        _returnToHome();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.10),
        body: Center(
          child: SingleChildScrollView(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.symmetric(vertical: 38, horizontal: 18),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.10),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: StreamBuilder<DocumentSnapshot>(
                stream: _roomStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return _ResultsLoader();
                  }
                  if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
                    return Center(
                      child: Text(
                        'Error loading results.',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    );
                  }

                  final data = snapshot.data!.data() as Map<String, dynamic>;
                  final participantsMap = Map<String, dynamic>.from(data['participants'] ?? {});
                  final votesRaw = Map<String, dynamic>.from(data['votes'] ?? {});
                  final int totalParticipants = participantsMap.length;

                  // Show waiting state if not all participants have voted
                  if (votesRaw.length < totalParticipants) {
                    final remaining = totalParticipants - votesRaw.length;
                    return _ResultsLoader(remaining: remaining);
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
                      int v = voteCounts[r.id] ?? 0;
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
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    );
                  }

                  // Main "winning restaurant" display
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Text(
                          'Results',
                          style: Theme.of(context).textTheme.headlineMedium!.copyWith(
                                fontWeight: FontWeight.w900,
                                fontSize: 34,
                                letterSpacing: 1.2,
                                color: Theme.of(context).colorScheme.primary,
                                shadows: [
                                  const Shadow(
                                    color: Colors.black12,
                                    blurRadius: 4,
                                    offset: Offset(1, 2),
                                  ),
                                ],
                              ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'Winning Restaurant:',
                        style: Theme.of(context).textTheme.titleLarge!.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 22,
                              color: Colors.black87,
                            ),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              winning.name,
                              style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 24,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              winning.address,
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Distance: ${winning.distance.toStringAsFixed(2)} miles',
                              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                                    color: Colors.black54,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      Center(
                        child: Text(
                          'Votes: ${voteCounts[winning.id] ?? 0} of $totalParticipants',
                          style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                                color: Colors.black87,
                              ),
                        ),
                      ),
                      const SizedBox(height: 26),
                      Center(
                        child: ElevatedButton(
                          onPressed: _returnToHome,
                          style: Theme.of(context).elevatedButtonTheme.style,
                          child: const Text('Back to Home'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
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
        CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary,
        ),
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
