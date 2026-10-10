import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:vero360_app/Home/merchant_story_model.dart';
import 'package:vero360_app/Home/story_service.dart';
import 'package:vero360_app/Home/story_viewer_screen.dart';

/// WhatsApp-style story ring colors.
abstract final class StoryRingColors {
  static const unviewed = Color(0xFF25D366);
  static const viewed = Color(0xFFB0B0B0);
}

/// Gradient ring decoration for story avatars.
class StoryRingDecoration {
  static BoxDecoration ring({required bool hasStories, required bool hasUnviewed}) {
    if (!hasStories) {
      return BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE0E0E0), width: 2),
      );
    }
    final color = hasUnviewed ? StoryRingColors.unviewed : StoryRingColors.viewed;
    return BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        colors: [color, color.withValues(alpha: 0.75)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      boxShadow: hasUnviewed
          ? [
              BoxShadow(
                color: StoryRingColors.unviewed.withValues(alpha: 0.28),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ]
          : null,
    );
  }
}

/// Profile avatar with optional WhatsApp-style story ring.
class StoryProfileRing extends StatelessWidget {
  final String merchantId;
  final String merchantName;
  final String? merchantImageUrl;
  final double size;
  final Widget? child;
  final ImageProvider? imageProvider;
  final IconData placeholderIcon;
  final List<MerchantStoryGroup>? allGroups;
  /// When set (e.g. home stories row), reuse preloaded group data instead of
  /// opening a separate Firestore stream per ring.
  final MerchantStoryGroup? fixedGroup;
  final VoidCallback? onNoStoriesTap;
  /// When set, a normal tap always runs this (e.g. open full profile photo).
  /// Stories still open via long-press when available.
  final VoidCallback? onAvatarTap;

  const StoryProfileRing({
    super.key,
    required this.merchantId,
    required this.merchantName,
    this.merchantImageUrl,
    this.size = 64,
    this.child,
    this.imageProvider,
    this.placeholderIcon = Icons.store_rounded,
    this.allGroups,
    this.fixedGroup,
    this.onNoStoriesTap,
    this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    if (fixedGroup != null) {
      final group = fixedGroup!;
      final state = MerchantStoryRingState(
        items: group.items,
        hasStories: group.items.isNotEmpty,
        hasUnviewed: group.hasUnviewed,
        group: group,
      );
      return _buildRing(context, state);
    }

    final viewerId = FirebaseAuth.instance.currentUser?.uid;
    final service = StoryService();

    return StreamBuilder<MerchantStoryRingState>(
      stream: service.watchMerchantStoryRing(
        merchantId: merchantId,
        viewerId: viewerId,
      ),
      builder: (context, snapshot) {
        final state = snapshot.data ?? MerchantStoryRingState.empty;
        return _buildRing(context, state);
      },
    );
  }

  Widget _buildRing(BuildContext context, MerchantStoryRingState state) {
    final hasStories = state.hasStories;
    final hasUnviewed = state.hasUnviewed;
    // Keep a thin inset so the empty gray ring (add-story) stays visible.
    final ringPadding = hasStories ? 3.0 : 2.0;
    final innerSize = size - ringPadding * 2;

    return _StoryRingTap(
      onTap: () => _onTap(context, state),
      onLongPress: onAvatarTap == null ? null : () => _openStories(context, state),
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(ringPadding),
        decoration: StoryRingDecoration.ring(
          hasStories: hasStories,
          hasUnviewed: hasUnviewed,
        ),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
          padding: const EdgeInsets.all(2),
          child: ClipOval(
            child: child ?? _defaultAvatar(innerSize - 4, state),
          ),
        ),
      ),
    );
  }

  Widget _defaultAvatar(double innerSize, MerchantStoryRingState state) {
    if (imageProvider != null) {
      return Image(
        image: imageProvider!,
        width: innerSize,
        height: innerSize,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(innerSize),
      );
    }

    final latest = state.items.isNotEmpty ? state.items.last : null;
    final latestIsVideo = latest?.mediaType == 'video';
    if (!latestIsVideo && latest != null && latest.mediaUrl.isNotEmpty) {
      return Image.network(
        latest.mediaUrl,
        key: ValueKey(latest.mediaUrl),
        width: innerSize,
        height: innerSize,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, __, ___) => _placeholder(innerSize),
      );
    }

    final inline = latest == null || latestIsVideo
        ? null
        : StoryInlineImageCache.bytesFor(latest.storyId, latest.imageBase64);
    if (inline != null) {
      return Image.memory(
        inline,
        width: innerSize,
        height: innerSize,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, __, ___) => _placeholder(innerSize),
      );
    }

    final fallback = merchantImageUrl?.trim() ?? '';
    if (fallback.isNotEmpty) {
      return Image.network(
        fallback,
        key: ValueKey(fallback),
        width: innerSize,
        height: innerSize,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, __, ___) => _placeholder(innerSize),
      );
    }

    return _placeholder(innerSize);
  }

  Widget _placeholder(double innerSize) {
    return Container(
      width: innerSize,
      height: innerSize,
      color: const Color(0xFFF5F5F5),
      child: Icon(placeholderIcon, color: const Color(0xFF6B6B6B), size: innerSize * 0.44),
    );
  }

  void _onTap(BuildContext context, MerchantStoryRingState state) {
    // Prefer explicit avatar action (e.g. view profile photo).
    if (onAvatarTap != null) {
      onAvatarTap!();
      return;
    }
    if (!state.hasStories || state.group == null) {
      onNoStoriesTap?.call();
      return;
    }
    _openStories(context, state);
  }

  void _openStories(BuildContext context, MerchantStoryRingState state) {
    if (!state.hasStories || state.group == null) return;

    final groups = allGroups ?? [state.group!];
    final index = groups.indexWhere((g) => g.merchantId == merchantId);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => StoryViewerScreen(
          groups: groups,
          initialGroupIndex: index >= 0 ? index : 0,
        ),
      ),
    );
  }
}

