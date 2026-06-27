import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:vero360_app/Home/merchant_story_model.dart';
import 'package:vero360_app/Home/story_service.dart';
import 'package:vero360_app/Home/story_ring_widget.dart';

class StorySection extends StatelessWidget {
  const StorySection({super.key});

  static const _ringSize = 64.0;

  @override
  Widget build(BuildContext context) {
    final service = StoryService();
    final viewerId = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<List<MerchantStoryGroup>>(
      stream: service.getActiveStoriesStream(viewerId: viewerId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                'Stories unavailable',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ),
          );
        }
        final groups = snapshot.data ?? [];
        if (groups.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                'No stories right now',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ),
          );
        }
        return SizedBox(
          height: _ringSize + 44,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              return StoryListRing(
                group: groups[index],
                allGroups: groups,
                index: index,
                size: _ringSize,
              );
            },
          ),
        );
      },
    );
  }
}
