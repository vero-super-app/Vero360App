import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:vero360_app/Home/merchant_story_model.dart';
import 'package:vero360_app/Home/story_service.dart';
import 'package:vero360_app/Home/story_ring_widget.dart';

class StorySection extends StatefulWidget {
  const StorySection({super.key});

  @override
  State<StorySection> createState() => _StorySectionState();
}

class _StorySectionState extends State<StorySection> {
  static const _ringSize = 64.0;
  final StoryService _service = StoryService();

  @override
  Widget build(BuildContext context) {
    final viewerId = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<List<MerchantStoryGroup>>(
      stream: _service.getActiveStoriesStream(viewerId: viewerId),
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
        if (!snapshot.hasData) {
          return SizedBox(
            height: _ringSize + 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              itemCount: 5,
              itemBuilder: (_, __) => Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: _ringSize,
                      height: _ringSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey.shade200,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: _ringSize,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final groups = snapshot.data!;
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
