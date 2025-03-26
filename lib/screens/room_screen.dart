import 'package:flutter/material.dart';
import 'swipe_screen.dart';

class RoomScreen extends StatefulWidget {
  final bool isCreator;
  final String? roomCode;

  const RoomScreen({
    Key? key,
    this.isCreator = true,
    this.roomCode,
  }) : super(key: key);

  @override
  _RoomScreenState createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  // Default values for the settings
  double _selectedRadius = 5.0;
  int _selectedMaxOptions = 5;

  // Predefined options for radius and max options
  final List<int> radiusOptions = [1, 3, 5, 10, 15, 25];
  final List<int> optionCounts = [5, 10, 15, 25];

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
            if (widget.isCreator)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Room Code:',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    widget.roomCode ?? 'N/A',
                    style: TextStyle(fontSize: 24, color: Colors.orange),
                  ),
                  SizedBox(height: 20),
                ],
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Select Search Radius:',
                style: TextStyle(fontSize: 18),
              ),
            ),
            DropdownButton<double>(
              value: _selectedRadius,
              items: radiusOptions.map((radius) {
                return DropdownMenuItem<double>(
                  value: radius.toDouble(),
                  child: Text('$radius miles'),
                );
              }).toList(),
              onChanged: (newValue) {
                setState(() {
                  _selectedRadius = newValue!;
                });
              },
            ),
            SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Select Number of Options:',
                style: TextStyle(fontSize: 18),
              ),
            ),
            DropdownButton<int>(
              value: _selectedMaxOptions,
              items: optionCounts.map((count) {
                return DropdownMenuItem<int>(
                  value: count,
                  child: Text('$count options'),
                );
              }).toList(),
              onChanged: (newValue) {
                setState(() {
                  _selectedMaxOptions = newValue!;
                });
              },
            ),
            Spacer(),
            ElevatedButton(
              onPressed: () {
                // Navigate to the swipe screen with selected settings
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SwipeScreen(
                      radius: _selectedRadius,
                      maxOptions: _selectedMaxOptions,
                    ),
                  ),
                );
              },
              child: const Text('Start Swiping'),
            ),
          ],
        ),
      ),
    );
  }
}
