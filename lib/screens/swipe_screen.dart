import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  late final List<Restaurant> swipeOptions;
  final CardSwiperController _cardSwiperController = CardSwiperController();

  static const int swipeTimeoutSeconds = 15;
  static const Duration _watchdogInterval = Duration(seconds: 10);

  final List<bool> _localVotes = [];
  int _currentIndex = 0;

  bool _navigated = false;
  bool _isLeaving = false;

  StreamSubscription<DocumentSnapshot>? _roomSub;
  Timer? _watchdogTimer;

  String get _uid {
    final u = FirebaseAuth.instance.currentUser;
    return u?.uid ?? widget.currentUser.id;
  }

  @override
  void initState() {
    super.initState();
    swipeOptions = widget.restaurants;

    _roomSub = RoomService().roomStream(widget.roomCode).listen(_onRoomUpdate);

    _watchdogTimer = Timer.periodic(_watchdogInterval, (_) {
      RoomService().timeoutStaleByVote(roomCode: widget.roomCode).catchError((_) {});
    });
  }

  @override
  void dispose() {
    _isLeaving = true;
    _watchdogTimer?.cancel();
    _roomSub?.cancel();
    _cardSwiperController.dispose();
    super.dispose();
  }

  // Helpers for room state
  int _restaurantsLenFromRoom(Map<String, dynamic> data) {
    final restaurantsDoc =
        List<Map<String, dynamic>>.from(data['restaurants'] ?? const []);
    return restaurantsDoc.isNotEmpty ? restaurantsDoc.length : swipeOptions.length;
  }

  // Room stream - navigate when this user is done and close when all are done
  void _onRoomUpdate(DocumentSnapshot snap) {
    if (_isLeaving || !mounted || !snap.exists) return;

    final data = snap.data() as Map<String, dynamic>;
    final status = (data['status'] ?? 'closed') as String;

    final int restaurantsLen = _restaurantsLenFromRoom(data);
    final participants = Map<String, dynamic>.from(data['participants'] ?? {});
    final votes = Map<String, dynamic>.from(data['votes'] ?? {});

    // Checks being done with server
    final Map<String, dynamic> myVotes =
        Map<String, dynamic>.from(votes[_uid] ?? {});
    final bool iAmDone = restaurantsLen > 0 && myVotes.length >= restaurantsLen;
    if (iAmDone && !_navigated) {
      _goToResults();
    }

    // If everyone's done proactively close
    bool allComplete = false;
    if (participants.isNotEmpty && restaurantsLen > 0) {
      allComplete = participants.keys.every((uid) {
        final Map<String, dynamic> uVotes =
            Map<String, dynamic>.from(votes[uid] ?? {});
        return uVotes.length >= restaurantsLen;
      });
    }
    if (status == 'voting' && allComplete) {
      RoomService().closeRoom(widget.roomCode).catchError((_) {});
    }
  }

  void _goToResults() {
    if (_navigated || _isLeaving || !mounted) return;
    _navigated = true;
    _isLeaving = true;
    _watchdogTimer?.cancel();
    _roomSub?.cancel();

    WidgetsBinding.instance.addPostFrameCallback((_) {
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
    });
  }

  // Swiping and incremental write
  void _simulateLeftSwipe() {
    if (_isLeaving || !mounted) return;
    if (_currentIndex >= swipeOptions.length) return;
    try {
      _cardSwiperController.swipe(CardSwiperDirection.left);
    } catch (_) {}
  }

  bool _handleSwipe(
    int previousIndex,
    int? newIndex,
    CardSwiperDirection direction,
  ) {
    if (_isLeaving) return false;
    if (previousIndex < 0 || previousIndex >= swipeOptions.length) return true;

    if (_localVotes.length > previousIndex) return true; // de-dupe

    final bool liked = (direction == CardSwiperDirection.right);
    final String restaurantId = swipeOptions[previousIndex].id;

    _localVotes.add(liked);
    _currentIndex = previousIndex + 1;

    final bool finishedDeck = _currentIndex >= swipeOptions.length;

    RoomService()
        .submitIncrementalVote(
          roomCode: widget.roomCode,
          userId: _uid,
          restaurantId: restaurantId,
          liked: liked,
          currentIndex: previousIndex,
          totalCount: swipeOptions.length,
        )
        .then((_) async {
          if (finishedDeck && !_navigated) {
            _goToResults();
          }
          await RoomService().timeoutStaleByVote(roomCode: widget.roomCode);
        })
        .catchError((e) {
          if (!mounted || _isLeaving) return;
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Vote failed: $e')));
        });

    if (mounted && !_isLeaving) setState(() {});
    return true;
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
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium!
                    .copyWith(color: Colors.black54),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (swipeOptions.isEmpty) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor.withOpacity(0.10),
        body: const Center(
          child: Text('No restaurants available within the selected radius.'),
        ),
      );
    }

    final bool finishedDeck = _currentIndex >= swipeOptions.length;

    return Scaffold(
      backgroundColor: theme.colorScheme.primary.withOpacity(0.10),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            const maxCardWidth = 420.0;
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxCardWidth,
                  minHeight: constraints.maxHeight,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
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
                  child: LayoutBuilder(
                    builder: (context, innerConstraints) {
                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: innerConstraints.maxHeight),
                          child: IntrinsicHeight(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  "Swipe to Choose!",
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.headlineMedium!.copyWith(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 34,
                                    letterSpacing: 1.2,
                                    shadows: const [
                                      Shadow(
                                        color: Colors.black12,
                                        blurRadius: 4,
                                        offset: Offset(1, 2),
                                      ),
                                    ],
                                  ),
                                ),

                                Expanded(
                                  child: Align(
                                    alignment: Alignment.center,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      child: Text(
                                        "Swipe right to vote YES, left to vote NO.\nAuto NO after $swipeTimeoutSeconds seconds.",
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.bodyLarge!.copyWith(
                                          fontSize: 16,
                                          color: Colors.black.withOpacity(0.7),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                                Expanded(
                                  flex: 3,
                                  child: Center(
                                    child: SizedBox(
                                      height: 380,
                                      child: CardSwiper(
                                        controller: _cardSwiperController,
                                        cardsCount: _cardWidgets.length,
                                        cardBuilder: (context, index, h, v) {
                                          if (index >= _cardWidgets.length) return null;
                                          return _cardWidgets[index];
                                        },
                                        isLoop: false,
                                        onSwipe: _handleSwipe,
                                        onEnd: () async {
                                          // Finished locally — navigate now (waiting screen if others not done)
                                          if (!_navigated) _goToResults();
                                          // Also nudge watchdog
                                          await RoomService()
                                              .timeoutStaleByVote(roomCode: widget.roomCode)
                                              .catchError((_) {});
                                        },
                                      ),
                                    ),
                                  ),
                                ),

                                if (!finishedDeck)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 20, bottom: 6),
                                    child: TweenAnimationBuilder<double>(
                                      key: ValueKey(_currentIndex),
                                      duration: const Duration(seconds: swipeTimeoutSeconds),
                                      tween: Tween(begin: 1.0, end: 0.0),
                                      builder: (context, value, child) {
                                        if (_isLeaving) return const SizedBox.shrink();
                                        final secondsLeft = (swipeTimeoutSeconds * value).ceil();
                                        return Column(
                                          children: [
                                            Text(
                                              secondsLeft > 0 ? '$secondsLeft' : '',
                                              style: theme.textTheme.headlineMedium!
                                                  .copyWith(color: Colors.orange, fontSize: 38),
                                            ),
                                            const SizedBox(height: 6),
                                            LinearProgressIndicator(
                                              value: value,
                                              color: Colors.orange,
                                              backgroundColor:
                                                  theme.colorScheme.primary.withOpacity(0.13),
                                              minHeight: 8,
                                              borderRadius: BorderRadius.circular(7),
                                            ),
                                          ],
                                        );
                                      },
                                      onEnd: () {
                                        if (_isLeaving || finishedDeck) return;
                                        WidgetsBinding.instance.addPostFrameCallback((_) {
                                          if (mounted && !_isLeaving && !finishedDeck) {
                                            _simulateLeftSwipe();
                                          }
                                        });
                                      },
                                    ),
                                  ),

                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8, top: 4),
                                  child: Text(
                                    'Option ${(_currentIndex + 1).clamp(1, swipeOptions.length)} of ${swipeOptions.length}',
                                    style: theme.textTheme.bodyMedium!.copyWith(color: Colors.black54),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
