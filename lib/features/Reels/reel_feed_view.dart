import 'dart:async';


import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:vero360_app/Gernalproviders/cart_service_provider.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/marketplace_share_navigation.dart';
import 'package:vero360_app/features/Marketplace/presentation/pages/merchant_products_page.dart';
import 'package:vero360_app/features/Reels/reel_comments_sheet.dart';
import 'package:vero360_app/features/Reels/reel_download_manager.dart';
import 'package:vero360_app/features/Reels/reel_model.dart';
import 'package:vero360_app/features/Reels/reel_music_picker.dart';
import 'package:vero360_app/features/Reels/reel_service.dart';
import 'package:vero360_app/features/Reels/reel_video_cache.dart';
import 'package:vero360_app/features/Reels/user_reels_page.dart';
import 'package:vero360_app/utils/app_update_checker.dart';
import 'package:vero360_app/utils/toasthelper.dart';

const _kOrange = Color(0xFFFF8A00);

/// Full-screen vertical reel player. Only the current reel and its neighbours
/// hold a video player, so low-RAM phones stay stable.
class ReelFeedView extends StatefulWidget {
  const ReelFeedView({
    super.key,
    required this.reels,
    required this.active,
    this.initialIndex = 0,
    this.bottomInset = 0,
    this.onNearEnd,
    this.onReelRemoved,
  });

  final List<Reel> reels;
  /// False when the tab is hidden or another screen covers the feed.
  final bool active;
  final int initialIndex;
  final double bottomInset;
  final VoidCallback? onNearEnd;
  final ValueChanged<String>? onReelRemoved;

  @override
  State<ReelFeedView> createState() => _ReelFeedViewState();
}