/// Compact story ring used in horizontal lists (home stories row).
class StoryListRing extends StatelessWidget {
  final MerchantStoryGroup group;
  final List<MerchantStoryGroup> allGroups;
  final int index;
  final double size;
  final bool isOwn;
  final int? ownViewCount;
  /// WhatsApp / Instagram-style green + on your own ring.
  final bool showAddBadge;
  final VoidCallback? onAddStory;
  final VoidCallback? onNoStoriesTap;

  const StoryListRing({
    super.key,
    required this.group,
    required this.allGroups,
    required this.index,
    this.size = 64,
    this.isOwn = false,
    this.ownViewCount,
    this.showAddBadge = false,
    this.onAddStory,
    this.onNoStoriesTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasStories = group.items.isNotEmpty;
    final label = isOwn
        ? (hasStories ? 'Your story' : 'Add story')
        : group.merchantName;
    final viewerGroups = allGroups.where((g) => g.items.isNotEmpty).toList();

    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              StoryProfileRing(
                merchantId: group.merchantId,
                merchantName: group.merchantName,
                merchantImageUrl: group.merchantImageUrl,
                size: size,
                allGroups: viewerGroups.isNotEmpty ? viewerGroups : null,
                fixedGroup: group,
                placeholderIcon:
                    isOwn ? Icons.person_rounded : Icons.store_rounded,
                onNoStoriesTap: onNoStoriesTap,
              ),
              if (showAddBadge)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: onAddStory,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Container(
                        margin: const EdgeInsets.all(1.5),
                        decoration: const BoxDecoration(
                          color: Color(0xFF25D366),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.add,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: size + 20,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isOwn ? FontWeight.w800 : FontWeight.w600,
                color: const Color(0xFF101010),
              ),
            ),
          ),
          if (isOwn && ownViewCount != null && hasStories) ...[
            const SizedBox(height: 2),
            Text(
              '${ownViewCount!} view${ownViewCount == 1 ? '' : 's'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Opens on the first tap inside the home scroll view.
/// A long-press recognizer on the same target was swallowing that tap.
class _StoryRingTap extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _StoryRingTap({
    required this.child,
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<_StoryRingTap> createState() => _StoryRingTapState();
}

class _StoryRingTapState extends State<_StoryRingTap> {
  Offset? _origin;
  Timer? _hold;
  bool _longFired = false;

  void _clear() {
    _hold?.cancel();
    _hold = null;
    _origin = null;
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        _longFired = false;
        _origin = e.position;
        _hold?.cancel();
        if (widget.onLongPress == null) return;
        _hold = Timer(const Duration(milliseconds: 450), () {
          if (!mounted || _origin == null) return;
          _longFired = true;
          widget.onLongPress?.call();
        });
      },
      onPointerMove: (e) {
        final origin = _origin;
        if (origin == null) return;
        if ((e.position - origin).distance > 16) _clear();
      },
      onPointerUp: (e) {
        final origin = _origin;
        _hold?.cancel();
        _hold = null;
        _origin = null;
        if (_longFired || origin == null) return;
        if ((e.position - origin).distance > 16) return;
        widget.onTap();
      },
      onPointerCancel: (_) => _clear(),
      child: widget.child,
    );
  }
}
