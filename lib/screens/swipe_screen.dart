import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tcard/tcard.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/restaurant.dart';
import '../models/user.dart';
import '../services/room_service.dart';
import 'results_screen.dart';

enum SwipeDirection { left, right }

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
    _cardTimer = Timer(const Duration(seconds: swipeTimeoutSeconds), _simulateLeftSwipe);
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
    bool liked = (info == SwipeDirection.right);
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

    // Determine the authenticated user ID
    final String authUid = FirebaseAuth.instance.currentUser?.uid ?? widget.currentUser.id;

    // Submit votes to Firestore under the authenticated UID
    await RoomService().submitUserVotes(
      widget.roomCode,
      authUid,
      userVotes,
    );

    // Navigate to ResultsScreen
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ResultsScreen(
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
          onForward: (index, info) => _handleSwipe(index, info),
          onEnd: _onSwipingEnd,
        ),
      ),
    );
  }
}