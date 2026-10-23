import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vero360_app/features/BottomnvarBars/BottomNavbar.dart';
import 'package:vero360_app/features/Reels/Live/live_hub_page.dart';
import 'package:vero360_app/features/Reels/Live/live_service.dart';
import 'package:vero360_app/features/Reels/Live/live_widgets.dart';
import 'package:vero360_app/features/Reels/post_reel_page.dart';
import 'package:vero360_app/features/Reels/reel_feed_view.dart';
import 'package:vero360_app/features/Reels/reel_model.dart';
import 'package:vero360_app/features/Reels/reel_search_page.dart';
import 'package:vero360_app/features/Reels/reel_service.dart';
import 'package:vero360_app/features/Reels/reel_upload_manager.dart';
import 'package:vero360_app/features/Reels/reel_video_cache.dart';
import 'package:vero360_app/features/Reels/user_reels_page.dart';

enum _FeedMode { forYou, following }

/// Reels tab in the main shell.
class ReelsPage extends StatefulWidget {
  const ReelsPage({super.key, required this.visible});

  /// True while the Reels tab is the selected tab.
  final ValueListenable<bool> visible;

  @override
  State<ReelsPage> createState() => _ReelsPageState();
}

class _ReelsPageState extends State<ReelsPage> {
  final _service = ReelService.instance;
  _FeedMode _mode = _FeedMode.forYou;
  final List<Reel> _forYou = [];
  List<Reel> _following = const [];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _hasMore = true;
  bool _loading = false;
  bool _loadedFollowing = false;
  String? _error;
  bool _covered = false;
  int _feedGeneration = 0;
  StreamSubscription<ReelUploadResult>? _uploadSub;

  @override
  void initState() {
    super.initState();
    widget.visible.addListener(_onVisibility);
    _uploadSub = ReelUploadManager.instance.results.listen(_onUploadResult);
    unawaited(ReelVideoCache.instance.init());
    _loadForYou(reset: true);
  }

