// address.dart
import 'package:flutter/material.dart';

class MobilemoneyPage extends StatelessWidget {
  const MobilemoneyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MobileMoney'),
      ),
      body: const Center(
        child: Text('mobile money'),
      ),
    );
  }
}
