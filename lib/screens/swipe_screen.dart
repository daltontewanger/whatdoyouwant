import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/restaurant.dart';
import '../models/user.dart';
import '../services/room_service.dart';
import 'results_screen.dart';

const Color cardSwipeBackground = Color(0xFFE7F8F3);

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
  SwipeScreenState createState() => SwipeScreenState();
}

class SwipeScreenState extends State<SwipeScreen> {
  late List<Restaurant> swipeOptions;
  List<bool> swipeResults = [];
  final CardSwiperController _cardSwiperController = CardSwiperController();
  static const int swipeTimeoutSeconds = 15;
  int _currentIndex = 0;
  bool _isSubmitting = false;
  bool _isAutoSwiping = false;

  @override
  void initState() {
    super.initState();
    swipeOptions = widget.restaurants;
  }

  @override
  void dispose() {
    _cardSwiperController.dispose();
    super.dispose();
  }

  void _simulateLeftSwipe() {
    if (!mounted) return;
    if (_currentIndex < swipeOptions.length) {
      _isAutoSwiping = true;
      _cardSwiperController.swipe(CardSwiperDirection.left);
    }
  }

  bool _handleSwipe(
    int previousIndex,
    int? newIndex,
    CardSwiperDirection direction,
  ) {
    // Prevent double-recording votes (manual and auto)
    if (swipeResults.length > previousIndex) return true;

    bool liked = false;
    if (_isAutoSwiping) {
      liked = false;
      _isAutoSwiping = false;
    } else if (direction == CardSwiperDirection.right) {
      liked = true;
    }

    swipeResults.add(liked);
    _currentIndex++;

    if (_currentIndex < swipeOptions.length) {
      setState(
        () {},
      ); 
    } else {
      _onSwipingEnd();
    }
    return true;
  }

  Future<void> _onSwipingEnd() async {
    while (swipeResults.length < swipeOptions.length) {
      swipeResults.add(false);
    }
    final Map<String, bool> userVotes = {};
    for (int i = 0; i < swipeOptions.length; i++) {
      userVotes[swipeOptions[i].id] = swipeResults[i];
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be signed in to vote.')),
      );
      return;
    }
    if (mounted) {
      setState(() => _isSubmitting = true);
    }
    try {
      await RoomService().submitUserVotes(widget.roomCode, user.uid, userVotes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error submitting votes: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }

    if (!mounted) return;
    Future.microtask(() {
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
    });
  }

  List<Widget> get _cardWidgets {
    return swipeOptions.map((restaurant) {
      return Card(
        color: cardSwipeBackground,
        shape: Theme.of(context).cardTheme.shape,
        elevation: Theme.of(context).cardTheme.elevation ?? 6,
        margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                restaurant.name,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium!.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 26,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                restaurant.address,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 14),
              Text(
                'Distance: ${restaurant.distance.toStringAsFixed(2)} miles',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium!.copyWith(color: Colors.black54),
              ),
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
        backgroundColor: Theme.of(
          context,
        ).scaffoldBackgroundColor.withOpacity(0.10),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (swipeOptions.isEmpty) {
      return Scaffold(
        backgroundColor: Theme.of(
          context,
        ).scaffoldBackgroundColor.withOpacity(0.10),
        body: const Center(
          child: Text('No restaurants available within the selected radius.'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(
        context,
      ).scaffoldBackgroundColor.withOpacity(0.10),
      body: PopScope(
        canPop: true,
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.symmetric(vertical: 38, horizontal: 18),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.10),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Swipe to Choose!",
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium!.copyWith(
                      fontWeight: FontWeight.w900,
                      fontSize: 34,
                      letterSpacing: 1.2,
                      shadows: [
                        const Shadow(
                          color: Colors.black12,
                          blurRadius: 4,
                          offset: Offset(1, 2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Swipe right to vote YES, left to vote NO.\nAuto NO after $swipeTimeoutSeconds seconds.",
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                      fontSize: 16,
                      color: Colors.black.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 370,
                    child: CardSwiper(
                      controller: _cardSwiperController,
                      cardsCount: _cardWidgets.length,
                      cardBuilder: (
                        context,
                        index,
                        horizontalThresholdPercentage,
                        verticalThresholdPercentage,
                      ) {
                        if (index >= _cardWidgets.length) return null;
                        return _cardWidgets[index];
                      },
                      isLoop: false,
                      onSwipe: _handleSwipe,
                      onEnd: _onSwipingEnd,
                    ),
                  ),
                  const SizedBox(height: 22),
                  TweenAnimationBuilder<double>(
                    key: ValueKey(_currentIndex),
                    duration: const Duration(seconds: swipeTimeoutSeconds),
                    tween: Tween(begin: 1.0, end: 0.0),
                    builder: (context, value, child) {
                      int secondsLeft = (swipeTimeoutSeconds * value).ceil();
                      return Column(
                        children: [
                          Text(
                            secondsLeft > 0 ? '$secondsLeft' : '',
                            style: Theme.of(context).textTheme.headlineMedium!
                                .copyWith(color: Colors.orange, fontSize: 38),
                          ),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            value: value,
                            color: Colors.orange,
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(0.13),
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(7),
                          ),
                        ],
                      );
                    },
                    onEnd: () {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _simulateLeftSwipe();
                      });
                    },
                  ),

                  const SizedBox(height: 12),
                  Text(
                    'Option ${_currentIndex + 1} of ${swipeOptions.length}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium!.copyWith(color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
