import 'package:flutter/material.dart';
import '../models/restaurant.dart';

class ResultsScreen extends StatelessWidget {
  final List<Restaurant> restaurants;
  // A map of restaurant ID to number of likes it received.
  final Map<String, int> voteCounts;
  final int totalParticipants;

  const ResultsScreen({
    super.key,
    required this.restaurants,
    required this.voteCounts,
    required this.totalParticipants,
  });

  @override
  Widget build(BuildContext context) {
    // Determine the winning restaurant.
    Restaurant? winningRestaurant;
    
    // First check for unanimous approval.
    for (Restaurant restaurant in restaurants) {
      if (voteCounts[restaurant.id] == totalParticipants) {
        winningRestaurant = restaurant;
        break;
      }
    }

    // If no restaurant was unanimously liked, pick the one with the highest votes.
    if (winningRestaurant == null) {
      int maxVotes = -1;
      for (Restaurant restaurant in restaurants) {
        final int votes = voteCounts[restaurant.id] ?? 0;
        if (votes > maxVotes) {
          maxVotes = votes;
          winningRestaurant = restaurant;
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Results'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: winningRestaurant != null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Winning Restaurant:',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    winningRestaurant.name,
                    style: const TextStyle(fontSize: 20),
                  ),
                  Text('Address: ${winningRestaurant.address}'),
                  Text('Distance: ${winningRestaurant.distance} miles'),
                  const SizedBox(height: 20),
                  Text(
                    'Votes: ${voteCounts[winningRestaurant.id] ?? 0} out of $totalParticipants',
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              )
            : const Center(child: Text('No results available.')),
      ),
    );
  }
}
