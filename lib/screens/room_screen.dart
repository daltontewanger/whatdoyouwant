import 'package:flutter/material.dart';
import '../services/location_services.dart';
import 'swipe_screen.dart';
import '../models/restaurant.dart';

class RoomScreen extends StatefulWidget {
  final bool isCreator;
  final String? roomCode;

  const RoomScreen({super.key, this.isCreator = true, this.roomCode});

  @override
  // ignore: library_private_types_in_public_api
  _RoomScreenState createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  // Default settings for search radius (in miles) and maximum options.
  double _selectedRadius = 5.0;
  int _selectedMaxOptions = 5;

  // Predefined options.
  final List<int> radiusOptions = [1, 3, 5, 10, 15, 25];
  final List<int> optionCounts = [5, 10, 15, 25];

  bool _isLoading = false;

  /// Called when the user taps "Start Swiping".
  /// This function calls the LocationService to fetch real restaurant data,
  /// filters/randomizes it, and then navigates to the SwipeScreen.
  Future<void> _startSwiping() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Query the HERE API via LocationService to fetch nearby restaurants.
      List<Restaurant> fetchedRestaurants = await LocationService.fetchNearbyRestaurants(
        radiusMiles: _selectedRadius,
      );
      // Optionally filter and randomize the list.
      List<Restaurant> finalRestaurants = LocationService.filterAndRandomizeRestaurants(
        allRestaurants: fetchedRestaurants,
        radiusMiles: _selectedRadius,
        maxOptions: _selectedMaxOptions,
      );

      if (!mounted) return; // Ensure widget is still in the tree

      setState(() {
        _isLoading = false;
      });

      // Navigate to the SwipeScreen with the fetched restaurant list.
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SwipeScreen(
            radius: _selectedRadius,
            maxOptions: _selectedMaxOptions,
            restaurants: finalRestaurants,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching restaurants: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isCreator ? 'Create Room' : 'Join Room'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (widget.isCreator)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Room Code:',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.roomCode ?? 'N/A',
                    style: const TextStyle(fontSize: 24, color: Colors.orange),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: const Text(
                'Select Search Radius:',
                style: TextStyle(fontSize: 18),
              ),
            ),
            DropdownButton<double>(
              value: _selectedRadius,
              items: radiusOptions.map((radius) {
                return DropdownMenuItem<double>(
                  value: radius.toDouble(),
                  child: Text('$radius miles'),
                );
              }).toList(),
              onChanged: (newValue) {
                setState(() {
                  _selectedRadius = newValue!;
                });
              },
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: const Text(
                'Select Number of Options:',
                style: TextStyle(fontSize: 18),
              ),
            ),
            DropdownButton<int>(
              value: _selectedMaxOptions,
              items: optionCounts.map((count) {
                return DropdownMenuItem<int>(
                  value: count,
                  child: Text('$count options'),
                );
              }).toList(),
              onChanged: (newValue) {
                setState(() {
                  _selectedMaxOptions = newValue!;
                });
              },
            ),
            const Spacer(),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _startSwiping,
                    child: const Text('Start Swiping'),
                  ),
          ],
        ),
      ),
    );
  }
}
