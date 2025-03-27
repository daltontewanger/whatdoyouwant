import 'package:flutter/material.dart';
import 'package:tcard/tcard.dart';
import '../models/restaurant.dart';
import '../services/location_services.dart';
import 'results_screen.dart';

class SwipeScreen extends StatefulWidget {
  final double radius;
  final int maxOptions;

  const SwipeScreen({
    Key? key,
    required this.radius,
    required this.maxOptions,
  }) : super(key: key);

  @override
  _SwipeScreenState createState() => _SwipeScreenState();
}

class _SwipeScreenState extends State<SwipeScreen> {
  List<Restaurant> allRestaurants = [];
  List<Restaurant> swipeOptions = [];
  List<bool> swipeResults = []; // true = like, false = dislike
  late TCardController _tCardController;

  @override
  void initState() {
    super.initState();
    _tCardController = TCardController();

    // Generate a list of dummy restaurants.
    allRestaurants = _generateDummyRestaurants();

    // Filter and randomize the list based on the selected radius and max options.
    swipeOptions = LocationService.filterAndRandomizeRestaurants(
      allRestaurants: allRestaurants,
      radiusMiles: widget.radius,
      maxOptions: widget.maxOptions,
    );
  }

  List<Restaurant> _generateDummyRestaurants() {
    List<Restaurant> dummyList = [];
    for (int i = 1; i <= 16; i++) {
      dummyList.add(
        Restaurant(
          id: i.toString(),
          name: 'Restaurant $i',
          address: 'Address $i',
          rating: 3.0 + (i % 5) * 0.5, // Ratings between 3.0 and 5.0.
          distance: (i % 10 + 1).toDouble(), // Distance between 1 and 10 miles.
        ),
      );
    }
    return dummyList;
  }

  /// Called when a card is swiped.
  /// [index] is the card index; [info] contains swipe details.
  void _handleSwipe(int index, dynamic info) {
    // info is already an instance of SwipDirection.
    // We treat a right swipe as a 'like'.
    bool liked = (info == SwipDirection.Right);
    swipeResults.add(liked);
  }

  /// Called when all cards have been swiped.
  void _onSwipingEnd() {
    // Simulate aggregating votes. In a real app, you'd combine votes from multiple users.
    const int totalParticipants = 5;
    Map<String, int> aggregatedVotes = {};

    // Assume the order of swipeResults corresponds to swipeOptions.
    for (var restaurant in swipeOptions) {
      int index = swipeOptions.indexOf(restaurant);
      int userVote = (index < swipeResults.length && swipeResults[index]) ? 1 : 0;
      // Add some dummy votes for demonstration.
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

  /// Build card widgets for each restaurant.
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
              Text('Rating: ${restaurant.rating.toStringAsFixed(1)}'),
              const SizedBox(height: 10),
              Text('Distance: ${restaurant.distance} miles'),
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
