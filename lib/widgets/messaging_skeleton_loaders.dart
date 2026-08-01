import 'package:flutter/material.dart';
import 'package:vero360_app/widgets/app_skeleton.dart';

/// Soft, warm palette for cute messaging skeletons.
class MessagingSkeleton {
  MessagingSkeleton._();

  static const Color bone = Color(0xFFEDEEF2);
  static const Color boneLight = Color(0xFFF7F8FA);
  static const Color peach = Color(0xFFFFEFE3);
  static const Color peachDeep = Color(0xFFFFE0C2);
  static const Color cardBg = Colors.white;
  static const Color brand = Color(0xFFFF8A00);
  static const Color chatBg = Color(0xFFF3F4F7);
}

// ─── Chat list ───────────────────────────────────────────────────────────────

class ChatListSkeleton extends StatelessWidget {
  const ChatListSkeleton({super.key, this.rows = 8});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return AppSkeletonShimmer(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
        itemCount: rows,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _ChatListRowSkeleton(index: i),
      ),
    );
  }
}

class _ChatListRowSkeleton extends StatelessWidget {
  const _ChatListRowSkeleton({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final titleW = 120.0 + (index % 3) * 28;
    final previewW = index.isEven ? double.infinity : 200.0;
    final showProduct = index % 2 == 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: MessagingSkeleton.cardBg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          _CuteAvatarBone(size: 50, showOnlineDot: index.isOdd),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: AppSkeletonBox(
                        height: 14,
                        width: titleW,
                        radius: 7,
                        color: MessagingSkeleton.bone,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const AppSkeletonBox(
                      height: 10,
                      width: 36,
                      radius: 5,
                      color: MessagingSkeleton.boneLight,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                AppSkeletonBox(
                  height: 11,
                  width: previewW,
                  radius: 5,
                  color: MessagingSkeleton.boneLight,
                ),
                if (showProduct) ...[
                  const SizedBox(height: 5),
                  AppSkeletonBox(
                    height: 10,
                    width: 88,
                    radius: 5,
                    color: MessagingSkeleton.peach,
                  ),
                ],
              ],
            ),
          ),
          if (showProduct) ...[
            const SizedBox(width: 10),
            _CuteProductThumbBone(),
          ],
        ],
      ),
    );
  }
}

// ─── Full chat screen loading (header + messages + typing) ───────────────────

/// Top app-bar shimmer while chat boots (avatar + title lines).
class ChatAppBarSkeleton extends StatelessWidget {
  const ChatAppBarSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 0.6,
      shadowColor: Colors.black12,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 8, 10),
          child: AppSkeletonShimmer(
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: Colors.black87,
                ),
                const _CuteAvatarBone(size: 40),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppSkeletonBox(
                        height: 15,
                        width: 128,
                        radius: 7,
                        color: MessagingSkeleton.bone,
                      ),
                      SizedBox(height: 6),
                      AppSkeletonBox(
                        height: 11,
                        width: 84,
                        radius: 6,
                        color: MessagingSkeleton.boneLight,
                      ),
                    ],
                  ),
                ),
                const AppSkeletonBox(
                  width: 22,
                  height: 22,
                  radius: 8,
                  color: MessagingSkeleton.boneLight,
                ),
                const SizedBox(width: 8),
                const AppSkeletonBox(
                  width: 22,
                  height: 22,
                  radius: 8,
                  color: MessagingSkeleton.boneLight,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen boot state — skeleton app bar, messages, and composer only.
class ChatBootLoadingScaffold extends StatelessWidget {
  const ChatBootLoadingScaffold({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MessagingSkeleton.chatBg,
      body: Column(
        children: const [
          ChatAppBarSkeleton(),
          Expanded(
            child: ChatScreenLoadingSkeleton(includeHeaderStrip: false),
          ),
          ChatComposerSkeleton(),
        ],
      ),
    );
  }
}

/// Marketplace “Opening chat…” overlay — matches in-chat skeleton style.
class OpeningChatLoadingDialog extends StatelessWidget {
  const OpeningChatLoadingDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: MessagingSkeleton.brand.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: AppSkeletonShimmer(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: const [
                    _CuteAvatarBone(size: 44, ringColor: MessagingSkeleton.peachDeep),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppSkeletonBox(
                            height: 14,
                            width: 110,
                            radius: 7,
                            color: MessagingSkeleton.bone,
                          ),
                          SizedBox(height: 7),
                          AppSkeletonBox(
                            height: 10,
                            width: 72,
                            radius: 5,
                            color: MessagingSkeleton.boneLight,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const _TypingIndicatorSkeleton(),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 15,
                      color: MessagingSkeleton.brand.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Opening chat…',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: MessagingSkeleton.brand.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// In-chat loading: mimics header strip, date pill, bubbles, typing dots.
class ChatScreenLoadingSkeleton extends StatelessWidget {
  const ChatScreenLoadingSkeleton({super.key, this.includeHeaderStrip = true});

  final bool includeHeaderStrip;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: MessagingSkeleton.chatBg,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  MessagingSkeleton.chatBg,
                  MessagingSkeleton.peach.withValues(alpha: 0.18),
                ],
              ),
            ),
          ),
        ),
        AppSkeletonShimmer(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
            children: [
              if (includeHeaderStrip) ...const [
                _ChatHeaderStripSkeleton(),
                SizedBox(height: 18),
              ],
              const _DatePillSkeleton(),
              const SizedBox(height: 18),
              const _IncomingBubbleSkeleton(width: 228, lines: 2),
              const SizedBox(height: 12),
              const _IncomingBubbleSkeleton(width: 168, lines: 1),
              const SizedBox(height: 16),
              const _OutgoingBubbleSkeleton(width: 196, lines: 2),
              const SizedBox(height: 14),
              const _OutgoingBubbleSkeleton(width: 124, lines: 1),
              const SizedBox(height: 16),
              const _IncomingBubbleSkeleton(width: 248, lines: 3),
              const SizedBox(height: 18),
              const _TypingIndicatorSkeleton(),
              const SizedBox(height: 8),
              const _LoadingHint(),
            ],
          ),
        ),
      ],
    );
  }
}

