// address.dart
import 'package:flutter/material.dart';

class ToShipPage extends StatelessWidget {
  const ToShipPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('To  Ship'),
      ),
      body: const Center(
        child: Text('This is what is is about to be shipped'),
      ),
    );
  }
}
