import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import '../models/restaurant.dart';
import '../models/saved_place.dart';
import '../services/place_links.dart';
import '../services/result_nudges.dart';
import '../services/room_backend.dart';
import 'place_card.dart';
import 'place_marks.dart';

/// The banner over a room's result, from how many voters liked the winner.
String resultBanner({required int likes, required int voters}) {
  if (likes <= 0 || voters <= 0) return 'Oops, no one wanted anything';
  if (likes >= voters) return 'Everyone wanted it';
  if (likes * 2 >= voters) return 'Well, most of you wanted it';
  return 'Some of you wanted it';
}

class ResultsScreen extends StatefulWidget {
  final String roomCode;
  final List<Restaurant> restaurants;

  /// Picks the random backup and decides on the tease; fixed in tests.
  final Random? random;

  const ResultsScreen({
    super.key,
    required this.roomCode,
    required this.restaurants,
    this.random,
  });

  @override
  ResultsScreenState createState() => ResultsScreenState();
}

class ResultsScreenState extends State<ResultsScreen> {
  Stream<RoomState>? _roomStream;
  late RoomBackend _backend;
  ResultNudges? _nudges;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_roomStream != null) return;
    _backend = RoomBackendScope.of(context).backend;
    _roomStream = _backend.watch(widget.roomCode);

    _nudges = ResultNudges(() => _backend.nudge(widget.roomCode))..start();
  }

  @override
  void dispose() {
    _nudges?.stop();
    super.dispose();
  }

  // Back to the app's own first screen, which keeps its bottom bar and
  // notices that the room is over.
  void _returnToHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      // A back gesture or button goes home too. When Back to Home pops this
      // screen itself, didPop is true and there is nothing left to do.
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _returnToHome();
      },
      child: Scaffold(
        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.10),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Center(
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 420),
                      padding: const EdgeInsets.symmetric(
                        vertical: 38,
                        horizontal: 18,
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
                      child: StreamBuilder<RoomState>(
                        stream: _roomStream,
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return Center(
                              child:
                                  snapshot.hasError
                                      ? const Text('No result data.')
                                      : const _ResultsLoader(),
                            );
                          }
                          final room = snapshot.data!;

                          if (!room.resultsReady) {
                            _nudges?.votingEndsAt(room.votingEndsAt);
                            return Center(
                              child: _ResultsLoader(
                                remaining: room.remainingVoters,
                                waiting: true,
                              ),
                            );
                          }

                          _nudges?.stop();
                          // Finished rooms are no longer offered on Home.
                          RoomBackendScope.of(context).activeRooms?.forget();

                          final results = room.results;
                          final Map<String, Restaurant> byId = {
                            for (final r in widget.restaurants) r.id: r,
                            for (final r in room.restaurants) r.id: r,
                          };
                          final Restaurant? winning =
                              results == null
                                  ? null
                                  : byId[results.winnerId] ??
                                      results.winnerCard;

                          if (winning == null || results == null) {
                            return Center(
                              child: Text(
                                'No results available.',
                                style: theme.textTheme.bodyLarge,
                              ),
                            );
                          }
                          final backupId = results.backupId;
                          return _ResultView(
                            winner: winning,
                            winnerLikes: results.winnerLikes,
                            voters: results.participants,
                            backup:
                                backupId == null
                                    ? null
                                    : byId[backupId] ?? results.backupCard,
                            backupLikes: results.likes[backupId] ?? 0,
                            others: [
                              for (final r in byId.values)
                                if (r.id != winning.id) r,
                            ],
                            random: widget.random,
                            onHome: _returnToHome,
                          );
                        },
                      ),
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
}

/// The winner, with a backup kept folded away until someone asks for it.
class _ResultView extends StatefulWidget {
  const _ResultView({
    required this.winner,
    required this.winnerLikes,
    required this.voters,
    required this.backup,
    required this.backupLikes,
    required this.others,
    required this.random,
    required this.onHome,
  });

  final Restaurant winner;
  final int winnerLikes;
  final int voters;
  final Restaurant? backup;
  final int backupLikes;

  /// Every other place in the room, for a random backup when nothing else
  /// got a vote. Empty once the deck is gone.
  final List<Restaurant> others;
  final Random? random;
  final VoidCallback onHome;

  @override
  State<_ResultView> createState() => _ResultViewState();
}

class _ResultViewState extends State<_ResultView> {
  late final Random _random = widget.random ?? Random();
  bool _backupOpen = false;
  Restaurant? _randomBackup;

  bool get _votedBackup => widget.backup != null && widget.backupLikes > 0;

  bool get _hasBackupTile => widget.backup != null || widget.others.isNotEmpty;

  /// The place Copy and Share send: whichever card is open.
  Restaurant get _shown {
    if (!_backupOpen) return widget.winner;
    if (_votedBackup) return widget.backup!;
    return _randomBackup ?? widget.winner;
  }

  // Drawn on the phone from the room's own places, so it costs no search.
  // Each person gets their own.
  Future<void> _pickRandom() async {
    final pick = widget.others[_random.nextInt(widget.others.length)];
    if (_random.nextInt(4) == 0) await _tease();
    if (mounted) setState(() => _randomBackup = pick);
  }