/// Legacy alias — conversation-only bubbles (used sparingly).
class ChatConversationSkeleton extends StatelessWidget {
  const ChatConversationSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const ChatScreenLoadingSkeleton();
  }
}

class _ChatHeaderStripSkeleton extends StatelessWidget {
  const _ChatHeaderStripSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: MessagingSkeleton.peachDeep.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: MessagingSkeleton.brand.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const _CuteAvatarBone(size: 44, ringColor: MessagingSkeleton.peachDeep),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSkeletonBox(
                  height: 15,
                  width: 130,
                  radius: 8,
                  color: MessagingSkeleton.bone,
                ),
                SizedBox(height: 7),
                Row(
                  children: [
                    AppSkeletonBox(
                      height: 8,
                      width: 8,
                      radius: 999,
                      color: MessagingSkeleton.peachDeep,
                    ),
                    SizedBox(width: 6),
                    AppSkeletonBox(
                      height: 11,
                      width: 72,
                      radius: 6,
                      color: MessagingSkeleton.boneLight,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const AppSkeletonBox(
            width: 32,
            height: 32,
            radius: 10,
            color: MessagingSkeleton.boneLight,
          ),
        ],
      ),
    );
  }
}

class _DatePillSkeleton extends StatelessWidget {
  const _DatePillSkeleton();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: MessagingSkeleton.bone.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const AppSkeletonBox(
          height: 10,
          width: 52,
          radius: 5,
          color: MessagingSkeleton.boneLight,
        ),
      ),
    );
  }
}

class _IncomingBubbleSkeleton extends StatelessWidget {
  const _IncomingBubbleSkeleton({
    required this.width,
    this.lines = 2,
  });

  final double width;
  final int lines;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const _CuteAvatarBone(size: 30),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CuteBubbleBone(
              width: width,
              lines: lines,
              incoming: true,
            ),
            const SizedBox(height: 5),
            const AppSkeletonBox(
              height: 8,
              width: 32,
              radius: 4,
              color: MessagingSkeleton.boneLight,
            ),
          ],
        ),
      ],
    );
  }
}

class _OutgoingBubbleSkeleton extends StatelessWidget {
  const _OutgoingBubbleSkeleton({
    required this.width,
    this.lines = 2,
  });

  final double width;
  final int lines;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _CuteBubbleBone(
              width: width,
              lines: lines,
              incoming: false,
            ),
            const SizedBox(height: 5),
            const AppSkeletonBox(
              height: 8,
              width: 32,
              radius: 4,
              color: MessagingSkeleton.peach,
            ),
          ],
        ),
      ],
    );
  }
}

