// address.dart
import 'package:flutter/material.dart';

class EducationPage extends StatelessWidget {
  const EducationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Education Page'),
      ),
      body: const Center(
        child: Text('find education resources'),
      ),
    );
  }
}
