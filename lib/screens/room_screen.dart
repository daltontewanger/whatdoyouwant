import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/room_backend.dart';
import 'search_panel.dart';
import 'swipe_screen.dart';
import '../models/own_spot.dart';
import '../models/user.dart';

/// What to tell a host whose room could not be created. Covers both callable
/// and Firestore errors; anything else gets the generic retry message.
String createRoomErrorMessage(Object error) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return 'Only verified accounts can host a room. Open Account to sign in or verify your email.';
      case 'resource-exhausted':
        return 'You have created several rooms recently. Wait a while and try again.';
      case 'unauthenticated':
        return 'This device could not be verified. Restart the app and try again.';
    }
  }
  return 'Could not create the room. Check your connection and try again.';
}

/// What to tell a host whose room could not start voting.
String startRoomErrorMessage(Object error) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
      case 'not-found':
        return 'This room can no longer be started. It may have expired or been closed.';
    }
  }
  final common = searchErrorMessage(error);
  if (common != null) return common;
  return 'Could not load restaurants. Check your connection and try again.';
}

class RoomScreen extends StatefulWidget {
  final bool isCreator;

  /// The room's identifier for the backend.
  final String? roomCode;

  /// What guests type to join, when it differs from [roomCode].
  final String? joinCode;
  final AppUser currentUser;

  /// Spots from the host's own list to swipe on in place of a search.
  final List<OwnSpot>? ownSpots;

