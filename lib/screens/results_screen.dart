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
        // On any back action, send to home and clear stack
        _returnToHome();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Results')),
        body: StreamBuilder<DocumentSnapshot>(
          stream: _roomStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError ||
                !snapshot.hasData ||
                !snapshot.data!.exists) {
              return const Center(child: Text('Error loading results.'));
            }

            final data = snapshot.data!.data() as Map<String, dynamic>;
            final participantsMap = Map<String, dynamic>.from(
              data['participants'] ?? {},
            );
            final votesRaw = Map<String, dynamic>.from(data['votes'] ?? {});
            final int totalParticipants = participantsMap.length;

            // If not all participants have voted yet, show waiting state
            if (votesRaw.length < totalParticipants) {
              final remaining = totalParticipants - votesRaw.length;
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    Text(
                      'Waiting for $remaining more vote${remaining > 1 ? 's' : ''}...',
                    ),
                  ],
                ),
              );
            }

            // Aggregate vote counts per restaurant
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
            // Check for unanimous
            for (var r in widget.restaurants) {
              if ((voteCounts[r.id] ?? 0) == totalParticipants) {
                winning = r;
                break;
              }
            }
            // Otherwise highest votes
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
              return const Center(child: Text('No results available.'));
            }

            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Winning Restaurant:',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  Text(winning.name, style: const TextStyle(fontSize: 20)),
                  Text('Address: ${winning.address}'),
                  Text(
                    'Distance: ${winning.distance.toStringAsFixed(2)} miles',
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Votes: ${voteCounts[winning.id] ?? 0} of $totalParticipants',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const Spacer(),
                  Center(
                    child: ElevatedButton(
                      onPressed: _returnToHome,
                      child: const Text('Back to Home'),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