class _ReelFeedViewState extends State<ReelFeedView>
    with WidgetsBindingObserver {
  late final PageController _controller;
  late int _index;
  bool _appVisible = true;
  /// Paused while another route (product, shop, profile) is on top.
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.reels.isEmpty ? 0 : widget.reels.length - 1);
    _controller = PageController(initialPage: _index);
    WidgetsBinding.instance.addObserver(this);
    _prefetchAround(_index);
  }

  /// Downloads the next reels while this one plays, like TikTok, and drops
  /// downloads for reels that were scrolled past.
  void _prefetchAround(int i) {
    final reels = widget.reels;
    if (reels.isEmpty) return;
    final cache = ReelVideoCache.instance;
    final near = <String>[];
    for (var j = i - 1; j <= i + 2; j++) {
      if (j >= 0 && j < reels.length) near.add(reels[j].videoUrl);
    }
    cache.keepOnly(near);
    for (var j = i; j <= i + 2 && j < reels.length; j++) {
      cache.prefetch(reels[j].videoUrl, priority: j == i);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `inactive` fires for permission prompts, the notification shade and
    // returning from pickers; only stop when the app is really in the background.
    final visible = state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    if (visible != _appVisible) setState(() => _appVisible = visible);
  }

  @override
  void didUpdateWidget(covariant ReelFeedView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reels.isNotEmpty && _index >= widget.reels.length) {
      _index = widget.reels.length - 1;
    }
    if (widget.reels.length != oldWidget.reels.length ||
        (widget.reels.isNotEmpty &&
            oldWidget.reels.isNotEmpty &&
            widget.reels.first.id != oldWidget.reels.first.id)) {
      _prefetchAround(_index);
    }
  }

  Future<T?> _pushCovered<T>(Route<T> route) async {
    setState(() => _covered = true);
    try {
      return await Navigator.of(context).push(route);
    } finally {
      if (mounted) setState(() => _covered = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reels = widget.reels;
    final playing = widget.active && _appVisible && !_covered;
    return PageView.builder(
      controller: _controller,
      scrollDirection: Axis.vertical,
      // Keeps the neighbouring pages built so their videos buffer before the swipe.
      allowImplicitScrolling: true,
      itemCount: reels.length,
      onPageChanged: (i) {
        setState(() => _index = i);
        _prefetchAround(i);
        if (i >= reels.length - 3) widget.onNearEnd?.call();
      },
      itemBuilder: (context, i) {
        final reel = reels[i];
        return _ReelTile(
          key: ValueKey(reel.id),
          reel: reel,
          load: i >= _index - 1 && i <= _index + 2,
          playing: playing && i == _index,
          bottomInset: widget.bottomInset,
          pushCovered: _pushCovered,
          onRemoved: () => widget.onReelRemoved?.call(reel.id),
        );
      },
    );
  }
}

class _ReelTile extends StatefulWidget {
  const _ReelTile({
    super.key,
    required this.reel,
    required this.load,
    required this.playing,
    required this.bottomInset,
    required this.pushCovered,
    required this.onRemoved,
  });

  final Reel reel;
  final bool load;
  final bool playing;
  final double bottomInset;
  final Future<T?> Function<T>(Route<T> route) pushCovered;
  final VoidCallback onRemoved;

  @override
  State<_ReelTile> createState() => _ReelTileState();
}

class _ReelTileState extends State<_ReelTile> {
  final _service = ReelService.instance;
  VideoPlayerController? _video;
  bool _ready = false;
  bool _failed = false;
  bool _initializing = false;
  int _retries = 0;
  Duration? _resumeAt;
  Timer? _watchdog;
  Duration _lastPosition = Duration.zero;
  int _stuckTicks = 0;
  bool _userPaused = false;
  bool _liked = false;
  bool _shared = false;
  bool _likeBusy = false;
  bool _following = true;
  bool _captionOpen = false;
  bool _showHeart = false;
  StreamSubscription<ReelDownloadResult>? _downloadSub;
  Timer? _viewTimer;
  late Reel _reel;

  bool get _isMine =>
      FirebaseAuth.instance.currentUser?.uid == _reel.ownerId;

  @override
  void initState() {
    super.initState();
    _reel = widget.reel;
    if (widget.load) _initVideo();
    _loadSocial();
    _downloadSub = ReelDownloadManager.instance.results.listen((r) {
      if (!mounted || r.reelId != _reel.id) return;
      if (r.ok) HapticFeedback.lightImpact();
      _toast(r.message, ok: r.ok);
    });
  }

  Future<void> _loadSocial() async {
    final results = await Future.wait([
      _service.isLiked(_reel.id),
      _service.hasShared(_reel.id),
    ]);
    final following = _isMine ||
        (await _service.followingIds()).contains(_reel.ownerId);
    if (!mounted) return;
    setState(() {
      _liked = results[0];
      _shared = results[1];
      _following = following;
    });
  }

  /// Android plays through a native view: the texture path renders black on
  /// Skia (Impeller is off in the manifest).
  /// Plays from the disk cache when the reel was seen or prefetched before
  /// (instant, works offline); otherwise streams and caches in the background.
  Future<void> _initVideo() async {
    if (_video != null || _initializing || _reel.videoUrl.isEmpty) return;
    _initializing = true;
    final cache = ReelVideoCache.instance;
    final file = cache.cachedSync(_reel.videoUrl) ?? await cache.cached(_reel.videoUrl);
    _initializing = false;
    if (!mounted || !widget.load || _video != null) return;
    final viewType = defaultTargetPlatform == TargetPlatform.android
        ? VideoViewType.platformView
        : VideoViewType.textureView;
    final controller = file != null
        ? VideoPlayerController.file(file, viewType: viewType)
        : VideoPlayerController.networkUrl(Uri.parse(_reel.videoUrl), viewType: viewType);
    if (file == null) cache.prefetch(_reel.videoUrl, priority: widget.playing);
    _video = controller;
    _failed = false;
    controller.addListener(_onVideoValue);
    try {
      await controller.initialize();
      if (!mounted || _video != controller) return;
      await controller.setLooping(true);
      final resume = _resumeAt;
      _resumeAt = null;
      if (resume != null && resume > Duration.zero) await controller.seekTo(resume);
      if (!widget.playing) {
        // Decode the first frame so the reel is on screen the moment it's swiped to.
        await controller.setVolume(0);
        await controller.play();
        if (!widget.playing) {
          await controller.pause();
          if (resume == null) await controller.seekTo(Duration.zero);
        }
        await controller.setVolume(1);
        if (!mounted || _video != controller) return;
      }
      _retries = 0;
      setState(() => _ready = true);
      _syncPlayback();
    } catch (e) {
      if (kDebugMode) debugPrint('[Reels] video failed: $e');
      if (!mounted || _video != controller) return;
      unawaited(_recover());
    }
  }

  void _onVideoValue() {
    final v = _video;
    if (v != null && v.value.hasError) unawaited(_recover());
  }

  bool _recovering = false;

  /// Rebuilds the player after a network drop or decoder error, resuming
  /// where it stopped. Prefers the cached copy if it finished meanwhile.
  Future<void> _recover() async {
    if (_recovering || !mounted) return;
    if (_retries >= 3) {
      setState(() => _failed = true);
      return;
    }
    _recovering = true;
    _retries++;
    final pos = _video?.value.position ?? Duration.zero;
    _releaseVideo();
    if (mounted) setState(() {});
    await Future<void>.delayed(Duration(milliseconds: 600 * _retries));
    _recovering = false;
    if (!mounted || !widget.load) return;
    _resumeAt = pos;
    await _initVideo();
  }

  /// Videos sometimes stop on their own (buffer underrun, audio focus,
  /// platform view hiccup). While this reel should be playing, nudge it.
  void _startWatchdog() {
    _watchdog ??= Timer.periodic(const Duration(seconds: 1), (_) {
      final v = _video;
      if (!mounted || v == null || !v.value.isInitialized) return;
      if (!widget.playing || _userPaused) {
        _stuckTicks = 0;
        return;
      }
      final value = v.value;
      if (!value.isPlaying) {
        v.play();
        _stuckTicks = 0;
        return;
      }
      if (value.position == _lastPosition && !value.isBuffering) {
        _stuckTicks++;
      } else if (value.isBuffering) {
        // Long stall on a stream: switch to the cached copy once it's there.
        if (ReelVideoCache.instance.isCached(_reel.videoUrl) && _stuckTicks++ > 3) {
          _stuckTicks = 0;
          _retries = 0;
          unawaited(_recover());
        }
      } else {
        _stuckTicks = 0;
      }
      _lastPosition = value.position;
      if (_stuckTicks >= 5) {
        _stuckTicks = 0;
        unawaited(_recover());
      }
    });
  }

  void _stopWatchdog() {
    _watchdog?.cancel();
    _watchdog = null;
    _stuckTicks = 0;
  }

  /// Tap always acts on the player directly, even if auto-play was held back.
  void _onTapVideo() {
    final v = _video;
    if (v == null || !v.value.isInitialized) {
      if (_failed) {
        _retries = 0;
        setState(() => _failed = false);
        _initVideo();
        return;
      }
      if (v == null) _initVideo();
      return;
    }
    if (v.value.isPlaying) {
      v.pause();
      _viewTimer?.cancel();
      setState(() => _userPaused = true);
    } else {
      v.play();
      setState(() => _userPaused = false);
      _viewTimer?.cancel();
      _viewTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) _service.recordView(_reel.id);
      });
    }
  }

  void _releaseVideo() {
    _viewTimer?.cancel();
    _stopWatchdog();
    final v = _video;
    _video = null;
    _ready = false;
    v?.removeListener(_onVideoValue);
    v?.dispose();
  }

  void _syncPlayback() {
    if (widget.playing) {
      _startWatchdog();
    } else {
      _stopWatchdog();
    }
    final v = _video;
    if (v == null || !v.value.isInitialized) return;
    final shouldPlay = widget.playing && !_userPaused;
    if (shouldPlay && !v.value.isPlaying) {
      v.play();
      _viewTimer?.cancel();
      _viewTimer = Timer(const Duration(seconds: 2), () {
        if (mounted && widget.playing) _service.recordView(_reel.id);
      });
    } else if (!shouldPlay && v.value.isPlaying) {
      v.pause();
      _viewTimer?.cancel();
    }
  }

  @override
  void didUpdateWidget(covariant _ReelTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.load && _video == null) _initVideo();
    if (!widget.load && _video != null) {
      _releaseVideo();
    }
    if (widget.playing && !oldWidget.playing) {
      _userPaused = false;
      if (_failed) {
        _retries = 0;
        _failed = false;
        _releaseVideo();
        _initVideo();
      } else {
        _video?.seekTo(Duration.zero);
      }
    }
    _syncPlayback();
  }

  @override
  void dispose() {
    _downloadSub?.cancel();
    _releaseVideo();
    super.dispose();
  }

  bool _requireSignIn(String action) {
    if (_service.isSignedIn) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Sign in to $action.'),
        action: SnackBarAction(
          label: 'Sign in',
          onPressed: () => Navigator.of(context).pushNamed('/login'),
        ),
      ),
    );
    return false;
  }

  void _toast(String msg, {bool ok = false}) {
    ToastHelper.showCustomToast(context, msg, isSuccess: ok, errorMessage: '');
  }

  Future<void> _toggleLike({bool onlyLike = false}) async {
    if (!_requireSignIn('like reels') || _likeBusy) return;
    if (onlyLike && _liked) return;
    final before = _liked;
    setState(() {
      _likeBusy = true;
      _liked = !before;
      _reel = _reel.copyWith(likeCount: _reel.likeCount + (before ? -1 : 1));
    });
    try {
      final now = await _service.toggleLike(_reel.id);
      if (mounted && now != _liked) setState(() => _liked = now);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _liked = before;
        _reel = _reel.copyWith(likeCount: _reel.likeCount + (before ? 1 : -1));
      });
      _toast('Could not update like');
    } finally {
      if (mounted) setState(() => _likeBusy = false);
    }
  }

  void _doubleTapLike() {
    setState(() => _showHeart = true);
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _showHeart = false);
    });
    _toggleLike(onlyLike: true);
  }

  Future<void> _follow() async {
    if (!_requireSignIn('follow')) return;
    setState(() => _following = true);
    try {
      await _service.follow(_reel.ownerId);
    } catch (_) {
      if (!mounted) return;
      setState(() => _following = false);
      _toast('Could not follow');
    }
  }

  Future<void> _openComments() async {
    await showReelComments(
      context,
      reel: _reel,
      canModerate: _isMine,
      onCountChanged: (n) {
        if (mounted && n != _reel.commentCount) {
          setState(() => _reel = _reel.copyWith(commentCount: n));
        }
      },
    );
  }

  Future<void> _share() async {
    final store = AppUpdateChecker.defaultStoreUrl(
      isIos: defaultTargetPlatform == TargetPlatform.iOS,
    );
    final caption = _reel.caption.trim();
    final text = [
      'Watch ${_reel.ownerName}\'s reel on Vero360',
      if (caption.isNotEmpty) '"$caption"',
      _reel.videoUrl,
      'Get the app: $store',
    ].join('\n');
    try {
      final result = await SharePlus.instance.share(
        ShareParams(text: text, subject: 'Vero360 reel'),
      );
      if (result.status == ShareResultStatus.dismissed) return;
      // One share per account, however many times they tap.
      final counted = await _service.recordShare(_reel.id);
      if (!mounted) return;
      setState(() {
        _shared = _service.isSignedIn || _shared;
        if (counted) _reel = _reel.copyWith(shareCount: _reel.shareCount + 1);
      });
    } catch (_) {}
  }

  void _openOwner() {
    if (_reel.ownerIsMerchant) {
      widget.pushCovered(MaterialPageRoute<void>(
        builder: (_) => MerchantProductsPage(
          merchantId: _reel.ownerId,
          merchantName: _reel.ownerName,
        ),
      ));
    } else {
      widget.pushCovered(MaterialPageRoute<void>(
        builder: (_) => UserReelsPage(
          ownerId: _reel.ownerId,
          ownerName: _reel.ownerName,
          ownerPhoto: _reel.ownerPhoto,
        ),
      ));
    }
  }

  Future<void> _openProduct() async {
    final product = _reel.product;
    if (product == null) return;
    setState(() => _userPaused = true);
    _syncPlayback();
    final opened = await MarketplaceShareNavigation.openFirestoreProduct(
      product.id,
      CartServiceProvider.getInstance(),
    );
    if (!mounted) return;
    if (!opened) _toast('This product is no longer available');
    setState(() => _userPaused = false);
    _syncPlayback();
  }

  Future<void> _more() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.download_rounded, color: Color(0xFFFF8A00)),
              title: const Text('Download video'),
              subtitle: const Text('Save to your gallery'),
              enabled: !ReelDownloadManager.instance.isDownloading(_reel.id),
              onTap: () => Navigator.pop(ctx, 'download'),
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Share'),
              onTap: () => Navigator.pop(ctx, 'share'),
            ),
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('Copy link'),
              onTap: () => Navigator.pop(ctx, 'copy'),
            ),
            const Divider(height: 1),
            if (_isMine)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete reel'),
                onTap: () => Navigator.pop(ctx, 'delete'),
              )
            else ...[
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: const Text('Not interested'),
                onTap: () => Navigator.pop(ctx, 'hide'),
              ),
              ListTile(
                leading: const Icon(Icons.flag_outlined, color: Colors.red),
                title: const Text('Report'),
                onTap: () => Navigator.pop(ctx, 'report'),
              ),
            ],
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'download':
        _download();
      case 'share':
        await _share();
      case 'copy':
        await Clipboard.setData(ClipboardData(text: _reel.videoUrl));
        if (mounted) _toast('Link copied', ok: true);
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete reel?'),
            content: const Text('It will be removed for everyone.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
        if (ok != true || !mounted) return;
        try {
          await _service.deleteReel(_reel);
          if (!mounted) return;
          _toast('Reel deleted', ok: true);
          widget.onRemoved();
        } catch (e) {
          if (mounted) _toast('Could not delete reel');
        }
      case 'hide':
        await _service.hideForMe(_reel.id);
        if (mounted) widget.onRemoved();
      case 'report':
        if (!_requireSignIn('report')) return;
        final reason = await _pickReportReason();
        if (reason == null || !mounted) return;
        try {
          await _service.report(_reel.id, reason);
          if (!mounted) return;
          _toast('Thanks. We will review this reel.', ok: true);
          widget.onRemoved();
        } catch (_) {
          if (mounted) _toast('Could not send report');
        }
    }
  }

  void _download() {
    if (FirebaseAuth.instance.currentUser == null) {
      _requireSignIn('download reels');
      return;
    }
    if (ReelDownloadManager.instance.start(_reel)) {
      _toast('Downloading in the background. You can keep watching.', ok: true);
    }
  }

  Future<String?> _pickReportReason() {
    const reasons = [
      'Scam or fraud',
      'Nudity or sexual content',
      'Violence or dangerous acts',
      'Hate or harassment',
      'Fake or misleading product',
      'Spam',
      'Something else',
    ];
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Why are you reporting this reel?',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            for (final r in reasons)
              ListTile(title: Text(r), onTap: () => Navigator.pop(ctx, r)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = _video;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _onTapVideo,
            onDoubleTap: _doubleTapLike,
            onLongPress: () {
              HapticFeedback.mediumImpact();
              _more();
            },
            child: Center(
              child: v != null && _ready && v.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: v.value.aspectRatio == 0
                          ? 9 / 16
                          : v.value.aspectRatio,
                      child: VideoPlayer(v),
                    )
                  : _placeholder(),
            ),
          ),
          // Top and bottom shades keep white text readable on bright videos.
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, 0.18, 0.5, 1],
                  colors: [
                    Color(0x8C000000),
                    Colors.transparent,
                    Colors.transparent,
                    Color(0xCC000000),
                  ],
                ),
              ),
            ),
          ),
          ValueListenableBuilder<Map<String, ReelDownloadProgress>>(
            valueListenable: ReelDownloadManager.instance.active,
            builder: (context, jobs, _) {
              final job = jobs[_reel.id];
              if (job == null) return const SizedBox.shrink();
              return IgnorePointer(
                child: SafeArea(
                  child: Align(
                    alignment: const Alignment(0, -0.78),
                    child: _DownloadPill(progress: job.progress, preparing: job.preparing),
                  ),
                ),
              );
            },
          ),
          IgnorePointer(
            child: Center(
              child: AnimatedOpacity(
                opacity: _userPaused && _ready ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      size: 52, color: Colors.white),
                ),
              ),
            ),
          ),
          if (_showHeart)
            IgnorePointer(
              child: Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.4, end: 1),
                  duration: const Duration(milliseconds: 380),
                  curve: Curves.elasticOut,
                  builder: (_, s, child) => Transform.scale(scale: s, child: child),
                  child: const Icon(
                    Icons.favorite_rounded,
                    size: 120,
                    color: Color(0xFFFF3B5C),
                    shadows: [Shadow(blurRadius: 24, color: Colors.black38)],
                  ),
                ),
              ),
            ),
          Positioned(
            right: 10,
            bottom: widget.bottomInset + 22,
            child: _actions(),
          ),
          Positioned(
            left: 16,
            right: 88,
            bottom: widget.bottomInset + 22,
            child: _details(),
          ),
          if (v != null && _ready)
            Positioned(
              left: 0,
              right: 0,
              bottom: widget.bottomInset + 4,
              child: SizedBox(
                height: 3,
                child: VideoProgressIndicator(
                  v,
                  allowScrubbing: true,
                  padding: EdgeInsets.zero,
                  colors: const VideoProgressColors(
                    playedColor: Colors.white,
                    bufferedColor: Colors.white24,
                    backgroundColor: Colors.white10,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholder() {
    if (_failed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, color: Colors.white70, size: 36),
          const SizedBox(height: 10),
          const Text('Could not load this reel',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Check your connection',
              style: TextStyle(color: Colors.white70, fontSize: 12.5)),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () {
              _releaseVideo();
              _retries = 0;
              setState(() => _failed = false);
              _initVideo();
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white70),
            ),
            child: const Text('Retry'),
          ),
        ],
      );
    }
    return const SizedBox(
      width: 34,
      height: 34,
      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
    );
  }

  Widget _actions() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _openOwner,
          child: SizedBox(
            width: 56,
            height: 66,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFFFFB347), _kOrange, Color(0xFFFF3B5C)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: _Avatar(url: _reel.ownerPhoto, name: _reel.ownerName, size: 46),
                ),
                if (!_following)
                  Positioned(
                    bottom: 0,
                    child: GestureDetector(
                      onTap: _follow,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: _kOrange,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.add_rounded, size: 16, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        _ActionButton(
          icon: _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          color: _liked ? const Color(0xFFFF3B5C) : Colors.white,
          active: _liked,
          label: _compact(_reel.likeCount),
          onTap: _toggleLike,
        ),
        _ActionButton(
          icon: Icons.chat_bubble_rounded,
          label: _compact(_reel.commentCount),
          onTap: _openComments,
        ),
        _ActionButton(
          icon: Icons.reply_rounded,
          mirror: true,
          color: _shared ? _kOrange : Colors.white,
          active: _shared,
          label: _compact(_reel.shareCount),
          onTap: _share,
        ),
        _ActionButton(icon: Icons.more_horiz_rounded, label: '', onTap: _more),
        if (_reel.music != null) ...[
          const SizedBox(height: 4),
          GestureDetector(
            onTap: _openMusic,
            child: _MusicDisc(
              image: _reel.music!.image,
              spinning: widget.playing && !_userPaused,
            ),
          ),
        ],
      ],
    );
  }

  Widget _details() {
    final caption = _reel.caption.trim();
    final product = _reel.product;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (product != null) ...[
          GestureDetector(
            onTap: _openProduct,
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: product.image.startsWith('http')
                        ? Image.network(
                            product.image,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _productIcon(),
                          )
                        : _productIcon(),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _kOrange,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shopping_bag_rounded, size: 14, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'Shop',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: GestureDetector(
                onTap: _openOwner,
                child: Text(
                  _reel.ownerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    letterSpacing: -0.2,
                    shadows: [Shadow(blurRadius: 8, color: Colors.black45)],
                  ),
                ),
              ),
            ),
            if (_reel.ownerIsMerchant) ...[
              const SizedBox(width: 5),
              const Icon(Icons.verified_rounded, size: 16, color: _kOrange),
            ],
            if (!_following) ...[
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _follow,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.85)),
                  ),
                  child: const Text(
                    'Follow',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (caption.isNotEmpty) ...[
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => setState(() => _captionOpen = !_captionOpen),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.topLeft,
              child: Text(
                caption,
                maxLines: _captionOpen ? 12 : 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.35,
                  shadows: [Shadow(blurRadius: 8, color: Colors.black45)],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.play_arrow_rounded, size: 15, color: Colors.white70),
            const SizedBox(width: 2),
            Text(
              '${_compact(_reel.viewCount)} views',
              style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const Text('  ·  ', style: TextStyle(color: Colors.white54, fontSize: 12)),
            Text(
              reelTimeAgo(_reel.createdAt),
              style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        if (_reel.music != null) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _openMusic,
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.music_note_rounded, size: 15, color: Colors.white),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      _reel.music!.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Spotify',
                    style: TextStyle(
                      color: kSpotifyGreen,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _openMusic() async {
    final music = _reel.music;
    if (music == null) return;
    setState(() => _userPaused = true);
    _syncPlayback();
    final ok = await launchUrl(Uri.parse(music.url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) _toast('Could not open Spotify');
  }

  Widget _productIcon() => Container(
        width: 44,
        height: 44,
        color: const Color(0xFFFFF0D9),
        child: const Icon(Icons.shopping_bag_outlined, color: _kOrange, size: 22),
      );
}

/// Album art on a vinyl-style disc that turns while the reel plays.
class _DownloadPill extends StatelessWidget {
  const _DownloadPill({required this.progress, required this.preparing});

  final double progress;
  final bool preparing;

  @override
  Widget build(BuildContext context) {
    final pct = (progress * 100).clamp(0, 100).round();
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              value: !preparing && progress > 0 ? progress : null,
              strokeWidth: 2.5,
              color: const Color(0xFFFF8A00),
              backgroundColor: Colors.white24,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            preparing
                ? 'Adding Vero360 watermark…'
                : progress >= 1
                    ? 'Saving…'
                    : 'Downloading $pct%',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _MusicDisc extends StatefulWidget {
  const _MusicDisc({required this.image, required this.spinning});

  final String image;
  final bool spinning;

  @override
  State<_MusicDisc> createState() => _MusicDiscState();
}

class _MusicDiscState extends State<_MusicDisc> with SingleTickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 5));

  @override
  void initState() {
    super.initState();
    if (widget.spinning) _spin.repeat();
  }

  @override
  void didUpdateWidget(covariant _MusicDisc oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spinning && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.spinning && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _spin,
      child: Container(
        width: 44,
        height: 44,
        padding: const EdgeInsets.all(9),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(
            colors: [Color(0xFF222222), Color(0xFF444444), Color(0xFF222222), Color(0xFF444444), Color(0xFF222222)],
          ),
        ),
        child: ClipOval(
          child: widget.image.startsWith('http')
              ? Image.network(
                  widget.image,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: kSpotifyGreen,
                    child: Icon(Icons.music_note_rounded, size: 14, color: Colors.white),
                  ),
                )
              : const ColoredBox(
                  color: kSpotifyGreen,
                  child: Icon(Icons.music_note_rounded, size: 14, color: Colors.white),
                ),
        ),
      ),
    );
  }
}

