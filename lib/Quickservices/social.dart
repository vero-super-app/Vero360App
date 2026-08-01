// address.dart
import 'package:flutter/material.dart';

class SocialPage extends StatelessWidget {
  const SocialPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Social Connect'),
      ),
      body: const Center(
        child: Text('our community'),
      ),
    );
  }
}
