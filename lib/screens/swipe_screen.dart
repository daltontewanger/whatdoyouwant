import 'package:flutter/material.dart';
import 'package:tcard/tcard.dart';
import '../models/restaurant.dart';
import 'results_screen.dart';

/// For the swipe direction, we assume the callback returns an enum or value that
/// can be compared. Adjust accordingly if needed.
enum SwipeDirection { left, right }

class SwipeScreen extends StatefulWidget {
  final double radius;
  final int maxOptions;
  final List<Restaurant> restaurants;

  const SwipeScreen({
    super.key,
    required this.radius,
    required this.maxOptions,
    required this.restaurants,
  });

  @override
  // ignore: library_private_types_in_public_api
  _SwipeScreenState createState() => _SwipeScreenState();
}

class _SwipeScreenState extends State<SwipeScreen> {
  late List<Restaurant> swipeOptions;
  List<bool> swipeResults = []; // true = like, false = dislike
  late TCardController _tCardController;

  @override
  void initState() {
    super.initState();
    _tCardController = TCardController();
    // Use the list passed in from RoomScreen.
    swipeOptions = widget.restaurants;
  }

  /// Called when a card is swiped.
  /// [index] is the index of the card swiped.
  /// [info] contains the swipe details.
  void _handleSwipe(int index, dynamic info) {
    // For demonstration, we assume info is an instance of SwipeDirection.
    // If info is not directly comparable, adjust as needed.
    bool liked = (info == SwipeDirection.right);
    swipeResults.add(liked);
  }

  /// Called when all cards have been swiped.
  void _onSwipingEnd() {
    // For now, we simulate vote aggregation.
    const int totalParticipants = 5; // Replace with real data in a multi-user scenario.
    Map<String, int> aggregatedVotes = {};
    for (var restaurant in swipeOptions) {
      int index = swipeOptions.indexOf(restaurant);
      int userVote = (index < swipeResults.length && swipeResults[index]) ? 1 : 0;
      int dummyVotes = restaurant.id.hashCode % totalParticipants;
      aggregatedVotes[restaurant.id] = userVote + dummyVotes;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ResultsScreen(
          restaurants: swipeOptions,
          voteCounts: aggregatedVotes,
          totalParticipants: totalParticipants,
        ),
      ),
    );
  }

  /// Builds card widgets for each restaurant.
  List<Widget> _buildCards() {
    return swipeOptions.map((restaurant) {
      return Card(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                restaurant.name,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(restaurant.address),
              const SizedBox(height: 10),
              const SizedBox(height: 10),
              Text('Distance: ${restaurant.distance.toStringAsFixed(2)} miles'),
            ],
          ),
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (swipeOptions.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Swipe Screen'),
        ),
        body: const Center(
          child: Text('No restaurants available within the selected radius.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Swipe Restaurants'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: TCard(
          controller: _tCardController,
          cards: _buildCards(),
          onForward: (index, info) {
            _handleSwipe(index, info);
          },
          onEnd: _onSwipingEnd,
        ),
      ),
    );
  }
}
