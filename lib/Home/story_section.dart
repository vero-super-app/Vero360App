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
  late final Stream<List<MerchantStoryGroup>> _stream;
  List<MerchantStoryGroup>? _lastGroups;
  int? _ownViewCount;
  String? _ownViewsForMerchantId;
  String? _ownViewsStoryKey;

  @override
  void initState() {
    super.initState();
    final viewerId = FirebaseAuth.instance.currentUser?.uid;
    // One stream for this State — avoid resubscribe flashes on parent rebuilds.
    _stream = _service.getActiveStoriesStream(viewerId: viewerId);
    _lastGroups = StoryService.lastActiveGroups;
  }

  List<MerchantStoryGroup> _orderedGroups(List<MerchantStoryGroup> groups) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return groups;
    final ownIndex = groups.indexWhere((g) => g.merchantId == uid);
    if (ownIndex <= 0) return groups;
    final copy = List<MerchantStoryGroup>.from(groups);
    final own = copy.removeAt(ownIndex);
    copy.insert(0, own);
    return copy;
  }

  void _maybeLoadOwnViews(List<MerchantStoryGroup> groups) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    MerchantStoryGroup? own;
    for (final g in groups) {
      if (g.merchantId == uid) {
        own = g;
        break;
      }
    }
    if (own == null || own.items.isEmpty) {
      if (_ownViewCount != null || _ownViewsForMerchantId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _ownViewCount = null;
            _ownViewsForMerchantId = null;
            _ownViewsStoryKey = null;
          });
        });
      }
      return;
    }
    final latest = own.latestItem;
    if (latest == null) return;
    final key = own.items.map((e) => e.storyId).join('|');
    if (_ownViewsForMerchantId == uid && _ownViewsStoryKey == key) return;
    _ownViewsForMerchantId = uid;
    _ownViewsStoryKey = key;
    _service.getStoryViewerCounts(own.items.map((e) => e.storyId).toList()).then((counts) {
      if (!mounted) return;
      final total = counts.values.fold<int>(0, (a, b) => a + b);
      setState(() => _ownViewCount = total);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MerchantStoryGroup>>(
      stream: _stream,
      initialData: _lastGroups,
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

        final groups = snapshot.data ?? _lastGroups;
        if (groups != null && groups.isNotEmpty) {
          _lastGroups = groups;
        }

        if (groups == null) {
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

        final ordered = _orderedGroups(groups);
        _maybeLoadOwnViews(ordered);
        final uid = FirebaseAuth.instance.currentUser?.uid;
        final rowHeight = (uid != null &&
                ordered.any((g) => g.merchantId == uid) &&
                _ownViewCount != null)
            ? _ringSize + 58
            : _ringSize + 44;

        return SizedBox(
          height: rowHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            itemCount: ordered.length,
            itemBuilder: (context, index) {
              final group = ordered[index];
              final isOwn = uid != null && group.merchantId == uid;
              return StoryListRing(
                group: group,
                allGroups: ordered,
                index: index,
                size: _ringSize,
                isOwn: isOwn,
                ownViewCount: isOwn ? _ownViewCount : null,
              );
            },
          ),
        );
      },
    );
  }
}
