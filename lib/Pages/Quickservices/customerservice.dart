// address.dart
import 'package:flutter/material.dart';

class CustomerServicePage extends StatelessWidget {
  const CustomerServicePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('customer service'),
      ),
      body: const Center(
        child: Text('contact us'),
      ),
    );
  }
}