class _CuteBubbleBone extends StatelessWidget {
  const _CuteBubbleBone({
    required this.width,
    required this.lines,
    required this.incoming,
  });

  final double width;
  final int lines;
  final bool incoming;

  @override
  Widget build(BuildContext context) {
    final color = incoming ? MessagingSkeleton.cardBg : MessagingSkeleton.peach;
    final borderColor = incoming
        ? MessagingSkeleton.bone
        : MessagingSkeleton.peachDeep.withValues(alpha: 0.6);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: width,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(incoming ? 5 : 18),
              bottomRight: Radius.circular(incoming ? 18 : 5),
            ),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < lines; i++) ...[
                if (i > 0) const SizedBox(height: 7),
                AppSkeletonBox(
                  height: 9,
                  width: i == lines - 1 ? width * 0.55 : width * 0.82,
                  radius: 5,
                  color: incoming
                      ? MessagingSkeleton.boneLight
                      : MessagingSkeleton.peachDeep.withValues(alpha: 0.55),
                ),
              ],
            ],
          ),
        ),
        Positioned(
          bottom: 0,
          left: incoming ? -4 : null,
          right: incoming ? null : -4,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: borderColor),
            ),
          ),
        ),
      ],
    );
  }
}

class _TypingIndicatorSkeleton extends StatelessWidget {
  const _TypingIndicatorSkeleton();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const _CuteAvatarBone(size: 30),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(5),
              bottomRight: Radius.circular(18),
            ),
            border: Border.all(color: MessagingSkeleton.bone),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TypingDot(delay: 0),
              const SizedBox(width: 5),
              _TypingDot(delay: 1),
              const SizedBox(width: 5),
              _TypingDot(delay: 2),
            ],
          ),
        ),
      ],
    );
  }
}

class _TypingDot extends StatelessWidget {
  const _TypingDot({required this.delay});

  final int delay;

  @override
  Widget build(BuildContext context) {
    final sizes = [7.0, 8.0, 7.0];
    return AppSkeletonBox(
      width: sizes[delay % 3],
      height: sizes[delay % 3],
      radius: 999,
      color: delay == 1
          ? MessagingSkeleton.peachDeep
          : MessagingSkeleton.bone,
    );
  }
}

class _LoadingHint extends StatelessWidget {
  const _LoadingHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 16,
            color: MessagingSkeleton.brand.withValues(alpha: 0.55),
          ),
          const SizedBox(width: 6),
          Text(
            'Loading your chat…',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: MessagingSkeleton.brand.withValues(alpha: 0.65),
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Composer ────────────────────────────────────────────────────────────────

class ChatComposerSkeleton extends StatelessWidget {
  const ChatComposerSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppSkeletonShimmer(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: SafeArea(
          top: false,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: MessagingSkeleton.boneLight,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: MessagingSkeleton.bone.withValues(alpha: 0.8),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Icon(
                        Icons.emoji_emotions_outlined,
                        size: 20,
                        color: MessagingSkeleton.bone,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: AppSkeletonBox(
                          height: 12,
                          width: 100,
                          radius: 6,
                          color: MessagingSkeleton.bone,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      MessagingSkeleton.peachDeep,
                      MessagingSkeleton.brand.withValues(alpha: 0.35),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.arrow_upward_rounded,
                  size: 20,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Shared bones ────────────────────────────────────────────────────────────

class _CuteAvatarBone extends StatelessWidget {
  const _CuteAvatarBone({
    this.size = 40,
    this.showOnlineDot = false,
    this.ringColor,
  });

  final double size;
  final bool showOnlineDot;
  final Color? ringColor;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: MessagingSkeleton.bone,
            border: Border.all(
              color: ringColor ?? Colors.white,
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Container(
              width: size * 0.38,
              height: size * 0.38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: MessagingSkeleton.boneLight,
              ),
            ),
          ),
        ),
        if (showOnlineDot)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * 0.28,
              height: size * 0.28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF39C16C),
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

class _CuteProductThumbBone extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: MessagingSkeleton.peach,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: MessagingSkeleton.peachDeep.withValues(alpha: 0.5),
        ),
      ),
      child: Center(
        child: Icon(
          Icons.shopping_bag_outlined,
          size: 22,
          color: MessagingSkeleton.brand.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}