  const RoomScreen({
    super.key,
    required this.currentUser,
    this.isCreator = true,
    this.roomCode,
    this.joinCode,
    this.ownSpots,
  });

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> with SearchStarter {
  String? _roomCode;
  String? _joinCode;
  Stream<RoomState>? _roomStream;
  bool _isLoading = false;

  RoomBackend get _backend => backend;

  @override
  String get startLabel => 'Start Swiping';

  @override
  String get searchCostNote => 'Starting uses one.';

  @override
  void initState() {
    super.initState();
    _roomCode = widget.roomCode;
    _joinCode = widget.joinCode;
  }

  bool _setupLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.isCreator && !_setupLoaded) {
      _setupLoaded = true;
      loadSearchSetup();
    }
    if (_roomCode != null) {
      _roomStream ??= _backend.watch(_roomCode!);
      _prepareStart();
    } else if (widget.isCreator && !_isLoading) {
      _createRoom();
    }
  }

  Future<void> _createRoom() async {
    setState(() => _isLoading = true);
    try {
      final room = await _backend.createRoom();
      if (!mounted) return;
      setState(() {
        _roomCode = room.id;
        _joinCode = room.joinCode;
        _roomStream = _backend.watch(room.id);
        _isLoading = false;
      });
      _prepareStart();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(createRoomErrorMessage(e))));
    }
  }

  bool _prepared = false;

  bool get _fromList => widget.ownSpots != null;

  /// Lets the backend find the location while the host waits for guests.
  void _prepareStart() {
    if (_prepared || !widget.isCreator || _fromList || !needsLocation) {
      return;
    }
    _prepared = true;
    unawaited(_backend.prepareStart().catchError((_) {}));
  }

  Future<void> _startSwiping() async {
    if (_roomCode == null) return;
    setState(() => _isLoading = true);

    try {
      final spots = widget.ownSpots;
      if (spots == null && needsLocation && !await locationReady()) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final finalRestaurants =
          spots == null
              ? await _backend.start(_roomCode!, search: search, zip: zip)
              : await _backend.startFromList(_roomCode!, spots);

      if (!mounted) return;
      setState(() => _isLoading = false);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => SwipeScreen(
                roomCode: _roomCode!,
                currentUser: widget.currentUser,
                radius: search.radius.toDouble(),
                maxOptions: finalRestaurants.length,
                restaurants: finalRestaurants,
              ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (showBlockedLocation(e)) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(startRoomErrorMessage(e))));
    }
  }

  Widget _listPanel(ThemeData theme) {
    final spots = widget.ownSpots!;
    return Column(
      children: [
        Text('From your list', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          '${spots.length} spots',
          style: theme.textTheme.bodyLarge!.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          spots.map((spot) => spot.name).join(', '),
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        Text(
          "Doesn't use a live search.",
          style: theme.textTheme.bodySmall!.copyWith(color: Colors.grey[800]),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                    vertical: 20,
                    horizontal: 20,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
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
                      final int participantCount =
                          snapshot.data?.memberCount ?? 1;
                      final String? shownCode =
                          snapshot.data?.joinCode ?? _joinCode ?? _roomCode;

                      return LayoutBuilder(
                        builder: (context, innerConstraints) {
                          return SingleChildScrollView(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: innerConstraints.maxHeight,
                              ),
                              child: IntrinsicHeight(
                                child: Column(
                                  children: [
                                    // Top - Room Code
                                    Row(
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                            Icons.arrow_back,
                                            color: Colors.black54,
                                            size: 28,
                                          ),
                                          tooltip: 'Back',
                                          onPressed:
                                              () => Navigator.of(context).pop(),
                                        ),
                                      ],
                                    ),
                                    if (shownCode != null) ...[
                                      Text(
                                        'Room Code',
                                        style: theme.textTheme.titleLarge,
                                      ),
                                      const SizedBox(height: 6),
                                      SelectableText(
                                        shownCode,
                                        style: const TextStyle(
                                          fontSize: 30,
                                          color: Colors.black,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 3,
                                        ),
                                      ),
                                      if (_backend.joinLinkFor(shownCode)
                                          case final link?
                                          when snapshot.data?.status == 'lobby')
                                        _JoinLink(link: link),
                                    ],

                                    // Instructional text
                                    Expanded(
                                      flex: 1,
                                      child: Align(
                                        alignment: Alignment.center,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10.0,
                                          ),
                                          child: Text(
                                            "Provide this code to those intending to join in on the fun. Once they are all confirmed to be in your lobby, you can start swiping!"
                                            "${_backend.usesFictionalRestaurants ? '\n\nThis build uses fictional test restaurants.' : ''}",
                                            style: TextStyle(
                                              fontSize: 15,
                                              color: Colors.grey[800],
                                              fontWeight: FontWeight.w500,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Search Options
                                    if (widget.isCreator)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                        ),
                                        child:
                                            _fromList
                                                ? _listPanel(theme)
                                                : searchPanel(
                                                  theme,
                                                  busy: _isLoading,
                                                ),
                                      ),

                                    // Participant count
                                    Expanded(
                                      flex: 1,
                                      child: Align(
                                        alignment: Alignment.center,
                                        child: Text(
                                          participantCount == 1
                                              ? "Participants in the lobby: 1 (only you)"
                                              : "Participants in the lobby: $participantCount",
                                          style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 16,
                                            fontStyle: FontStyle.italic,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),

                                    // Bottom - Start Swiping Button
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: 12.0,
                                        bottom: 4.0,
                                      ),
                                      child:
                                          _isLoading
                                              ? const Center(
                                                child:
                                                    CircularProgressIndicator(),
                                              )
                                              : Center(
                                                child: ElevatedButton(
                                                  onPressed:
                                                      widget.isCreator &&
                                                              (_fromList ||
                                                                  !cannotSearch)
                                                          ? _startSwiping
                                                          : null,
                                                  style: ElevatedButton.styleFrom(
                                                    minimumSize: const Size(
                                                      170,
                                                      46,
                                                    ),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            14,
                                                          ),
                                                    ),
                                                  ),
                                                  child: const Text(
                                                    'Start Swiping',
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
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

/// A QR code and a copyable link, so people at the same table can join by
/// pointing a camera instead of typing the code.
class _JoinLink extends StatelessWidget {
  const _JoinLink({required this.link});

  final Uri link;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          Semantics(
            label: 'QR code that opens the join link for this room',
            image: true,
            // A fixed-size painter: the lobby measures its own height, which
            // QrImageView's layout builder cannot report.
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(8),
              child: CustomPaint(
                size: const Size.square(132),
                painter: QrPainter(
                  data: link.toString(),
                  version: QrVersions.auto,
                ),
              ),
            ),
          ),
          TextButton.icon(
            icon: const Icon(Icons.link),
            label: const Text('Copy join link'),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(ClipboardData(text: link.toString()));
              messenger.showSnackBar(
                const SnackBar(content: Text('Join link copied')),
              );
            },
          ),
        ],
      ),
    );
  }
}
