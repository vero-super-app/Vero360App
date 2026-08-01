// address.dart
import 'package:flutter/material.dart';

class Fitnespage extends StatelessWidget {
  const Fitnespage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gym & Fitness'),
      ),
      body: const Center(
        child: Text('fitness page'),
      ),
    );
  }
}
