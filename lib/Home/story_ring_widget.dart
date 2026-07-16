import 'dart:convert';

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
      return const BoxDecoration(shape: BoxShape.circle);
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
    final ringPadding = hasStories ? 3.0 : 0.0;
    final innerSize = size - ringPadding * 2;

    return InkWell(
      onTap: () => _onTap(context, state),
      borderRadius: BorderRadius.circular(size / 2 + 4),
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
            color: hasStories ? Colors.white : Colors.transparent,
          ),
          padding: hasStories ? const EdgeInsets.all(2) : EdgeInsets.zero,
          child: ClipOval(
            child: child ?? _defaultAvatar(innerSize, state),
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
    final imageBase64 = latest?.imageBase64;
    if (imageBase64 != null && imageBase64.isNotEmpty) {
      try {
        final bytes = base64Decode(imageBase64);
        return Image.memory(
          bytes,
          width: innerSize,
          height: innerSize,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(innerSize),
        );
      } catch (_) {}
    }

    final thumbUrl = latest?.mediaUrl.isNotEmpty == true
        ? latest!.mediaUrl
        : merchantImageUrl;
    if (thumbUrl != null && thumbUrl.isNotEmpty) {
      return Image.network(
        thumbUrl,
        width: innerSize,
        height: innerSize,
        fit: BoxFit.cover,
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
    if (!state.hasStories || state.group == null) {
      onNoStoriesTap?.call();
      return;
    }

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

  const StoryListRing({
    super.key,
    required this.group,
    required this.allGroups,
    required this.index,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StoryProfileRing(
            merchantId: group.merchantId,
            merchantName: group.merchantName,
            merchantImageUrl: group.merchantImageUrl,
            size: size,
            allGroups: allGroups,
            fixedGroup: group,
            placeholderIcon: Icons.store_rounded,
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: size + 20,
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
    );
  }
}
