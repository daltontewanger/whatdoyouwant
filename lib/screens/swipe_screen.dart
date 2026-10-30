import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import '../models/restaurant.dart';
import '../models/saved_place.dart';
import '../models/user.dart';
import '../services/result_nudges.dart';
import '../services/room_backend.dart';
import '../services/my_places.dart';
import '../services/search_defaults.dart';
import 'place_marks.dart';
import 'results_screen.dart';

const Color cardSwipeBackground = Color(0xFFE7F8F3);

/// What to tell someone whose vote was not saved. Ballots are written straight
/// to Firestore, so a rejection usually means voting closed for this room.
String voteErrorMessage(Object error) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return 'That vote was not counted. Voting may have ended for this room.';
      case 'unauthenticated':
        return 'This device could not be verified. Restart the app and try again.';
    }
  }
  return 'Your vote could not be saved. Check your connection.';
}

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

  final List<bool> _localVotes = [];
  int _currentIndex = 0;

  bool _navigated = false;
  bool _isLeaving = false;

  StreamSubscription<RoomState>? _roomSub;
  ResultNudges? _nudges;
  late RoomBackend _backend;
  MyPlacesStore? _places;

  @override
  void initState() {
    super.initState();
    swipeOptions = widget.restaurants;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_roomSub != null) return;
    _backend = RoomBackendScope.of(context).backend;
    _roomSub = _backend
        .watch(widget.roomCode)
        .listen(_onRoomUpdate, onError: (_) {});

    _nudges = ResultNudges(() => _backend.nudge(widget.roomCode));
    _places =
        RoomBackendScope.of(context).myPlaces?..addListener(_placesChanged);
    // Favorites in this deck get their details refreshed.
    _places?.seen(swipeOptions).catchError((_) {});
  }

  void _placesChanged() {
    if (mounted) setState(() {});
  }

  /// Never counts as No and Favorite as Yes; both also save the place.
  void _mark({required bool never}) {
    if (_currentIndex >= swipeOptions.length) return;
    markPlace(context, swipeOptions[_currentIndex], never: never);
    _swipe(never ? CardSwiperDirection.left : CardSwiperDirection.right);
  }

  @override
  void dispose() {
    _places?.removeListener(_placesChanged);
    _isLeaving = true;
    _nudges?.stop();
    _roomSub?.cancel();
    _cardSwiperController.dispose();
    super.dispose();
  }

  // Room stream: move on to results once this person is done or time is up.
  void _onRoomUpdate(RoomState room) {
    if (_isLeaving || !mounted) return;

    final int restaurantsLen =
        room.restaurants.isNotEmpty
            ? room.restaurants.length
            : swipeOptions.length;
    final bool iAmDone =
        restaurantsLen > 0 && room.myVoteCount >= restaurantsLen;
    // Someone has to close the room when time runs out, even if nobody has
    // reached the results screen yet; once it closes, leftover cards are moot.
    _nudges?.votingEndsAt(room.votingEndsAt);
    if ((iAmDone || room.status == 'closed') && !_navigated) {
      _goToResults();
    }
  }

  void _goToResults() {
    if (_navigated || _isLeaving || !mounted) return;
    _navigated = true;
    _isLeaving = true;
    _nudges?.stop();
    _roomSub?.cancel();

    WidgetsBinding.instance.addPostFrameCallback((_) {
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

  // Swiping and incremental write. The Yes and No buttons and the timeout
  // swipe the card for the person, so every vote takes the same path.
  void _swipe(CardSwiperDirection direction) {
    if (_isLeaving || !mounted) return;
    if (_currentIndex >= swipeOptions.length) return;
    try {
      _cardSwiperController.swipe(direction);
    } catch (_) {}
  }

  void _simulateLeftSwipe() => _swipe(CardSwiperDirection.left);

  bool _handleSwipe(
    int previousIndex,
    int? newIndex,
    CardSwiperDirection direction,
  ) {
    if (_isLeaving) return false;
    if (previousIndex < 0 || previousIndex >= swipeOptions.length) return true;

    if (_localVotes.length > previousIndex) return true; // de-dupe

    final bool liked = (direction == CardSwiperDirection.right);
    final Restaurant restaurant = swipeOptions[previousIndex];

    _localVotes.add(liked);
    _currentIndex = previousIndex + 1;

    final bool finishedDeck = _currentIndex >= swipeOptions.length;

    _backend
        .vote(
          widget.roomCode,
          restaurant,
          liked: liked,
          index: previousIndex,
          total: swipeOptions.length,
        )
        .then((_) async {
          if (finishedDeck && !_navigated) {
            _goToResults();
          }
          // The server only needs asking once this person's last ballot is
          // stored; earlier ones cannot complete the room.
          if (finishedDeck) {
            // A failed nudge is not a failed vote; the next one retries.
            await _backend.nudge(widget.roomCode).catchError((_) {});
          }
        })
        .catchError((e) {
          if (!mounted || _isLeaving) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(voteErrorMessage(e))));
        });

    if (mounted && !_isLeaving) setState(() {});
    return true;
  }

  List<Widget> get _cardWidgets {
    return swipeOptions.map((restaurant) {
      final favorite = _places?.isFavorite(restaurant.id) ?? false;
      return Card(
        color: cardSwipeBackground,
        shape: Theme.of(context).cardTheme.shape,
        elevation: Theme.of(context).cardTheme.elevation ?? 6,
        margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Stack(
          // Expanded so the text stays centred in the card around the badge.
          fit: StackFit.expand,
          children: [
            if (favorite)
              const Positioned(top: 12, right: 12, child: FavoriteBadge()),
            Padding(
              padding: const EdgeInsets.all(28.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    restaurant.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 14),
                  // Spots from the host's own list were never looked up, so they
                  // have the host's note in place of a distance.
                  if (restaurant.userEntered)
                    Text(
                      restaurant.note ?? '',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  else
                    Text(
                      'Distance: ${distanceText(restaurant.distance, RoomBackendScope.distanceUnitOf(context))}',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium!.copyWith(color: Colors.black54),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (swipeOptions.isEmpty) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor.withValues(alpha: 0.10),
        body: const Center(
          child: Text('No restaurants available within the selected radius.'),
        ),
      );
    }

    final bool finishedDeck = _currentIndex >= swipeOptions.length;
    // Typed spots from the host's own list are already the host's; they
    // cannot be favorites or never places.
    final bool canMark =
        _places != null &&
        !finishedDeck &&
        SavedPlace.canSave(swipeOptions[_currentIndex]);

    return Scaffold(
      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.10),
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
                  padding: const EdgeInsets.symmetric(
                    vertical: 30,
                    horizontal: 20,
                  ),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.10,
                        ),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: LayoutBuilder(
                    builder: (context, innerConstraints) {
                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: innerConstraints.maxHeight,
                          ),
                          child: IntrinsicHeight(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  "Swipe to Choose!",
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.headlineMedium!
                                      .copyWith(
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
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 6,
                                      ),
                                      child: Text(
                                        "Swipe right or tap Yes to vote YES; swipe left or tap No to vote NO.\nAuto NO after $swipeTimeoutSeconds seconds.",
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.bodyLarge!
                                            .copyWith(
                                              fontSize: 16,
                                              color: Colors.black.withValues(
                                                alpha: 0.7,
                                              ),
                                            ),
                                      ),
                                    ),
                                  ),
                                ),

                                Expanded(
                                  flex: 3,
                                  child: Center(
                                    // The swiper sizes cards from these constraints; with
                                    // a loose width every card shrinks to its own text
                                    // and sits at the left edge.
                                    child: SizedBox(
                                      width: double.infinity,
                                      height: 380,
                                      child: CardSwiper(
                                        controller: _cardSwiperController,
                                        cardsCount: _cardWidgets.length,
                                        // The swiper shows two stacked cards by
                                        // default and rejects a one-card deck.
                                        numberOfCardsDisplayed:
                                            _cardWidgets.length < 2 ? 1 : 2,
                                        cardBuilder: (context, index, h, v) {
                                          if (index >= _cardWidgets.length) {
                                            return null;
                                          }
                                          return _cardWidgets[index];
                                        },
                                        isLoop: false,
                                        onSwipe: _handleSwipe,
                                        onEnd: () async {
                                          // Finished locally — navigate now (waiting screen if others not done)
                                          if (!_navigated) _goToResults();
                                          // Also nudge watchdog
                                          await _backend
                                              .nudge(widget.roomCode)
                                              .catchError((_) {});
                                        },
                                      ),
                                    ),
                                  ),
                                ),

                                if (!finishedDeck)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 20,
                                      bottom: 6,
                                    ),
                                    // Small thumbs either side of the countdown are
                                    // a tap alternative to swiping, for anyone who
                                    // cannot or would rather not drag a card.
                                    child: Row(
                                      children: [
                                        if (!_isLeaving)
                                          _ListButton(
                                            visible: canMark,
                                            label: 'Never',
                                            tooltip: 'Never what I want',
                                            icon: const Icon(
                                              Icons.block,
                                              color: Color(0xFF555451),
                                            ),
                                            color: const Color(0xFFF1EFE8),
                                            onTap: () => _mark(never: true),
                                          ),
                                        if (!_isLeaving)
                                          _VoteButton(
                                            image: 'assets/images/vote-no.png',
                                            label: 'No',
                                            onTap:
                                                () => _swipe(
                                                  CardSwiperDirection.left,
                                                ),
                                          ),
                                        Expanded(
                                          child: TweenAnimationBuilder<double>(
                                            key: ValueKey(_currentIndex),
                                            duration: const Duration(
                                              seconds: swipeTimeoutSeconds,
                                            ),
                                            tween: Tween(begin: 1.0, end: 0.0),
                                            builder: (context, value, child) {
                                              if (_isLeaving) {
                                                return const SizedBox.shrink();
                                              }
                                              final secondsLeft =
                                                  (swipeTimeoutSeconds * value)
                                                      .ceil();
                                              return Column(
                                                children: [
                                                  Text(
                                                    secondsLeft > 0
                                                        ? '$secondsLeft'
                                                        : '',
                                                    style: theme
                                                        .textTheme
                                                        .headlineMedium!
                                                        .copyWith(
                                                          color: Colors.orange,
                                                          fontSize: 38,
                                                        ),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  LinearProgressIndicator(
                                                    value: value,
                                                    color: Colors.orange,
                                                    backgroundColor: theme
                                                        .colorScheme
                                                        .primary
                                                        .withValues(
                                                          alpha: 0.13,
                                                        ),
                                                    minHeight: 8,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          7,
                                                        ),
                                                  ),
                                                ],
                                              );
                                            },
                                            onEnd: () {
                                              if (_isLeaving || finishedDeck) {
                                                return;
                                              }
                                              WidgetsBinding.instance
                                                  .addPostFrameCallback((_) {
                                                    if (mounted &&
                                                        !_isLeaving &&
                                                        !finishedDeck) {
                                                      _simulateLeftSwipe();
                                                    }
                                                  });
                                            },
                                          ),
                                        ),
                                        if (!_isLeaving)
                                          _VoteButton(
                                            image: 'assets/images/vote-yes.png',
                                            label: 'Yes',
                                            onTap:
                                                () => _swipe(
                                                  CardSwiperDirection.right,
                                                ),
                                          ),
                                        if (!_isLeaving)
                                          _ListButton(
                                            visible: canMark,
                                            label: 'Favorite',
                                            tooltip: 'Save as favorite',
                                            icon: const FavoriteIcon(),
                                            color: const Color(0xFFFBEAF0),
                                            onTap: () => _mark(never: false),
                                          ),
                                      ],
                                    ),
                                  ),

                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: 8,
                                    top: 4,
                                  ),
                                  child: Text(
                                    'Option ${(_currentIndex + 1).clamp(1, swipeOptions.length)} of ${swipeOptions.length}',
                                    style: theme.textTheme.bodyMedium!.copyWith(
                                      color: Colors.black54,
                                    ),
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

/// A small thumbs-up or thumbs-down bubble. Its name is in the tooltip and
/// what screen readers announce.
class _VoteButton extends StatelessWidget {
  const _VoteButton({
    required this.image,
    required this.label,
    required this.onTap,
  });

  final String image;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Vote $label',
    excludeSemantics: true,
    child: Tooltip(
      message: 'Vote $label',
      child: InkResponse(
        onTap: onTap,
        radius: 30,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Image.asset(image, width: 48, height: 48),
        ),
      ),
    ),
  );
}

/// Never or Favorite: a vote that also saves the place to a list. Buttons
/// only, so a list is never changed by an accidental swipe. Keeps its space
/// when hidden, so the vote buttons do not move between cards.
class _ListButton extends StatelessWidget {
  const _ListButton({
    required this.visible,
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final bool visible;
  final String label;
  final String tooltip;
  final Widget icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Visibility(
    visible: visible,
    maintainSize: true,
    maintainAnimation: true,
    maintainState: true,
    child: Semantics(
      button: true,
      label: tooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: InkResponse(
          onTap: visible ? onTap : null,
          radius: 26,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: icon,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
