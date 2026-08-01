// Full-screen story viewer — one merchant's stories, 24h, caption, video, record viewers.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:video_player/video_player.dart';

import 'package:vero360_app/Home/merchant_story_model.dart';
import 'package:vero360_app/Home/story_service.dart';
import 'package:vero360_app/Home/story_ring_widget.dart';
import 'package:vero360_app/Home/MessagePageBackendApi.dart';
import 'package:vero360_app/features/Marketplace/presentation/pages/merchant_products_page.dart';
import 'package:vero360_app/features/Auth/AuthPresenter/login_screen.dart';
import 'package:vero360_app/features/Auth/AuthPresenter/register_screen.dart';
import 'package:vero360_app/GernalServices/backend_chat_service.dart';

class StoryViewerScreen extends StatefulWidget {
  final List<MerchantStoryGroup> groups;
  final int initialGroupIndex;

  const StoryViewerScreen({
    super.key,
    required this.groups,
    required this.initialGroupIndex,
  });

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  int _currentIndex = 0;
  late int _groupIndex;
  late List<MerchantStoryGroup> _groups;
  static const Duration _autoAdvance = Duration(seconds: 8);
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isPaused = false;
  bool _sendingReply = false;
  bool _replyFocused = false;
  late AnimationController _progressController;
  final StoryService _storyService = StoryService();
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocus = FocusNode();

  MerchantStoryGroup get _currentGroup => _groups[_groupIndex];
  List<MerchantStoryItem> get _items => _currentGroup.items;

  bool get _isOwnStory {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid != null && uid == _currentGroup.merchantId;
  }