  Future<void> _tease() => showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return Dialog(
        backgroundColor: theme.colorScheme.primary,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
            bottomRight: Radius.circular(24),
            bottomLeft: Radius.circular(4),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Haha! You fell for it!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'I am only kidding, when you close this the random option '
                'will show up for you.',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 6),
              const Text(
                "(I'm not that mean)",
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  String _likedNote(int likes) => '$likes of ${widget.voters} liked it';

  Widget _actions(Restaurant place) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      PlaceActions(links: placeLinksFor(place), alignment: WrapAlignment.start),
      if (SavedPlace.canSave(place)) ...[
        const SizedBox(height: 10),
        PlaceListButtons(restaurant: place),
      ],
    ],
  );

  Widget _tile({
    required Widget label,
    required String tooltip,
    required VoidCallback onTap,
  }) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black26),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(child: label),
            Tooltip(
              message: tooltip,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black26),
                ),
                child: const Icon(Icons.add, size: 20),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _winnerView(ThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Center(
        child: _Banner(
          text: resultBanner(likes: widget.winnerLikes, voters: widget.voters),
          shrug: widget.winnerLikes <= 0,
        ),
      ),
      const SizedBox(height: 14),
      PlaceCard(
        restaurant: widget.winner,
        note: _likedNote(widget.winnerLikes),
        child: _actions(widget.winner),
      ),
      if (_hasBackupTile) ...[
        const SizedBox(height: 14),
        _tile(
          label: Text(
            "It's always good to have a backup plan...",
            style: theme.textTheme.bodyLarge,
          ),
          tooltip: 'Show the backup',
          onTap: () => setState(() => _backupOpen = true),
        ),
      ],
    ],
  );

  Widget _closeButton(VoidCallback close) => Positioned(
    top: -8,
    right: -8,
    child: IconButton(
      icon: const Icon(Icons.close),
      tooltip: 'Close the backup',
      onPressed: close,
    ),
  );

  Widget _backupView(ThemeData theme) {
    void close() => setState(() => _backupOpen = false);
    final backup = widget.backup;
    final random = _randomBackup;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tile(
          label: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Winner',
                style: theme.textTheme.bodySmall!.copyWith(
                  color: Colors.black54,
                ),
              ),
              Text(
                widget.winner.name,
                style: theme.textTheme.titleMedium!.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          tooltip: 'Show the winner',
          onTap: close,
        ),
        const SizedBox(height: 14),
        if (_votedBackup) ...[
          const Center(
            child: _Banner(text: 'Your backup plan', icon: Icons.support),
          ),
          const SizedBox(height: 14),
          PlaceCard(
            restaurant: backup!,
            note: _likedNote(widget.backupLikes),
            onClose: close,
            closeTooltip: 'Close the backup',
            child: _actions(backup),
          ),
        ] else if (random != null) ...[
          const Center(
            child: _Banner(text: 'Your random backup plan', icon: Icons.casino),
          ),
          const SizedBox(height: 14),
          PlaceCard(
            restaurant: random,
            note: 'picked at random',
            onClose: close,
            closeTooltip: 'Close the backup',
            child: _actions(random),
          ),
        ] else
          Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 22),
                  child: Column(
                    children: [
                      Text(
                        'You were all too picky to have a backup plan! '
                        'Nothing else had even 1 vote.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge,
                      ),
                      if (widget.others.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          'But, because I like you...',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.casino),
                          label: const Text('Pick a random one for me'),
                          onPressed: _pickRandom,
                        ),
                      ],
                    ],
                  ),
                ),
                _closeButton(close),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IntrinsicHeight(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Text(
                'Results',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium!.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 34,
                  letterSpacing: 1.2,
                  color: theme.colorScheme.primary,
                  shadows: const [
                    Shadow(
                      color: Colors.black12,
                      blurRadius: 4,
                      offset: Offset(1, 2),
                    ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: PlaceShareButtons(restaurant: _shown),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Spacer(),
          _backupOpen ? _backupView(theme) : _winnerView(theme),
          const Spacer(),
          const SizedBox(height: 20),
          Center(
            child: ElevatedButton(
              onPressed: widget.onHome,
              style: theme.elevatedButtonTheme.style,
              child: const Text('Back to Home'),
            ),
          ),
          // A room from the host's own list has nothing from HERE in it.
          if (!widget.winner.userEntered) ...[
            const SizedBox(height: 12),
            const PlaceCredit(),
          ],
        ],
      ),
    );
  }
}

/// A rounded label above the card: the vote banner, or which backup it is.
class _Banner extends StatelessWidget {
  const _Banner({required this.text, this.icon, this.shrug = false});

  final String text;
  final IconData? icon;

  /// Nobody liked anything: a shrug in place of the celebration.
  final bool shrug;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground =
        shrug ? const Color(0xFF633806) : theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color:
            shrug
                ? const Color(0xFFFAEEDA)
                : theme.colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon ?? (shrug ? Icons.sentiment_neutral : Icons.celebration),
            size: 20,
            color: foreground,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall!.copyWith(
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Loader/waiting state
class _ResultsLoader extends StatelessWidget {
  final int? remaining;
  final bool waiting;
  const _ResultsLoader({this.remaining, this.waiting = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 20),
        CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 28),
        Text(
          remaining != null
              ? 'Waiting for $remaining more vote${remaining! > 1 ? 's' : ''}...'
              : waiting
              ? 'Waiting for everyone to finish voting...'
              : 'Loading results...',
          style: Theme.of(context).textTheme.bodyLarge!.copyWith(fontSize: 18),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