  @override
  void didUpdateWidget(covariant ReelsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) {
      oldWidget.visible.removeListener(_onVisibility);
      widget.visible.addListener(_onVisibility);
    }
  }

  @override
  void dispose() {
    widget.visible.removeListener(_onVisibility);
    _uploadSub?.cancel();
    super.dispose();
  }

  void _onVisibility() {
    if (mounted) setState(() {});
  }

  /// Offline, reels whose video is on the device come first so the feed still plays.
  List<Reel> _playableFirst(List<Reel> reels) {
    final cache = ReelVideoCache.instance;
    final ready = reels.where((r) => cache.isCached(r.videoUrl)).toList();
    if (ready.isEmpty) return reels;
    return [...ready, ...reels.where((r) => !cache.isCached(r.videoUrl))];
  }

  void _warmVideos(List<Reel> reels) {
    ReelVideoCache.instance.prefetchMany(reels.map((r) => r.videoUrl));
  }

  Future<void> _loadForYou({bool reset = false}) async {
    if (_loading || (!reset && !_hasMore)) return;
    setState(() {
      _loading = true;
      if (reset) _error = null;
    });
    try {
      // First open: show what's on the device right away, then merge fresh reels.
      var showedQuick = false;
      if (reset && _forYou.isEmpty) {
        await ReelVideoCache.instance.init();
        try {
          final quick = await _service.fetchForYou(cacheOnly: true);
          if (mounted && quick.reels.isNotEmpty) {
            setState(() {
              _forYou
                ..clear()
                ..addAll(_playableFirst(quick.reels));
              _cursor = quick.cursor;
              _hasMore = quick.hasMore;
              _feedGeneration++;
            });
            _warmVideos(_forYou);
            showedQuick = true;
          }
        } catch (_) {}
      }
      final page = await _service.fetchForYou(after: reset ? null : _cursor);
      if (!mounted) return;
      if (showedQuick) {
        setState(() {
          final seen = _forYou.map((r) => r.id).toSet();
          _forYou.addAll(page.reels.where((r) => !seen.contains(r.id)));
          _cursor = page.cursor;
          _hasMore = page.hasMore;
        });
        _warmVideos(_forYou);
        return;
      }
      setState(() {
        if (reset) {
          _forYou
            ..clear()
            ..addAll(page.fromCache ? _playableFirst(page.reels) : page.reels);
          _feedGeneration++;
        } else {
          final seen = _forYou.map((r) => r.id).toSet();
          _forYou.addAll(page.reels.where((r) => !seen.contains(r.id)));
        }
        _cursor = page.cursor;
        _hasMore = page.hasMore;
      });
      _warmVideos(_forYou);
      // A page can be entirely filtered out (hidden / reported); keep going.
      if (page.reels.isEmpty && page.hasMore) {
        _loading = false;
        await _loadForYou();
        return;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Reels] feed failed: $e');
      if (mounted && _forYou.isEmpty) {
        setState(() => _error = 'Could not load reels. Check your connection.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadFollowing() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final reels = await _service.fetchFollowing();
      if (!mounted) return;
      setState(() {
        _following = reels;
        _loadedFollowing = true;
        _feedGeneration++;
      });
      _warmVideos(_following);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load reels. Check your connection.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _switchMode(_FeedMode mode) {
    if (mode == _mode) return;
    setState(() => _mode = mode);
    if (mode == _FeedMode.following && !_loadedFollowing) _loadFollowing();
  }

  Future<void> _refresh() async {
    if (_mode == _FeedMode.forYou) {
      await _loadForYou(reset: true);
    } else {
      await _loadFollowing();
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

  Future<void> _post() async {
    if (!_service.isSignedIn) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Sign in to post a reel.'),
        action: SnackBarAction(
          label: 'Sign in',
          onPressed: () => Navigator.of(context).pushNamed('/login'),
        ),
      ));
      return;
    }
    await _pushCovered<bool>(
      MaterialPageRoute(builder: (_) => const PostReelPage()),
    );
  }

  void _onUploadResult(ReelUploadResult result) {
    if (!mounted || !result.ok) return;
    if (_forYou.isEmpty && _mode == _FeedMode.forYou) {
      unawaited(_loadForYou(reset: true));
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Your reel is posted'),
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(
        label: 'View',
        textColor: const Color(0xFFFF8A00),
        onPressed: _openMine,
      ),
    ));
  }

  Future<void> _openMine() async {
    final me = await _service.myIdentity();
    if (!mounted) return;
    if (me == null) {
      _post();
      return;
    }
    await _pushCovered<void>(MaterialPageRoute(
      builder: (_) => UserReelsPage(
        ownerId: me.uid,
        ownerName: me.name,
        ownerPhoto: me.photo,
      ),
    ));
  }

  void _removeReel(String id) {
    setState(() {
      _forYou.removeWhere((r) => r.id == id);
      _following = _following.where((r) => r.id != id).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final reels = _mode == _FeedMode.forYou ? _forYou : _following;
    // Android remounts this tab; iOS keeps it in an IndexedStack.
    // Either signal is enough so autoplay is not held back a frame.
    final onScreen = widget.visible.value || TickerMode.of(context);
    final active = onScreen && !_covered;
    final navClearance = veroFloatingNavClearance(context, extra: 0);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (reels.isNotEmpty)
              ReelFeedView(
                key: ValueKey('${_mode.name}_$_feedGeneration'),
                reels: reels,
                active: active,
                bottomInset: navClearance,
                onNearEnd: _mode == _FeedMode.forYou ? () => _loadForYou() : null,
                onReelRemoved: _removeReel,
              )
            else
              _emptyState(),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    _TopIconButton(
                      icon: Icons.person_rounded,
                      tooltip: 'My reels',
                      onTap: _openMine,
                    ),
                    const SizedBox(width: 18),
                    _LiveButton(
                      onTap: () => _pushCovered<void>(
                        MaterialPageRoute(builder: (_) => const LiveHubPage()),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Spacer(),
                    Flexible(
                      flex: 6,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.32),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ModeTab(
                            label: 'For you',
                            selected: _mode == _FeedMode.forYou,
                            onTap: () => _switchMode(_FeedMode.forYou),
                          ),
                          _ModeTab(
                            label: 'Following',
                            selected: _mode == _FeedMode.following,
                            onTap: () => _switchMode(_FeedMode.following),
                          ),
                        ],
                      ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 6),
                    _TopIconButton(
                      icon: Icons.search_rounded,
                      tooltip: 'Search shops',
                      onTap: () => _pushCovered<void>(
                        MaterialPageRoute(builder: (_) => const ReelSearchPage()),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _TopIconButton(
                      icon: Icons.add_rounded,
                      tooltip: 'Post a reel',
                      onTap: _post,
                      highlighted: true,
                    ),
                  ],
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 62, 16, 0),
                child: ValueListenableBuilder<ReelUpload?>(
                  valueListenable: ReelUploadManager.instance.current,
                  builder: (context, upload, _) => upload == null
                      ? const SizedBox.shrink()
                      : Align(
                          alignment: Alignment.topCenter,
                          child: _UploadPill(upload: upload),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    final String message;
    if (_error != null) {
      message = _error!;
    } else if (_mode == _FeedMode.following) {
      message = _service.isSignedIn
          ? 'Reels from people you follow show here.\nTap + on a reel to follow.'
          : 'Sign in to see reels from people you follow.';
    } else {
      message = 'No reels yet. Be the first to post one.';
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.movie_filter_outlined, color: Colors.white54, size: 56),
            const SizedBox(height: 14),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.4)),
            const SizedBox(height: 18),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(
                  onPressed: _refresh,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                  child: const Text('Refresh'),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _post,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8A00),
                  ),
                  child: const Text('Post a reel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFF8A00) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white.withValues(alpha: 0.85),
            fontWeight: FontWeight.w800,
            fontSize: 13.5,
          ),
        ),
      ),
    );
  }
}

