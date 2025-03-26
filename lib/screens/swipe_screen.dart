import 'package:flutter/material.dart';

class SwipeScreen extends StatelessWidget {
  final double radius;
  final int maxOptions;

  const SwipeScreen({
    Key? key,
    required this.radius,
    required this.maxOptions,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Swipe Screen'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Placeholder for Swipe Screen\n\n'
            'Search Radius: $radius miles\n'
            'Max Options: $maxOptions',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20),
          ),
        ),
      ),
    );
  }
}
