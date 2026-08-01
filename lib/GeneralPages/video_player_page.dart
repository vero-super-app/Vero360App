// lib/Pages/video_player_page.dart
import 'package:flutter/material.dart';

class VideoPlayerPage extends StatelessWidget {
  final String url;
  const VideoPlayerPage({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    // Replace with video_player + chewie as needed
    return Scaffold(
      appBar: AppBar(title: const Text('Video')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.play_circle_fill, size: 80),
            const SizedBox(height: 12),
            Text('Play video:\n$url', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
