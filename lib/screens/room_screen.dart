import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/room_service.dart';
import '../services/location_services.dart';
import 'swipe_screen.dart';
import '../models/user.dart';

class RoomScreen extends StatefulWidget {
  final bool isCreator;
  final String? roomCode;
  final AppUser currentUser;

  const RoomScreen({
    super.key,
    required this.currentUser,
    this.isCreator = true,
    this.roomCode,
  });

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  String? _roomCode;
  double _selectedRadius = 5.0;
  int _selectedMaxOptions = 5;
  final List<int> radiusOptions = [1, 3, 5, 10, 15];
  final List<int> optionCounts = [5, 10, 15, 25];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _roomCode = widget.roomCode;
    if (widget.isCreator && widget.roomCode == null) {
      _createRoom();
    }
  }

  Future<void> _createRoom() async {
    setState(() => _isLoading = true);
    try {
      final code = await RoomService().createRoom(widget.currentUser.id);
      if (!mounted) return;
      setState(() {
        _roomCode = code;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error creating room: $e')));
    }
  }

  Future<void> _startSwiping() async {
    if (_roomCode == null) return;
    setState(() => _isLoading = true);

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _isLoading = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Location services are disabled. Please enable them in settings.',
            ),
          ),
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _isLoading = false);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Location permission is required to use this feature.',
              ),
            ),
          );
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() => _isLoading = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Location permissions are permanently denied. Please enable them in your device settings.',
            ),
            action: SnackBarAction(
              label: 'Open Settings',
              onPressed: () async {
                await Geolocator.openAppSettings();
              },
            ),
            duration: const Duration(seconds: 6),
          ),
        );
        return;
      }

      final fetched = await LocationService.fetchNearbyRestaurantsTiled(
        radiusMiles: _selectedRadius,
      );
      final finalRestaurants = LocationService.filterAndRandomizeRestaurants(
        allRestaurants: fetched,
        radiusMiles: _selectedRadius,
        maxOptions: _selectedMaxOptions,
      );

      await RoomService().setRoomOptionsAndStart(
        roomCode: _roomCode!,
        radius: _selectedRadius,
        maxOptions: _selectedMaxOptions,
        options: finalRestaurants,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => SwipeScreen(
                roomCode: _roomCode!,
                currentUser: widget.currentUser,
                radius: _selectedRadius,
                maxOptions: _selectedMaxOptions,
                restaurants: finalRestaurants,
              ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error fetching restaurants: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                  padding: const EdgeInsets.symmetric(
                    vertical: 20,
                    horizontal: 20,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withOpacity(0.10),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: StreamBuilder<DocumentSnapshot>(
                    stream:
                        _roomCode == null
                            ? null
                            : FirebaseFirestore.instance
                                .collection('rooms')
                                .doc(_roomCode)
                                .snapshots(),
                    builder: (context, snapshot) {
                      int participantCount = 1;
                      if (snapshot.hasData && snapshot.data!.exists) {
                        final data =
                            snapshot.data!.data() as Map<String, dynamic>;
                        if (data['participants'] != null) {
                          if (data['participants'] is List) {
                            participantCount =
                                (data['participants'] as List).length;
                          } else if (data['participants'] is Map) {
                            participantCount =
                                (data['participants'] as Map).length;
                          }
                        }
                      }

                      // Magic scroll + expanded combo:
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
                                    // ---- Top: Room Code (fixed top)
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
                                    if (_roomCode != null) ...[
                                      Text(
                                        'Room Code',
                                        style: theme.textTheme.titleLarge,
                                      ),
                                      const SizedBox(height: 6),
                                      SelectableText(
                                        _roomCode!,
                                        style: const TextStyle(
                                          fontSize: 30,
                                          color: Colors.black,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 3,
                                        ),
                                      ),
                                    ],

                                    // ---- Instructional text (evenly spaced)
                                    Expanded(
                                      flex: 1,
                                      child: Align(
                                        alignment: Alignment.center,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10.0,
                                          ),
                                          child: Text(
                                            "Provide this code to those intending to join in on the fun. Once they are all confirmed to be in your lobby, you can start swiping!",
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

                                    // ---- Search Options (evenly spaced)
                                    Expanded(
                                      flex: 2, 
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            'Select Search Radius:',
                                            style: theme.textTheme.titleLarge,
                                          ),
                                          const SizedBox(height: 4),
                                          SizedBox(
                                            width: 100,
                                            child: DropdownButton<double>(
                                              value: _selectedRadius,
                                              isExpanded: true,
                                              items:
                                                  radiusOptions
                                                      .map(
                                                        (r) => DropdownMenuItem(
                                                          value: r.toDouble(),
                                                          child: Text(
                                                            '$r miles',
                                                          ),
                                                        ),
                                                      )
                                                      .toList(),
                                              onChanged:
                                                  (v) => setState(
                                                    () => _selectedRadius = v!,
                                                  ),
                                            ),
                                          ),
                                          const SizedBox(height: 18),
                                          Text(
                                            'Select Number of Options:',
                                            style: theme.textTheme.titleLarge,
                                          ),
                                          const SizedBox(height: 4),
                                          SizedBox(
                                            width: 100,
                                            child: DropdownButton<int>(
                                              value: _selectedMaxOptions,
                                              isExpanded: true,
                                              items:
                                                  optionCounts
                                                      .map(
                                                        (c) => DropdownMenuItem(
                                                          value: c,
                                                          child: Text(
                                                            '$c options',
                                                          ),
                                                        ),
                                                      )
                                                      .toList(),
                                              onChanged:
                                                  (v) => setState(
                                                    () =>
                                                        _selectedMaxOptions =
                                                            v!,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // ---- Participant count (evenly spaced)
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

                                    // ---- Bottom: Start Swiping Button (fixed bottom)
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
                                                      widget.isCreator
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
