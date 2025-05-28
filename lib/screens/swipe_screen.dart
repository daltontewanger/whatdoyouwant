import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tcard/tcard.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/restaurant.dart';
import '../models/user.dart';
import '../services/room_service.dart';
import 'results_screen.dart';

class SwipeScreen extends StatefulWidget {
  final String roomCode;
  final AppUser currentUser;
  final double radius;
  final int maxOptions;
  final List<Restaurant> restaurants;

  const SwipeScreen({
    super.key,
    required this.roomCode,
    required this.currentUser,
    required this.radius,
    required this.maxOptions,
    required this.restaurants,
  });

  @override
  _SwipeScreenState createState() => _SwipeScreenState();
}

class _SwipeScreenState extends State<SwipeScreen> {
  late List<Restaurant> swipeOptions;
  List<bool> swipeResults = [];
  late TCardController _tCardController;
  Timer? _cardTimer;
  int _currentIndex = 0;
  static const int swipeTimeoutSeconds = 10;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _tCardController = TCardController();
    swipeOptions = widget.restaurants;
    _startCardTimer();
  }

  @override
  void dispose() {
    _cancelCardTimer();
    super.dispose();
  }

  void _startCardTimer() {
    _cancelCardTimer();
    _cardTimer = Timer(
      const Duration(seconds: swipeTimeoutSeconds),
      _simulateLeftSwipe,
    );
  }

  void _cancelCardTimer() {
    if (_cardTimer?.isActive == true) {
      _cardTimer!.cancel();
    }
  }

  void _simulateLeftSwipe() {
    if (_currentIndex < swipeOptions.length) {
      swipeResults.add(false);
      _currentIndex++;
      _tCardController.forward();
      if (_currentIndex < swipeOptions.length) {
        _startCardTimer();
      } else {
        _onSwipingEnd();
      }
    }
  }

  void _handleSwipe(int index, dynamic info) {
    _cancelCardTimer();

    bool liked = false;

    var direction =
        info?.direction ?? info;

    if (direction.toString().contains('Right')) {
      liked = true;
    }

    print('Direction enum: $direction, liked: $liked, at card $index');

    swipeResults.add(liked);
    _currentIndex++;

    if (_currentIndex < swipeOptions.length) {
      _startCardTimer();
    }
  }

  Future<void> _onSwipingEnd() async {
    _cancelCardTimer();
    // Ensure every card has a vote
    while (swipeResults.length < swipeOptions.length) {
      swipeResults.add(false);
    }

    // Build user's votes map
    final Map<String, bool> userVotes = {};
    for (int i = 0; i < swipeOptions.length; i++) {
      userVotes[swipeOptions[i].id] = swipeResults[i];
    }

    // Make sure there is a real authenticated Firebase user
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be signed in to vote.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // Submit votes to Firestore under the authenticated UID
      await RoomService().submitUserVotes(widget.roomCode, user.uid, userVotes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error submitting votes: $e')));
    } finally {
      setState(() => _isSubmitting = false);
    }

    // Navigate to ResultsScreen
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder:
            (_) => ResultsScreen(
              roomCode: widget.roomCode,
              restaurants: swipeOptions,
            ),
      ),
    );
  }

  List<Widget> _buildCards() {
    return swipeOptions.map((restaurant) {
      return Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                restaurant.name,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(restaurant.address),
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
    if (_isSubmitting) {
      return Scaffold(
        appBar: AppBar(title: const Text('Submitting Votes')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (swipeOptions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Swipe Screen')),
        body: const Center(
          child: Text('No restaurants available within the selected radius.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Swipe Restaurants')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: TCard(
          controller: _tCardController,
          cards: _buildCards(),
          onForward: _handleSwipe,
          onEnd: _onSwipingEnd,
        ),
      ),
    );
  }
}