  @override
  void initState() {
    super.initState();
    _groups = List<MerchantStoryGroup>.from(widget.groups);
    _groupIndex = widget.initialGroupIndex;
    _pageController = PageController();
    _replyFocus.addListener(_onReplyFocusChanged);
    _progressController = AnimationController(
      vsync: this,
      duration: _autoAdvance,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _onAutoAdvance();
        }
      });
    _restartProgress();
    WidgetsBinding.instance.addPostFrameCallback((_) => _recordViewForCurrentSlide());
  }

  void _onReplyFocusChanged() {
    final focused = _replyFocus.hasFocus;
    if (focused == _replyFocused) return;
    setState(() {
      _replyFocused = focused;
      if (focused) {
        _isPaused = true;
        _progressController.stop();
      } else if (!_sendingReply) {
        _isPaused = false;
        _progressController.forward();
      }
    });
  }

  void _recordViewForCurrentSlide() {
    final items = _items;
    if (_currentIndex < 0 || _currentIndex >= items.length) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final viewerName = user.displayName ?? user.email ?? 'Someone';
    final storyId = items[_currentIndex].storyId;
    _storyService.recordView(
      storyId: storyId,
      viewerId: user.uid,
      viewerName: viewerName,
      viewerProfileImageUrl: user.photoURL,
    ).then((_) => _refreshUnviewedState(user.uid));
  }

  Future<void> _refreshUnviewedState(String viewerId) async {
    final group = _currentGroup;
    final hasUnviewed = await _storyService
        .getMerchantStoryRingState(merchantId: group.merchantId, viewerId: viewerId)
        .then((s) => s.hasUnviewed);
    if (!mounted) return;
    setState(() {
      _groups[_groupIndex] = group.copyWith(hasUnviewed: hasUnviewed);
    });
  }

  void _restartProgress() {
    if (_isPaused) {
      _progressController
        ..stop()
        ..reset();
      return;
    }
    _progressController
      ..stop()
      ..reset()
      ..forward();
  }

  void _onAutoAdvance() {
    if (!mounted) return;
    if (_currentIndex < _items.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _goNextStoryGroupOrClose();
    }
  }

  bool _allowTapAdvance() {
    final now = DateTime.now();
    if (now.difference(_lastTap).inMilliseconds < 320) return false;
    _lastTap = now;
    return true;
  }

  void _goNextStoryGroupOrClose() {
    if (_groupIndex < _groups.length - 1) {
      setState(() {
        _groupIndex++;
        _currentIndex = 0;
      });
      _pageController.jumpToPage(0);
      _restartProgress();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _replyFocus.removeListener(_onReplyFocusChanged);
    _replyFocus.dispose();
    _replyController.dispose();
    _progressController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: Text('No story', style: TextStyle(color: Colors.white))),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onLongPressStart: (_) => _progressController.stop(),
        onLongPressEnd: (_) {
          if (!_isPaused) _progressController.forward();
        },
        onTapUp: (details) {
          if (!_allowTapAdvance()) return;
          final w = MediaQuery.of(context).size.width;
          if (details.globalPosition.dx < w * 0.25) {
            if (_currentIndex > 0) {
              _pageController.previousPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            }
          } else if (details.globalPosition.dx > w * 0.75) {
            if (_currentIndex < items.length - 1) {
              _pageController.nextPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            } else {
              _goNextStoryGroupOrClose();
            }
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              onPageChanged: (i) {
                setState(() => _currentIndex = i);
                _restartProgress();
                _recordViewForCurrentSlide();
              },
              itemBuilder: (context, i) {
                final item = items[i];
                return _StoryPage(item: item);
              },
            ),
            SafeArea(
              child: Column(
                children: [
                  _topBar(),
                  const SizedBox(height: 8),
                  _progressBars(items.length),
                ],
              ),
            ),
            Positioned(
              top: 56,
              right: 16,
              child: SafeArea(
                child: InkWell(
                  onTap: () {
                    setState(() => _isPaused = !_isPaused);
                    if (_isPaused) {
                      _progressController.stop();
                    } else {
                      _progressController.forward();
                    }
                  },
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.45),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isPaused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_groups.length > 1 && !_replyFocused) _buildGroupsTray(),
                    if (_groups.length > 1 && !_replyFocused)
                      const SizedBox(height: 8),
                    if (!_isOwnStory) _buildReplyBar(),
                    if (_isOwnStory) const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 28),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MerchantProductsPage(
                    merchantId: _currentGroup.merchantId,
                    merchantName: _currentGroup.merchantName,
                  ),
                ),
              );
            },
            child: Container(
              width: 44,
              height: 44,
              padding: EdgeInsets.all(_currentGroup.hasUnviewed ? 2 : 0),
              decoration: StoryRingDecoration.ring(
                hasStories: true,
                hasUnviewed: _currentGroup.hasUnviewed,
              ),
              child: CircleAvatar(
                radius: 20,
                backgroundColor: Colors.white24,
                backgroundImage: _currentGroup.merchantImageUrl != null
                    ? NetworkImage(_currentGroup.merchantImageUrl!)
                    : null,
                child: _currentGroup.merchantImageUrl == null
                    ? const Icon(Icons.store, color: Colors.white)
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _currentGroup.merchantName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                _timeAgoLabel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressBars(int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: AnimatedBuilder(
        animation: _progressController,
        builder: (context, _) {
          return Row(
            children: List.generate(count, (i) {
              final isPast = i < _currentIndex;
              final isCurrent = i == _currentIndex;
              final value = isPast
                  ? 1.0
                  : isCurrent
                      ? _progressController.value
                      : 0.0;
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  height: 3,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: value.clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }

  Widget _buildGroupsTray() {
    return SizedBox(
      height: 78,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _groups.length,
        itemBuilder: (context, i) {
          final g = _groups[i];
          final isActive = i == _groupIndex;
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: GestureDetector(
              onTap: () {
                if (i == _groupIndex) return;
                setState(() {
                  _groupIndex = i;
                  _currentIndex = 0;
                });
                _pageController.jumpToPage(0);
                _restartProgress();
                _recordViewForCurrentSlide();
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: isActive
                        ? BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          )
                        : null,
                    child: Container(
                      padding: EdgeInsets.all(g.hasUnviewed ? 2.5 : 1.5),
                      decoration: StoryRingDecoration.ring(
                        hasStories: true,
                        hasUnviewed: g.hasUnviewed,
                      ),
                      child: ClipOval(
                        child: g.merchantImageUrl != null &&
                                g.merchantImageUrl!.isNotEmpty
                            ? Image.network(
                                g.merchantImageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: Colors.white24,
                                  child: const Icon(Icons.store,
                                      color: Colors.white, size: 20),
                                ),
                              )
                            : Container(
                                color: Colors.white24,
                                child: const Icon(Icons.store,
                                    color: Colors.white, size: 20),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 56,
                    child: Text(
                      g.merchantName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 10,
                        fontWeight:
                            isActive ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _timeAgoLabel() {
    if (_items.isEmpty) {
      return const SizedBox.shrink();
    }
    final item =
        _items[_currentIndex.clamp(0, _items.length - 1)];
    final now = DateTime.now();
    final diff = now.difference(item.createdAt);
    String text;
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes.clamp(1, 59);
      text = '${m}m ago';
    } else if (diff.inHours < 24) {
      final h = diff.inHours;
      text = '${h}h ago';
    } else {
      final d = diff.inDays;
      text = '${d}d ago';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildReplyBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _replyController,
              focusNode: _replyFocus,
              enabled: !_sendingReply,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendStoryReply(),
              style: const TextStyle(color: Colors.white, fontSize: 15),
              cursorColor: const Color(0xFFFF8A00),
              decoration: InputDecoration(
                hintText: 'Reply to ${_currentGroup.merchantName}…',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 14,
                ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.14),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.28),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.28),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: const BorderSide(color: Color(0xFFFF8A00)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: const Color(0xFFFF8A00),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _sendingReply ? null : _sendStoryReply,
              child: SizedBox(
                width: 46,
                height: 46,
                child: Center(
                  child: _sendingReply
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendStoryReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty || _sendingReply || _isOwnStory) return;
    if (_items.isEmpty) return;

    // Guests can view stories, but inbox replies need an account.
    if (FirebaseAuth.instance.currentUser == null) {
      _replyFocus.unfocus();
      await _promptLoginToReply();
      return;
    }

    final item = _items[_currentIndex.clamp(0, _items.length - 1)];
    final merchantId = _currentGroup.merchantId.trim();
    if (merchantId.isEmpty) return;

    setState(() {
      _sendingReply = true;
      _isPaused = true;
    });
    _progressController.stop();
    _replyFocus.unfocus();

    try {
      final result = await BackendChatService.startMerchantChat(
        merchantId: merchantId,
      );

      final caption = item.caption?.trim();
      final content = (caption != null && caption.isNotEmpty)
          ? '↩️ Story reply:\n"$caption"\n\n$text'
          : '↩️ Story reply:\n\n$text';

      await BackendChatService.sendMessage(
        chatId: result.chat.id,
        content: content,
        type: 'text',
        metadata: {
          'source': 'story_reply',
          'storyId': item.storyId,
          'merchantId': merchantId,
          if (caption != null && caption.isNotEmpty) 'storyCaption': caption,
        },
      );

      if (!mounted) return;
      _replyController.clear();

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MessagePageBackendApi(
            peerId: result.chat.id,
            peerName: _currentGroup.merchantName,
            peerAvatarUrl: _currentGroup.merchantImageUrl,
            peerMerchantId: merchantId,
            peerUserId: result.sellerId,
          ),
        ),
      );

      if (!mounted) return;
      // Close story after opening inbox so user lands back on home/inbox flow.
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      final lower = raw.toLowerCase();
      if (lower.contains('not authenticated') ||
          lower.contains('unauthorized') ||
          lower.contains('401')) {
        await _promptLoginToReply();
        if (mounted) {
          setState(() {
            _sendingReply = false;
            _isPaused = false;
          });
          _progressController.forward();
        }
        return;
      }
      final message = raw.contains('own listing') ||
              raw.contains('cannot chat with yourself') ||
              raw.contains('cannot chat with ur self')
          ? 'You can’t reply to your own story.'
          : raw.contains('could not find') ||
                  raw.contains('not linked') ||
                  raw.contains('User ') && raw.contains('not found')
              ? 'Couldn’t open inbox — this merchant’s account isn’t linked for chat yet.'
              : 'Couldn’t send reply. Check your connection and try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (mounted) {
        setState(() {
          _sendingReply = false;
          _isPaused = false;
        });
        _progressController.forward();
      }
    }
  }

  Future<void> _promptLoginToReply() async {
    setState(() {
      _isPaused = true;
    });
    _progressController.stop();

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Login required'),
        content: const Text(
          'Sign in to reply to this story in your inbox.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'login'),
            child: const Text('Login'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'signup'),
            child: const Text('Sign Up'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (action == 'login') {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    } else if (action == 'signup') {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const RegisterScreen()),
      );
    }

    if (!mounted) return;
    setState(() => _isPaused = false);
    if (!_replyFocused) _progressController.forward();
  }
}

class _StoryPage extends StatefulWidget {
  final MerchantStoryItem item;

  const _StoryPage({required this.item});

  @override
  State<_StoryPage> createState() => _StoryPageState();
}

class _StoryPageState extends State<_StoryPage> {
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    if (widget.item.mediaType == 'video' && widget.item.mediaUrl.trim().isNotEmpty) {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(widget.item.mediaUrl))
        ..initialize().then((_) {
          if (mounted) {
            _videoController!.setLooping(true);
            _videoController!.play();
            setState(() {});
          }
        }).catchError((_) {
          if (mounted) setState(() {});
        });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildMedia(item),
        if (item.caption != null && item.caption!.trim().isNotEmpty)
          Positioned(
            left: 16,
            right: 16,
            bottom: 88,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  item.caption!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMedia(MerchantStoryItem item) {
    if (item.mediaType == 'video') {
      if (_videoController == null) {
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      }
      if (!_videoController!.value.isInitialized) {
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      }
      return Center(
        child: AspectRatio(
          aspectRatio: _videoController!.value.aspectRatio,
          child: VideoPlayer(_videoController!),
        ),
      );
    }
    if (item.hasInlineImage && item.imageBase64 != null) {
      try {
        final bytes = base64Decode(item.imageBase64!);
        return Center(
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Center(
              child: Text('Unable to load', style: TextStyle(color: Colors.white)),
            ),
          ),
        );
      } catch (_) {
        return const Center(
          child: Text('Unable to load', style: TextStyle(color: Colors.white)),
        );
      }
    }
    if (item.mediaUrl.isNotEmpty) {
      return Center(
        child: Image.network(
          item.mediaUrl,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Center(
            child: Text('Unable to load', style: TextStyle(color: Colors.white)),
          ),
        ),
      );
    }
    return const Center(
      child: Text('No media', style: TextStyle(color: Colors.white)),
    );
  }
}