/// Opens Vero LIVE; pulses a dot while someone is broadcasting.
class _LiveButton extends StatelessWidget {
  const _LiveButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LiveStream>>(
      stream: LiveService.instance.watchLiveNow(),
      builder: (context, snap) {
        final count = snap.data?.length ?? 0;
        return Tooltip(
          message: 'LIVE',
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(21),
                gradient: const LinearGradient(colors: [kLiveRed, Color(0xFFFF5E3A)]),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sensors_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 4),
                  const Text('LIVE',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 12.5,
                          letterSpacing: 0.5)),
                  if (count > 0) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('$count',
                          style: const TextStyle(
                              color: kLiveRed, fontSize: 10.5, fontWeight: FontWeight.w900)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Background reel upload: progress while posting, Retry when it failed.
class _UploadPill extends StatelessWidget {
  const _UploadPill({required this.upload});

  final ReelUpload upload;

  static const _orange = Color(0xFFFF8A00);

  @override
  Widget build(BuildContext context) {
    final manager = ReelUploadManager.instance;
    final failed = upload.failed;
    final pct = (upload.progress * 100).floor();
    final label = failed
        ? 'Reel not posted'
        : upload.progress >= 1
            ? 'Finishing up…'
            : pct > 0
                ? 'Posting your reel  $pct%'
                : 'Posting your reel…';
    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                failed ? Icons.error_outline_rounded : Icons.cloud_upload_rounded,
                color: failed ? Colors.redAccent : _orange,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF1F2430),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              if (failed) ...[
                TextButton(
                  onPressed: manager.retry,
                  style: TextButton.styleFrom(
                    foregroundColor: _orange,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w900)),
                ),
                IconButton(
                  onPressed: manager.dismiss,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 18, color: Colors.black45),
                ),
              ] else
                const SizedBox(width: 4),
            ],
          ),
          if (!failed) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: upload.progress > 0 && upload.progress < 1 ? upload.progress : null,
                minHeight: 4,
                color: _orange,
                backgroundColor: const Color(0xFFFFE6C7),
              ),
            ),
            const SizedBox(height: 2),
          ] else if (upload.error != null)
            Padding(
              padding: const EdgeInsets.only(left: 28, right: 8, bottom: 2),
              child: Text(
                upload.error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _TopIconButton extends StatelessWidget {
  const _TopIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: highlighted
                ? const LinearGradient(
                    colors: [Color(0xFFFFB347), Color(0xFFFF8A00)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: highlighted ? null : Colors.black.withValues(alpha: 0.32),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Icon(icon, color: Colors.white, size: highlighted ? 26 : 22),
        ),
      ),
    );
  }
}
