// address.dart
import 'package:flutter/material.dart';

class ToRefundPage extends StatelessWidget {
  const ToRefundPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('To Refund'),
      ),
      body: const Center(
        child: Text('This is what you need to be refunded'),
      ),
    );
  }
}
