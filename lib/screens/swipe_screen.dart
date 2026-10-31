import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import '../models/restaurant.dart';
import '../models/saved_place.dart';
import '../models/user.dart';
import '../services/result_nudges.dart';
import '../services/room_backend.dart';
import '../services/accessibility.dart';
import '../services/my_places.dart';
import '../services/search_defaults.dart';
import 'bubble_icons.dart';
import 'place_marks.dart';
import 'results_screen.dart';
import '../themes/main_theme.dart';

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
  /// Only the card on top can be marked.
  void _mark(int index, {required bool never}) {
    if (index != _currentIndex || _currentIndex >= swipeOptions.length) return;
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

  // Set while the timer swipes a card away, so that No is marked as the
  // app's rather than the person's.
  bool _timedOut = false;

  void _simulateLeftSwipe() {
    _timedOut = true;
    _swipe(CardSwiperDirection.left);
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
    final bool auto = _timedOut && !liked;
    _timedOut = false;
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
          auto: auto,
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

  // Every card has the same height, taller with bigger text so the name
  // and address still fit; the page scrolls if it gets too tall.
  static double _cardHeight(BuildContext context) {
    final growth = MediaQuery.textScalerOf(context).scale(10) / 10 - 1;
    return 380 + 150 * growth.clamp(0.0, 2.0);
  }

  List<Widget> get _cardWidgets {
    return swipeOptions.indexed.map((entry) {
      final (index, restaurant) = entry;
      final favorite = _places?.isFavorite(restaurant.id) ?? false;
      final never = _places?.isNever(restaurant.id) ?? false;
      // Typed spots from the host's own list are already the host's, and a
      // place already on a list shows that instead. Only the card on top
      // offers them; the one beneath peeks out below it.
      final offersLists =
          _places != null &&
          SavedPlace.canSave(restaurant) &&
          !favorite &&
          !never;
      final canMark = offersLists && index == _currentIndex;
      return Card(
        color: cardSwipeBackground,
        shape: Theme.of(context).cardTheme.shape,
        elevation: Theme.of(context).cardTheme.elevation ?? 6,
        margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Stack(
          // Expanded so the text stays centred in the card around the badge.
          fit: StackFit.expand,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(28, 28, 28, offersLists ? 56 : 28),
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
            if (favorite || never)
              Positioned(top: 8, right: 8, child: ListBadge(never: never)),
            if (canMark) ...[
              Positioned(
                left: 10,
                bottom: 10,
                child: _CardAction(
                  label: 'Never',
                  tooltip: 'Never what I want: vote no and save it',
                  icon: const NeverIcon(),
                  color: neverColor,
                  onTap: () => _mark(index, never: true),
                ),
              ),
              Positioned(
                right: 10,
                bottom: 10,
                child: _CardAction(
                  label: 'Favorite',
                  tooltip: 'I know what I want: vote yes and save it',
                  icon: const FavoriteIcon(),
                  iconAfter: true,
                  color: favoriteColor,
                  onTap: () => _mark(index, never: false),
                ),
              ),
            ],
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
        backgroundColor: screenBackground,
        body: const Center(
          child: Text('No restaurants available within the selected radius.'),
        ),
      );
    }

    final bool finishedDeck = _currentIndex >= swipeOptions.length;
    // No countdown for anyone who votes without a timer.
    final bool untimed = votesWithoutTimer(context);

    return _withArrowKeys(
      Scaffold(
        backgroundColor: screenBackground,
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
                                    'Swipe to Choose',
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

                                  // Only as tall as its text: a stretchy
                                  // block here grows with the text and pushes
                                  // the vote buttons off short screens.
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      8,
                                      10,
                                      8,
                                      4,
                                    ),
                                    child: Text(
                                      'Swipe right, tap the thumbs up or Favorite for a place you want'
                                      ' · Swipe left, tap the thumbs down or Never for a place you '
                                      "don't want\n"
                                      '${untimed ? "No timer for you, so take your time. If you don't vote for 3 minutes, the rest count as places you don't want" : "After $swipeTimeoutSeconds seconds it will auto vote that you don't want this place"}',
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.bodyMedium!
                                          .copyWith(
                                            fontSize: 14,
                                            color: Colors.black.withValues(
                                              alpha: 0.7,
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
                                        height: _cardHeight(context),
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
                                            _VoteButton(
                                              glyph: BubbleGlyph.no,
                                              label: 'No',
                                              onTap:
                                                  () => _swipe(
                                                    CardSwiperDirection.left,
                                                  ),
                                            ),
                                          Expanded(
                                            child:
                                                untimed
                                                    ? Text(
                                                      'No timer',
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: theme
                                                          .textTheme
                                                          .titleMedium!
                                                          .copyWith(
                                                            color:
                                                                Colors.black54,
                                                          ),
                                                    )
                                                    : TweenAnimationBuilder<
                                                      double
                                                    >(
                                                      key: ValueKey(
                                                        _currentIndex,
                                                      ),
                                                      duration: const Duration(
                                                        seconds:
                                                            swipeTimeoutSeconds,
                                                      ),
                                                      tween: Tween(
                                                        begin: 1.0,
                                                        end: 0.0,
                                                      ),
                                                      builder: (
                                                        context,
                                                        value,
                                                        child,
                                                      ) {
                                                        if (_isLeaving) {
                                                          return const SizedBox.shrink();
                                                        }
                                                        final secondsLeft =
                                                            (swipeTimeoutSeconds *
                                                                    value)
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
                                                                    color:
                                                                        Colors
                                                                            .orange,
                                                                    fontSize:
                                                                        38,
                                                                  ),
                                                            ),
                                                            const SizedBox(
                                                              height: 6,
                                                            ),
                                                            LinearProgressIndicator(
                                                              value: value,
                                                              color:
                                                                  Colors.orange,
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
                                                        if (_isLeaving ||
                                                            finishedDeck) {
                                                          return;
                                                        }
                                                        WidgetsBinding.instance
                                                            .addPostFrameCallback((
                                                              _,
                                                            ) {
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
                                              glyph: BubbleGlyph.yes,
                                              label: 'Yes',
                                              onTap:
                                                  () => _swipe(
                                                    CardSwiperDirection.right,
                                                  ),
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
                                      style: theme.textTheme.bodyMedium!
                                          .copyWith(color: Colors.black54),
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
      ),
    );
  }

  // Arrow keys vote too, for anyone using a keyboard.
  Widget _withArrowKeys(Widget child) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.arrowLeft):
          () => _swipe(CardSwiperDirection.left),
      const SingleActivator(LogicalKeyboardKey.arrowRight):
          () => _swipe(CardSwiperDirection.right),
    },
    child: Focus(autofocus: true, child: child),
  );
}

/// The "meh" or "yum" bubble either side of the countdown. Its tail points
/// at the timer. Its name is in the tooltip and what screen readers announce.
class _VoteButton extends StatelessWidget {
  const _VoteButton({
    required this.glyph,
    required this.label,
    required this.onTap,
  });

  final BubbleGlyph glyph;
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
        radius: 32,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: BubbleIcon(
            glyph,
            size: 56,
            tailRight: glyph == BubbleGlyph.no,
          ),
        ),
      ),
    ),
  );
}

/// Never or Favorite on the card: a vote that also saves the place to a
/// list. Buttons only, so a list is never changed by a stray swipe.
class _CardAction extends StatelessWidget {
  const _CardAction({
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
    this.iconAfter = false,
  });

  final String label;
  final String tooltip;
  final Widget icon;
  final Color color;
  final VoidCallback onTap;
  final bool iconAfter;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 14),
    );
    return Semantics(
      button: true,
      label: tooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!iconAfter) ...[icon, const SizedBox(width: 6)],
                text,
                if (iconAfter) ...[const SizedBox(width: 6), icon],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
