import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
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
    // Only create a room if this is the creator and no code was pre-generated
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
    // Check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location services are disabled. Please enable them in settings.')),
      );
      return;
    }

    // Check and request location permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _isLoading = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission is required to use this feature.')),
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

    // Save to Firestore
    await RoomService().setRoomOptionsAndStart(
      roomCode: _roomCode!,
      radius: _selectedRadius,
      maxOptions: _selectedMaxOptions,
      options: finalRestaurants,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    // Go to swipe screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SwipeScreen(
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
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.10),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withOpacity(0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back,
                        color: Colors.black54,
                        size: 28,
                      ),
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                if (_roomCode != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        'Room Code',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        _roomCode!,
                        style: TextStyle(
                          fontSize: 30,
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Select Search Radius:',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                DropdownButton<double>(
                  value: _selectedRadius,
                  items:
                      radiusOptions
                          .map(
                            (r) => DropdownMenuItem(
                              value: r.toDouble(),
                              child: Text('$r miles'),
                            ),
                          )
                          .toList(),
                  onChanged:
                      widget.isCreator
                          ? (v) => setState(() => _selectedRadius = v!)
                          : null, // disable for joiners
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Select Number of Options:',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                DropdownButton<int>(
                  value: _selectedMaxOptions,
                  items:
                      optionCounts
                          .map(
                            (c) => DropdownMenuItem(
                              value: c,
                              child: Text('$c options'),
                            ),
                          )
                          .toList(),
                  onChanged:
                      widget.isCreator
                          ? (v) => setState(() => _selectedMaxOptions = v!)
                          : null, // disable for joiners
                ),
                const SizedBox(height: 30),
                if (_isLoading)
                  const CircularProgressIndicator()
                else
                  ElevatedButton(
                    onPressed: widget.isCreator ? _startSwiping : null,
                    child: const Text('Start Swiping'),
                  ),
                if (!widget.isCreator)
                  Padding(
                    padding: const EdgeInsets.only(top: 32),
                    child: Text(
                      "Waiting for host to select options...",
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 16,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
