import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:vero360_app/Home/merchant_story_model.dart';
import 'package:vero360_app/Home/story_service.dart';
import 'package:vero360_app/Home/story_viewer_screen.dart';

class StorySection extends StatelessWidget {
  const StorySection({super.key});

  static const _ringSize = 64.0;

  @override
  Widget build(BuildContext context) {
    final service = StoryService();
    return StreamBuilder<List<MerchantStoryGroup>>(
      stream: service.getActiveStoriesStream(),
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
          height: _ringSize + 36,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final g = groups[index];
              return _StoryRing(
                group: g,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => StoryViewerScreen(group: g),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _StoryRing extends StatelessWidget {
  final MerchantStoryGroup group;
  final VoidCallback onTap;

  const _StoryRing({required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final latest = group.latestItem;
    final imageUrl = latest?.mediaUrl.isNotEmpty == true
        ? latest!.mediaUrl
        : (group.merchantImageUrl);
    final imageBase64 = latest?.imageBase64;
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_StoryRing.ringSize / 2 + 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: _StoryRing.ringSize + 4,
              height: _StoryRing.ringSize + 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFFF8A00),
                    const Color(0xFFFF8A00).withOpacity(0.7),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF8A00).withOpacity(0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(2),
              child: Container(
                width: _StoryRing.ringSize,
                height: _StoryRing.ringSize,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                padding: const EdgeInsets.all(2),
                child: ClipOval(
                  child: _thumbnailWidget(imageUrl, imageBase64),
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: _StoryRing.ringSize + 20,
              child: Text(
                group.merchantName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF101010),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const double ringSize = 64.0;

  Widget _thumbnailWidget(String? imageUrl, String? imageBase64) {
    if (imageBase64 != null && imageBase64.isNotEmpty) {
      try {
        final bytes = base64Decode(imageBase64);
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          width: _StoryRing.ringSize,
          height: _StoryRing.ringSize,
          errorBuilder: (_, __, ___) => _placeholder(),
        );
      } catch (_) {
        return _placeholder();
      }
    }
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        width: _StoryRing.ringSize,
        height: _StoryRing.ringSize,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      color: const Color(0xFFF5F5F5),
      child: const Center(
        child: Icon(Icons.store_rounded, color: Color(0xFF6B6B6B), size: 28),
      ),
    );
  }
}
