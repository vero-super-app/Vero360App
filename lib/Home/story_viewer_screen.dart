// Full-screen story viewer — one merchant's stories, 24h, caption, video, record viewers.

import 'dart:async';
import 'package:universal_io/io.dart';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import 'package:vero360_app/Home/merchant_story_model.dart';
import 'package:vero360_app/Home/story_service.dart';
import 'package:vero360_app/Home/story_ring_widget.dart';
import 'package:vero360_app/Home/MessagePageBackendApi.dart';
import 'package:vero360_app/features/Reels/reel_video_cache.dart';
import 'package:vero360_app/utils/profile_open_helper.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/features/Auth/AuthPresenter/login_screen.dart';
import 'package:vero360_app/features/Auth/AuthPresenter/register_screen.dart';
import 'package:vero360_app/GernalServices/backend_chat_service.dart';
import 'package:vero360_app/utils/display_name_sync.dart';

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
  static const Duration _maxVideoAdvance = Duration(seconds: 60);
  final Map<String, Duration> _videoDurations = {};
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isPaused = false;
  bool _sendingReply = false;
  bool _replyFocused = false;
  Uint8List? _replyImageBytes;
  String? _replyVideoPath;
  MerchantChatResult? _warmChat;
  String? _warmMerchantId;
  final ImagePicker _replyPicker = ImagePicker();
  bool _deleting = false;
  int _ownViewerCount = 0;
  int _likeCount = 0;
  bool _liked = false;
  String? _likeWatchStoryId;
  bool? _expectMineLiked;
  StreamSubscription<StoryLikeState>? _likeSub;
  bool _likeBusy = false;
  late AnimationController _progressController;
  final StoryService _storyService = StoryService();
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocus = FocusNode();

  MerchantStoryGroup get _currentGroup => _groups[_groupIndex];
  List<MerchantStoryItem> get _items => _currentGroup.items;

  /// Food stories open the kitchen menu, not the marketplace shop.
  String? get _ownerServiceType {
    for (final it in _items) {
      final st = (it.serviceType ?? '').trim().toLowerCase();
      if (st == 'food') return 'food';
    }
    if (_items.isEmpty) return null;
    final i = _currentIndex.clamp(0, _items.length - 1);
    return _items[i].serviceType;
  }

  void _openOwnerProfile() {
    openMerchantOrDriverProfile(
      context,
      profileId: _currentGroup.merchantId,
      displayName: _ownerDisplayName,
      serviceType: _ownerServiceType,
    );
  }

  bool get _isOwnStory {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid != null && uid == _currentGroup.merchantId;
  }

  /// Story owner label — merchants always show business name (including own).
  String get _ownerDisplayName {
    final name = _currentGroup.merchantName.trim();
    if (name.isEmpty) return _isOwnStory ? 'My status' : 'Merchant';
    if (!_isOwnStory) return name;

    final st = (_items.isNotEmpty ? _items.first.serviceType : null)
        ?.toLowerCase()
        .trim();
    final isMerchantStory = st == null ||
        st.isEmpty ||
        st == 'marketplace' ||
        st == 'food' ||
        st == 'accommodation' ||
        st == 'courier' ||
        st == 'merchant';
    if (isMerchantStory && name.toLowerCase() != 'you') return name;
    return 'My status';
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prefetchUpcoming();
      _recordViewForCurrentSlide();
      _hydrateOwnerBusinessNames();
      _warmReplyChat();
    });
  }

  /// Ensure merchant story headers use live business name, not personal name.
  Future<void> _hydrateOwnerBusinessNames() async {
    try {
      final refreshed =
          await _storyService.resolveLiveMerchantNamesForGroups(_groups);
      if (!mounted || refreshed.isEmpty) return;
      setState(() {
        _groups = refreshed;
      });
    } catch (_) {}

    // Own merchant story: force acting business name from prefs/shop.
    if (!_isOwnStory) return;
    try {
      final biz = await DisplayNameSync.resolveActingDisplayName(fallback: '');
      if (!mounted || biz.trim().isEmpty) return;
      final g = _currentGroup;
      if (g.merchantName.trim() == biz.trim()) return;
      setState(() {
        _groups[_groupIndex] = g.copyWith(merchantName: biz.trim());
      });
    } catch (_) {}
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
    _bindLikeWatch();
    if (_isOwnStory) {
      _loadOwnViewerCount();
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final storyId = items[_currentIndex].storyId;
    final viewerName = user.displayName ?? user.email ?? 'Someone';
    _storyService.recordView(
      storyId: storyId,
      viewerId: user.uid,
      viewerName: viewerName,
      viewerProfileImageUrl: user.photoURL,
    ).then((_) => _refreshUnviewedState(user.uid));
  }

  Future<void> _loadOwnViewerCount() async {
    if (!_isOwnStory) return;
    final items = _items;
    if (_currentIndex < 0 || _currentIndex >= items.length) return;
    final storyId = items[_currentIndex].storyId;
    try {
      final viewers = await _storyService.getStoryViewers(storyId);
      if (!mounted) return;
      if (_likeWatchStoryId != storyId) return;
      setState(() {
        _ownViewerCount = viewers.length;
      });
    } catch (_) {}
  }

  Future<void> _showOwnViewersSheet() async {
    final items = _items;
    if (_currentIndex < 0 || _currentIndex >= items.length) return;
    _progressController.stop();
    setState(() => _isPaused = true);
    final storyId = items[_currentIndex].storyId;
    List<StoryViewerInfo> viewers = const [];
    try {
      viewers = await _storyService.getStoryViewers(storyId);
    } catch (_) {}
    if (!mounted) return;
    await showStoryViewersSheet(context, viewers);
    if (!mounted) return;
    setState(() {
      _ownViewerCount = viewers.length;
      _isPaused = false;
    });
    _progressController.forward();
  }

  Future<void> _confirmDeleteCurrentStory() async {
    if (!_isOwnStory || _deleting) return;
    final items = _items;
    if (_currentIndex < 0 || _currentIndex >= items.length) return;
    _progressController.stop();
    setState(() => _isPaused = true);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete status?'),
        content: const Text(
          'This status will be removed for everyone. You can’t undo this.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) {
      if (mounted) {
        setState(() => _isPaused = false);
        _progressController.forward();
      }
      return;
    }

    final item = items[_currentIndex];
    setState(() => _deleting = true);
    try {
      await _storyService.deleteStory(item.storyId);
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Status deleted',
        isSuccess: true,
        errorMessage: '',
      );
      final remaining = List<MerchantStoryItem>.from(_items)
        ..removeWhere((e) => e.storyId == item.storyId);
      if (remaining.isEmpty) {
        final nextGroups = List<MerchantStoryGroup>.from(_groups)
          ..removeAt(_groupIndex);
        if (nextGroups.isEmpty) {
          Navigator.of(context).pop();
          return;
        }
        final nextIndex = _groupIndex.clamp(0, nextGroups.length - 1);
        setState(() {
          _groups = nextGroups;
          _groupIndex = nextIndex;
          _currentIndex = 0;
          _deleting = false;
          _isPaused = false;
        });
        _pageController.jumpToPage(0);
        _restartProgress();
        _recordViewForCurrentSlide();
        return;
      }
      final nextIndex = _currentIndex.clamp(0, remaining.length - 1);
      setState(() {
        _groups[_groupIndex] = _currentGroup.copyWith(items: remaining);
        _currentIndex = nextIndex;
        _deleting = false;
        _isPaused = false;
      });
      _pageController.jumpToPage(nextIndex);
      _restartProgress();
      _recordViewForCurrentSlide();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _isPaused = false;
      });
      _progressController.forward();
      ToastHelper.showCustomToast(
        context,
        'Could not delete status',
        isSuccess: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> _refreshUnviewedState(String viewerId) async {
    final group = _currentGroup;
    final hasUnviewed = await _storyService
        .getMerchantStoryRingState(merchantId: group.merchantId, viewerId: viewerId)
        .then((s) => s.hasUnviewed);
    if (!mounted) return;
    if (group.hasUnviewed == hasUnviewed) return;
    setState(() {
      _groups[_groupIndex] = group.copyWith(hasUnviewed: hasUnviewed);
    });
  }

  void _warmReplyChat() {
    if (_isOwnStory) return;
    final merchantId = _currentGroup.merchantId.trim();
    if (merchantId.isEmpty) return;
    if (FirebaseAuth.instance.currentUser == null) return;
    if (_warmMerchantId == merchantId && _warmChat != null) return;
    _warmMerchantId = merchantId;
    _warmChat = null;
    BackendChatService.startMerchantChat(merchantId: merchantId).then((result) {
      if (!mounted) return;
      if (_currentGroup.merchantId.trim() != merchantId) return;
      _warmChat = result;
    }).catchError((_) {});
  }

  void _onVideoReady(String storyId, Duration length) {
    if (!mounted) return;
    final wasReady = _readyVideos.contains(storyId);
    _readyVideos.add(storyId);
    if (length > Duration.zero) {
      final capped = length > _maxVideoAdvance ? _maxVideoAdvance : length;
      if (_videoDurations[storyId] == capped && wasReady) return;
      _videoDurations[storyId] = capped;
    } else if (wasReady) {
      return;
    }
    final items = _items;
    if (_currentIndex >= 0 &&
        _currentIndex < items.length &&
        items[_currentIndex].storyId == storyId) {
      _restartProgress();
    }
  }

  /// Video stories that have loaded; the progress bar waits for these so a
  /// slow network doesn't skip a story before it is seen.
  final Set<String> _readyVideos = <String>{};

  /// Downloads the next two stories and the next person's first story.
  void _prefetchUpcoming() {
    final cache = ReelVideoCache.stories;
    final items = _items;
    for (var j = _currentIndex + 1; j <= _currentIndex + 2 && j < items.length; j++) {
      final it = items[j];
      if (it.mediaType == 'video') cache.prefetch(it.mediaUrl.trim());
    }
    if (_groupIndex + 1 < _groups.length) {
      final next = _groups[_groupIndex + 1].items;
      if (next.isNotEmpty && next.first.mediaType == 'video') {
        cache.prefetch(next.first.mediaUrl.trim());
      }
    }
  }

  void _restartProgress() {
    final items = _items;
    final current = _currentIndex >= 0 && _currentIndex < items.length
        ? items[_currentIndex]
        : null;
    final storyId = current?.storyId;
    _progressController.duration =
        (storyId == null ? null : _videoDurations[storyId]) ?? _autoAdvance;
    final waitingForVideo = current != null &&
        current.mediaType == 'video' &&
        current.mediaUrl.trim().isNotEmpty &&
        !_readyVideos.contains(current.storyId);
    if (_isPaused || waitingForVideo) {
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

  /// Timer finished. Video stories advance when the clip actually ends
  /// (see [_onVideoEnded]); this is only a fallback if that event never comes.
  void _onAutoAdvance() {
    if (!mounted) return;
    final items = _items;
    final current = _currentIndex >= 0 && _currentIndex < items.length
        ? items[_currentIndex]
        : null;
    final isVideo = current != null &&
        current.mediaType == 'video' &&
        current.mediaUrl.trim().isNotEmpty &&
        _readyVideos.contains(current.storyId);
    final cappedLong = current != null &&
        (_videoDurations[current.storyId] ?? Duration.zero) >= _maxVideoAdvance;
    if (isVideo && !cappedLong) {
      final id = current.storyId;
      _endFallback?.cancel();
      _endFallback = Timer(const Duration(milliseconds: 1200), () {
        if (mounted && _items.isNotEmpty && _currentStoryId == id) _advance();
      });
      return;
    }
    _advance();
  }

  Timer? _endFallback;

  String? get _currentStoryId {
    final items = _items;
    if (_currentIndex < 0 || _currentIndex >= items.length) return null;
    return items[_currentIndex].storyId;
  }

  void _onVideoEnded(String storyId) {
    if (!mounted || _isPaused || _replyFocused || _sendingReply) return;
    if (_currentStoryId != storyId) return;
    _advance();
  }

  /// Instant cut to the next story (no slide): sliding over a native video
  /// view flashes black on Android.
  void _advance() {
    if (!mounted) return;
    _endFallback?.cancel();
    if (_currentIndex < _items.length - 1) {
      _pageController.jumpToPage(_currentIndex + 1);
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
      _warmReplyChat();
      _prefetchUpcoming();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _bindLikeWatch() {
    final items = _items;
    if (_currentIndex < 0 || _currentIndex >= items.length) return;
    final storyId = items[_currentIndex].storyId;
    if (storyId.isEmpty || storyId == _likeWatchStoryId) return;
    _likeWatchStoryId = storyId;
    _likeSub?.cancel();
    _likeSub = null;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final cachedMine = uid == null ? null : StoryService.peekMyLike(uid, storyId);
    if (!_isOwnStory) {
      setState(() {
        if (!_likeBusy) _liked = cachedMine ?? false;
      });
      if (uid == null) return;
      _storyService.viewerHasLiked(storyId: storyId, viewerId: uid).then((liked) {
        if (!mounted || _likeWatchStoryId != storyId || _likeBusy) return;
        if (_expectMineLiked != null && liked != _expectMineLiked) return;
        setState(() {
          _expectMineLiked = null;
          _liked = liked;
        });
      });
      return;
    }
    final cachedCount = StoryService.peekLikeCount(storyId);
    setState(() {
      _likeCount = cachedCount ?? 0;
      if (!_likeBusy) _liked = cachedMine ?? false;
    });
    _likeSub = _storyService
        .watchStoryLikes(storyId: storyId, viewerId: uid)
        .listen((state) {
      if (!mounted || _likeWatchStoryId != storyId || _likeBusy) return;
      if (_expectMineLiked != null && state.mineLiked != _expectMineLiked) {
        return;
      }
      setState(() {
        _expectMineLiked = null;
        _likeCount = state.likeCount;
        _liked = state.mineLiked;
      });
    });
  }

  @override
  void dispose() {
    _endFallback?.cancel();
    _likeSub?.cancel();
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
        onVerticalDragEnd: (details) {
          if (!_isOwnStory) return;
          final velocity = details.primaryVelocity ?? 0;
          if (velocity < -280) _showOwnViewersSheet();
        },
        onTapUp: (details) {
          if (!_allowTapAdvance()) return;
          final w = MediaQuery.of(context).size.width;
          if (details.globalPosition.dx < w * 0.25) {
            if (_currentIndex > 0) {
              _endFallback?.cancel();
              _pageController.jumpToPage(_currentIndex - 1);
            }
          } else if (details.globalPosition.dx > w * 0.75) {
            _advance();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              // Builds the next story so its video is ready before the tap.
              allowImplicitScrolling: true,
              itemCount: items.length,
              onPageChanged: (i) {
                _endFallback?.cancel();
                setState(() => _currentIndex = i);
                _restartProgress();
                _recordViewForCurrentSlide();
                _prefetchUpcoming();
              },
              itemBuilder: (context, i) {
                final item = items[i];
                return _StoryPage(
                  key: ValueKey(item.storyId),
                  item: item,
                  active: i == _currentIndex,
                  onVideoReady: (d) => _onVideoReady(item.storyId, d),
                  onVideoEnded: () => _onVideoEnded(item.storyId),
                );
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
                    if (!_isOwnStory) _buildReplyBar(),
                    if (_isOwnStory) _buildOwnStoryBar(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOwnStoryBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: _showOwnViewersSheet,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.visibility_rounded,
                          color: Colors.white, size: 22),
                      const SizedBox(width: 8),
                      Flexible(
                          child: Text(
                            '$_ownViewerCount view${_ownViewerCount == 1 ? '' : 's'} · $_likeCount like${_likeCount == 1 ? '' : 's'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      const SizedBox(width: 6),
                      Text(
                        'Swipe up',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      Icon(
                        Icons.keyboard_arrow_up_rounded,
                        color: Colors.white.withValues(alpha: 0.8),
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Delete status',
              onPressed: _deleting ? null : _confirmDeleteCurrentStory,
              icon: _deleting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.delete_outline_rounded,
                      color: Colors.white, size: 24),
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
            onTap: _openOwnerProfile,
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
            child: GestureDetector(
              onTap: _openOwnerProfile,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _ownerDisplayName,
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
          ),
          if (_isOwnStory)
            IconButton(
              tooltip: 'Delete',
              onPressed: _deleting ? null : _confirmDeleteCurrentStory,
              icon: const Icon(Icons.delete_outline_rounded,
                  color: Colors.white, size: 24),
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

  Future<void> _toggleLike() async {
    if (_likeBusy || _isOwnStory || _items.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await _promptLoginToReply();
      return;
    }
    final storyId = _items[_currentIndex.clamp(0, _items.length - 1)].storyId;
    final wasLiked = _liked;
    final next = !wasLiked;
    final previousCount = _likeCount;
    _expectMineLiked = next;
    setState(() {
      _liked = next;
      _likeBusy = true;
      if (next && !wasLiked) _likeCount++;
      if (!next && wasLiked && _likeCount > 0) _likeCount--;
    });
    try {
      final name = await DisplayNameSync.resolveActingDisplayName(
        fallback: user.displayName ?? user.email ?? 'Someone',
      );
      await _storyService.setStoryLiked(
        storyId: storyId,
        viewerId: user.uid,
        viewerName: name,
        viewerProfileImageUrl: user.photoURL,
        liked: next,
      );
      if (!mounted) return;
      final saved = StoryService.peekLikeCount(storyId);
      setState(() {
        _likeBusy = false;
        _liked = next;
        if (saved != null) _likeCount = saved;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _likeBusy = false;
        _expectMineLiked = null;
        _liked = wasLiked;
        _likeCount = previousCount;
      });
    }
  }

  Widget _likeButton() {
    return Material(
      color: Colors.white.withValues(alpha: 0.14),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _likeBusy ? null : _toggleLike,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Icon(
            _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: _liked ? const Color(0xFFFF2D55) : Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }

  Widget _buildReplyBar() {
    final hasImage = _replyImageBytes != null;
    final hasVideo = _replyVideoPath != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasImage || hasVideo)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 54, bottom: 8),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: hasImage
                          ? Image.memory(
                              _replyImageBytes!,
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            )
                          : Container(
                              width: 72,
                              height: 72,
                              color: Colors.black,
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.play_circle_fill_rounded,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                    ),
                    Positioned(
                      top: -6,
                      right: -6,
                      child: Material(
                        color: Colors.black87,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _sendingReply
                              ? null
                              : () => setState(() {
                                    _replyImageBytes = null;
                                    _replyVideoPath = null;
                                  }),
                          child: const SizedBox(
                            width: 22,
                            height: 22,
                            child: Icon(Icons.close, color: Colors.white, size: 14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Row(
        children: [
          _likeButton(),
          const SizedBox(width: 8),
          Material(
            color: Colors.white.withValues(alpha: 0.14),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _sendingReply ? null : _pickReplyMedia,
              child: const SizedBox(
                width: 46,
                height: 46,
                child: Icon(Icons.perm_media_outlined, color: Colors.white, size: 22),
              ),
            ),
          ),
          const SizedBox(width: 8),
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
                hintText: 'Reply to ${_ownerDisplayName}…',
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
        ],
      ),
    );
  }

  Widget _replySourceRow(
    BuildContext ctx, {
    required String choice,
    required Color color,
    required IconData icon,
    required String label,
  }) {
    return InkWell(
      onTap: () => Navigator.pop(ctx, choice),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF222222),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickReplyMedia() async {
    _progressController.stop();
    setState(() => _isPaused = true);
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _replySourceRow(
                ctx,
                choice: 'photo_camera',
                color: const Color(0xFFFF8A00),
                icon: Icons.photo_camera_outlined,
                label: 'Take a photo',
              ),
              _replySourceRow(
                ctx,
                choice: 'photo',
                color: const Color(0xFF1E88E5),
                icon: Icons.photo_library_outlined,
                label: 'Choose from gallery',
              ),
              _replySourceRow(
                ctx,
                choice: 'video_camera',
                color: const Color(0xFF111111),
                icon: Icons.videocam_outlined,
                label: 'Record a video',
              ),
              _replySourceRow(
                ctx,
                choice: 'video',
                color: const Color(0xFF111111),
                icon: Icons.video_library_outlined,
                label: 'Choose a video',
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'photo' || choice == 'photo_camera') {
      try {
        final file = await _replyPicker.pickImage(
          source: choice == 'photo_camera'
              ? ImageSource.camera
              : ImageSource.gallery,
          maxWidth: 1600,
          imageQuality: 85,
        );
        if (file == null || !mounted) {
          _resumeAfterReplyPick();
          return;
        }
        final raw = await file.readAsBytes();
        final prepared = await StoryService.prepareStoryImageBytes(
          Uint8List.fromList(raw),
          maxEdge: 1280,
          maxBytes: 450000,
        );
        if (!mounted) return;
        setState(() {
          _replyImageBytes = prepared;
          _replyVideoPath = null;
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not add that photo. $e')),
          );
        }
      }
    } else if (choice == 'video' || choice == 'video_camera') {
      try {
        final file = await _replyPicker.pickVideo(
          source: choice == 'video_camera'
              ? ImageSource.camera
              : ImageSource.gallery,
          maxDuration: const Duration(minutes: 2),
        );
        if (file == null || !mounted) {
          _resumeAfterReplyPick();
          return;
        }
        final length = await File(file.path).length();
        if (length > 40 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('That video is too large. Choose one under 40 MB.'),
              ),
            );
          }
          _resumeAfterReplyPick();
          return;
        }
        setState(() {
          _replyVideoPath = file.path;
          _replyImageBytes = null;
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not add that video. $e')),
          );
        }
      }
    }
    _resumeAfterReplyPick();
  }

  void _resumeAfterReplyPick() {
    if (!mounted || _sendingReply || _replyFocused) return;
    setState(() => _isPaused = false);
    _progressController.forward();
  }

  Future<void> _sendStoryReply() async {
    final text = _replyController.text.trim();
    final hasImage = _replyImageBytes != null && _replyImageBytes!.isNotEmpty;
    final hasVideo = _replyVideoPath != null && _replyVideoPath!.isNotEmpty;
    if ((text.isEmpty && !hasImage && !hasVideo) || _sendingReply || _isOwnStory) {
      return;
    }
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
      final result = (_warmChat != null && _warmMerchantId == merchantId)
          ? _warmChat!
          : await BackendChatService.startMerchantChat(
              merchantId: merchantId,
            );
      _warmChat = result;
      _warmMerchantId = merchantId;

      final caption = item.caption?.trim();
      final metadata = <String, dynamic>{
        'source': 'story_reply',
        'storyId': item.storyId,
        'merchantId': merchantId,
        if (caption != null && caption.isNotEmpty) 'storyCaption': caption,
        if (item.mediaUrl.trim().isNotEmpty) 'storyMediaUrl': item.mediaUrl.trim(),
        'storyMediaType': item.mediaType,
      };

      if (hasImage) {
        final url = await BackendChatService.uploadChatAttachment(
          bytes: _replyImageBytes!,
          filename: 'story-reply.jpg',
          mimeType: 'image/jpeg',
        );
        await BackendChatService.sendImageMessage(
          chatId: result.chat.id,
          imageUrl: url,
          caption: text,
          metadata: metadata,
        );
      } else if (hasVideo) {
        final path = _replyVideoPath!;
        final ref = FirebaseStorage.instance.ref().child(
          'chat_media/story_replies/'
          '${DateTime.now().millisecondsSinceEpoch}.mp4',
        );
        await ref.putFile(
          File(path),
          SettableMetadata(contentType: 'video/mp4'),
        );
        final url = await ref.getDownloadURL();
        await BackendChatService.sendVideoMessage(
          chatId: result.chat.id,
          videoUrl: url,
          caption: text,
          metadata: metadata,
        );
      } else {
        final content = (caption != null && caption.isNotEmpty)
            ? '↩️ Story reply:\n"$caption"\n\n$text'
            : '↩️ Story reply:\n\n$text';
        await BackendChatService.sendMessage(
          chatId: result.chat.id,
          content: content,
          type: 'text',
          metadata: metadata,
        );
      }

      if (!mounted) return;
      _replyController.clear();
      _replyImageBytes = null;
      _replyVideoPath = null;

      final myId = BackendChatService.peekUserId() ?? 0;
      var peerName = _ownerDisplayName.trim();
      if (ChatParticipant.isPlaceholderName(peerName)) {
        final fromThread =
            BackendChatService.peerDisplayNameForThread(result.chat, myId);
        if (!ChatParticipant.isPlaceholderName(fromThread)) {
          peerName = fromThread;
        }
      }
      final other = result.chat.otherParticipant(myId);
      if (other != null && !ChatParticipant.isPlaceholderName(peerName)) {
        BackendChatService.rememberPeerDisplayName(other, peerName);
      }

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MessagePageBackendApi(
            peerId: result.chat.id,
            peerName: peerName,
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
  final bool active;
  final ValueChanged<Duration>? onVideoReady;
  final VoidCallback? onVideoEnded;

  const _StoryPage({
    super.key,
    required this.item,
    required this.active,
    this.onVideoReady,
    this.onVideoEnded,
  });

  @override
  State<_StoryPage> createState() => _StoryPageState();
}

class _StoryPageState extends State<_StoryPage>
    with AutomaticKeepAliveClientMixin {
  VideoPlayerController? _videoController;
  Uint8List? _inlineBytes;
  bool _videoReady = false;
  bool _videoFailed = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _inlineBytes = StoryInlineImageCache.bytesFor(
      widget.item.storyId,
      widget.item.imageBase64,
    );
    final url = widget.item.mediaUrl.trim();
    if (widget.item.mediaType != 'video' && url.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        precacheImage(NetworkImage(url), context);
      });
    }
    if (widget.item.mediaType == 'video') {
      if (url.isEmpty) {
        _videoFailed = true;
      } else {
        _startVideo(url);
      }
    }
  }

  /// Android uses a native view: the default texture path renders black on
  /// some devices running the Skia renderer (Impeller is off in the manifest).
  /// Plays the cached copy when the story was prefetched or seen before
  /// (instant, offline); otherwise streams while caching in the background.
  Future<void> _startVideo(String url) async {
    final cache = ReelVideoCache.stories;
    final file = cache.cachedSync(url) ?? await cache.cached(url);
    if (!mounted || _videoController != null) return;
    final viewType = defaultTargetPlatform == TargetPlatform.android
        ? VideoViewType.platformView
        : VideoViewType.textureView;
    final controller = file != null
        ? VideoPlayerController.file(file, viewType: viewType)
        : VideoPlayerController.networkUrl(Uri.parse(url), viewType: viewType);
    if (file == null) cache.prefetch(url, priority: widget.active);
    _videoController = controller;
    try {
      await controller.initialize();
      if (!mounted || _videoController != controller) return;
      // No looping: the clip stops on its last frame and the viewer cuts to
      // the next story, instead of flashing the start again.
      await controller.setLooping(false);
      controller.addListener(() => _watchEnd(controller));
      if (widget.active) await controller.play();
      if (!mounted || _videoController != controller) return;
      setState(() {
        _videoReady = true;
        _videoFailed = false;
      });
      widget.onVideoReady?.call(controller.value.duration);
    } catch (e) {
      if (kDebugMode) debugPrint('[StoryViewer] video failed: $e');
      if (!mounted || _videoController != controller) return;
      if (!_autoRetried) {
        // One silent retry: the cached copy may have finished meanwhile.
        _autoRetried = true;
        _videoController = null;
        unawaited(controller.dispose());
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (mounted) unawaited(_startVideo(url));
        return;
      }
      setState(() {
        _videoReady = false;
        _videoFailed = true;
      });
      // Let the progress bar run so a broken video doesn't freeze the viewer.
      widget.onVideoReady?.call(Duration.zero);
    }
  }

  bool _autoRetried = false;
  bool _ended = false;

  void _watchEnd(VideoPlayerController controller) {
    if (_videoController != controller || !widget.active || _ended) return;
    final v = controller.value;
    if (!v.isInitialized || v.duration <= Duration.zero) return;
    if (v.position >= v.duration - const Duration(milliseconds: 150) && !v.isPlaying) {
      _ended = true;
      widget.onVideoEnded?.call();
    }
  }

  void _retryVideo() {
    final url = widget.item.mediaUrl.trim();
    if (url.isEmpty) return;
    final old = _videoController;
    _videoController = null;
    old?.dispose();
    _autoRetried = false;
    setState(() {
      _videoReady = false;
      _videoFailed = false;
    });
    _startVideo(url);
  }

  @override
  void didUpdateWidget(covariant _StoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    if (widget.active && !oldWidget.active) {
      _ended = false;
      controller.seekTo(Duration.zero);
      controller.play();
    } else if (widget.active && !controller.value.isPlaying && !_ended) {
      controller.play();
    } else if (!widget.active && controller.value.isPlaying) {
      controller.pause();
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
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
      final controller = _videoController;
      return ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (controller != null && _videoReady && controller.value.isInitialized)
              Center(
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio == 0
                      ? 9 / 16
                      : controller.value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
              ),
            if (_videoFailed)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Unable to play this video',
                      style: TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _retryVideo,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white70),
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            else if (!_videoReady)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
          ],
        ),
      );
    }
    final inline = _inlineBytes;
    if (inline != null) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Image.memory(
            inline,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => const Center(
              child: Text('Unable to load', style: TextStyle(color: Colors.white)),
            ),
          ),
        ),
      );
    }
    if (item.mediaUrl.isNotEmpty) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Image.network(
            item.mediaUrl,
            key: ValueKey(item.mediaUrl),
            fit: BoxFit.contain,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => const Center(
              child: Text('Unable to load', style: TextStyle(color: Colors.white)),
            ),
          ),
        ),
      );
    }
    return const Center(
      child: Text('No media', style: TextStyle(color: Colors.white)),
    );
  }
}

Future<void> showStoryViewersSheet(
  BuildContext context,
  List<StoryViewerInfo> viewers,
) {
  final screenHeight = MediaQuery.sizeOf(context).height;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      return SizedBox(
        height: screenHeight,
        child: DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.32,
          maxChildSize: 0.92,
          builder: (_, scrollController) => ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: ColoredBox(
              color: Colors.white,
              child: _StoryViewersPage(
                viewers: viewers,
                scrollController: scrollController,
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _StoryViewersPage extends StatelessWidget {
  final List<StoryViewerInfo> viewers;
  final ScrollController scrollController;

  const _StoryViewersPage({
    required this.viewers,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final likes = viewers.where((v) => v.liked).length;
    return Column(
      children: [
        const SizedBox(height: 10),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFFD1D7DB),
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Row(
            children: [
              const Icon(Icons.remove_red_eye_outlined,
                  size: 20, color: Color(0xFF54656F)),
              const SizedBox(width: 8),
              Text(
                'Viewed by ${viewers.length}',
                style: const TextStyle(
                  color: Color(0xFF111B21),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const Spacer(),
              const Icon(Icons.favorite_rounded,
                  size: 16, color: Color(0xFFFF2D55)),
              const SizedBox(width: 4),
              Text(
                '$likes',
                style: const TextStyle(
                  color: Color(0xFF111B21),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 0.6, color: Color(0xFFE9EDEF)),
        Expanded(
          child: viewers.isEmpty
              ? const _EmptyViewers()
              : ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.only(top: 6, bottom: 24),
                  itemCount: viewers.length,
                  separatorBuilder: (_, __) => const Padding(
                    padding: EdgeInsets.only(left: 84),
                    child: Divider(
                      height: 1,
                      thickness: 0.5,
                      color: Color(0xFFF0F2F5),
                    ),
                  ),
                  itemBuilder: (_, i) => _ViewerRow(viewer: viewers[i]),
                ),
        ),
      ],
    );
  }
}

class _EmptyViewers extends StatelessWidget {
  const _EmptyViewers();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.remove_red_eye_outlined, size: 42, color: Color(0xFF8696A0)),
          SizedBox(height: 12),
          Text(
            'No views yet',
            style: TextStyle(
              color: Color(0xFF111B21),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'When someone watches this status,\nthey’ll show up here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF667781),
              fontSize: 13.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewerRow extends StatelessWidget {
  final StoryViewerInfo viewer;

  const _ViewerRow({required this.viewer});

  @override
  Widget build(BuildContext context) {
    final name = viewer.viewerName.trim().isEmpty ? 'Unknown' : viewer.viewerName.trim();
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();
    final photo = viewer.viewerProfileImageUrl?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE9EDEF), width: 1.4),
            ),
            child: ClipOval(
              child: photo.isNotEmpty
                  ? Image.network(
                      photo,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => _InitialAvatar(initial: initial),
                    )
                  : _InitialAvatar(initial: initial),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111B21),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _viewedLabel(viewer.viewedAt),
                  style: const TextStyle(
                    color: Color(0xFF667781),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (viewer.liked)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.favorite_rounded, color: Color(0xFFFF2D55), size: 20),
            ),
        ],
      ),
    );
  }
}

class _InitialAvatar extends StatelessWidget {
  final String initial;

  const _InitialAvatar({required this.initial});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFDFE5E7),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: Color(0xFF3B4A54),
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
    );
  }
}

String _viewedLabel(DateTime viewedAt) {
  final now = DateTime.now();
  final local = viewedAt.toLocal();
  final diff = now.difference(local);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return m == 1 ? '1 minute ago' : '$m minutes ago';
  }
  final time = _clock(local);
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  if (day == today) return 'Today, $time';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday, $time';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${local.day} ${months[local.month - 1]}, $time';
}

String _clock(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  final suffix = t.hour >= 12 ? 'PM' : 'AM';
  return '$h:$m $suffix';
}
