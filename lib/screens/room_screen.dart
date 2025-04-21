import 'package:flutter/material.dart';
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
  _RoomScreenState createState() => _RoomScreenState();
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
    // Only join if this is a joiner and a roomCode was provided
    else if (!widget.isCreator && widget.roomCode != null) {
      _joinRoom(widget.roomCode!);
    }
  }

  Future<void> _createRoom() async {
    setState(() => _isLoading = true);
    try {
      final code = await RoomService().createRoom(widget.currentUser.id);
      setState(() {
        _roomCode = code;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error creating room: $e')),
      );
    }
  }

  Future<void> _joinRoom(String code) async {
    setState(() => _isLoading = true);
    try {
      await RoomService().joinRoom(code, widget.currentUser.id);
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error joining room: $e')),
      );
    }
  }

  Future<void> _startSwiping() async {
    if (_roomCode == null) return;
    setState(() => _isLoading = true);
    try {
      final fetched = await LocationService.fetchNearbyRestaurantsTiled(
        radiusMiles: _selectedRadius,
      );
      final finalRestaurants = LocationService.filterAndRandomizeRestaurants(
        allRestaurants: fetched,
        radiusMiles: _selectedRadius,
        maxOptions: _selectedMaxOptions,
      );
      if (!mounted) return;
      setState(() => _isLoading = false);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching restaurants: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isCreator ? 'Create Room' : 'Join Room'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (_roomCode != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Room Code:', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(_roomCode!, style: const TextStyle(fontSize: 24, color: Colors.orange)),
                  const SizedBox(height: 20),
                ],
              ),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Select Search Radius:', style: TextStyle(fontSize: 18)),
            ),
            DropdownButton<double>(
              value: _selectedRadius,
              items: radiusOptions.map((r) => DropdownMenuItem(value: r.toDouble(), child: Text('$r miles'))).toList(),
              onChanged: (v) => setState(() => _selectedRadius = v!),
            ),
            const SizedBox(height: 20),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Select Number of Options:', style: TextStyle(fontSize: 18)),
            ),
            DropdownButton<int>(
              value: _selectedMaxOptions,
              items: optionCounts.map((c) => DropdownMenuItem(value: c, child: Text('$c options'))).toList(),
              onChanged: (v) => setState(() => _selectedMaxOptions = v!),
            ),
            const Spacer(),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(onPressed: _startSwiping, child: const Text('Start Swiping')),
          ],
        ),
      ),
    );
  }
}