String reelCompact(int n) => _compact(n);

String _compact(int n) {
  if (n <= 0) return '0';
  if (n < 1000) return '$n';
  if (n < 1000000) {
    final k = n / 1000;
    return '${k.toStringAsFixed(k < 10 ? 1 : 0)}K';
  }
  final m = n / 1000000;
  return '${m.toStringAsFixed(m < 10 ? 1 : 0)}M';
}

/// Round translucent action button (no backdrop blur: it hides native video).
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
    this.mirror = false,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool mirror;
  final bool active;

  @override
  Widget build(BuildContext context) {
    Widget iconWidget = Icon(icon, size: 27, color: color);
    if (mirror) {
      iconWidget = Transform(
        alignment: Alignment.center,
        transform: Matrix4.rotationY(3.14159),
        child: iconWidget,
      );
    }
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            AnimatedScale(
              scale: active ? 1.08 : 1,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.28),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: Center(child: iconWidget),
              ),
            ),
            if (label.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.name, required this.size});

  final String url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? 'V' : name.trim()[0].toUpperCase();
    final fallback = CircleAvatar(
      radius: size / 2,
      backgroundColor: _kOrange,
      child: Text(initial,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
    );
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      child: url.startsWith('http')
          ? ClipOval(
              child: Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
            )
          : fallback,
    );
  }
}

/// Small helper reused by the grid page.
class ReelAvatar extends StatelessWidget {
  const ReelAvatar({super.key, required this.url, required this.name, this.size = 40});

  final String url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => _Avatar(url: url, name: name, size: size);
}
