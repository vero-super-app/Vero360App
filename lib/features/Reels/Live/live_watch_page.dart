import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:vero360_app/features/Reels/Live/live_filters.dart';
import 'package:vero360_app/features/Reels/Live/live_rtc.dart';
import 'package:vero360_app/features/Reels/Live/live_service.dart';
import 'package:vero360_app/features/Reels/Live/live_widgets.dart';
import 'package:vero360_app/features/Reels/reel_feed_view.dart';
import 'package:vero360_app/features/Reels/reel_service.dart';
import 'package:vero360_app/features/Reels/user_reels_page.dart';

/// Full-screen viewer for one LIVE.
class LiveWatchPage extends StatefulWidget {
  const LiveWatchPage({super.key, required this.live});

  final LiveStream live;

  @override
  State<LiveWatchPage> createState() => _LiveWatchPageState();
}

class _LiveWatchPageState extends State<LiveWatchPage> {
  late final LiveViewerSession _session = LiveViewerSession(widget.live.id);
  final _comment = TextEditingController();
  final _hearts = GlobalKey<FloatingHeartsState>();
  final _live = LiveService.instance;

  late LiveStream _info = widget.live;
  StreamSubscription<LiveStream?>? _sub;
  bool _ended = false;
  bool _full = false;
  bool? _following;
  int _seenLikes = 0;

  bool get _isMine => _live.uid == widget.live.hostId;

  @override
  void initState() {
    super.initState();
    _seenLikes = widget.live.likeCount;
    _session.addListener(_onSession);
    if (widget.live.viewerCount >= LiveService.maxViewers) {
      _full = true;
    } else {
      unawaited(_session.join().then((_) => _announceJoin()));
    }
    _sub = _live.watch(widget.live.id).listen(_onLive);
    if (!_isMine) {
      ReelService.instance.followingIds().then((ids) {
        if (mounted) setState(() => _following = ids.contains(widget.live.hostId));
      });
    }
  }

  Future<void> _announceJoin() async {
    if (_session.error != null) return;
    try {
      await _live.sendChat(widget.live.id, 'joined', type: 'join');
    } catch (_) {}
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  void _onLive(LiveStream? l) {
    if (!mounted) return;
    if (l == null || !l.isLive) {
      setState(() => _ended = true);
      return;
    }
    if (l.likeCount > _seenLikes) {
      _hearts.currentState?.burst((l.likeCount - _seenLikes).clamp(1, 3));
    }
    setState(() {
      _info = l;
      _seenLikes = l.likeCount;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _session.removeListener(_onSession);
    unawaited(_session.leave());
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _comment.text.trim();
    if (text.isEmpty) return;
    _comment.clear();
    try {
      await _live.sendChat(widget.live.id, text);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
      ));
    }
  }

  void _like() {
    HapticFeedback.lightImpact();
    _seenLikes++;
    _hearts.currentState?.burst();
    unawaited(_live.like(widget.live.id));
  }

  Future<void> _follow() async {
    if (_following != false) return;
    setState(() => _following = true);
    try {
      await ReelService.instance.follow(widget.live.hostId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _following = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
      ));
    }
  }

  void _openHost() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => UserReelsPage(
        ownerId: widget.live.hostId,
        ownerName: widget.live.hostName,
        ownerPhoto: widget.live.hostPhoto,
        isMerchant: widget.live.hostIsMerchant,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (_session.hasVideo && !_ended)
              applyLiveFilter(
                _info.filter,
                RTCVideoView(
                  _session.remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              )
            else
              _backdrop(),
            if (_session.hasVideo && !_ended) LiveEffectLayer(effectId: _info.effect),
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x66000000), Colors.transparent, Colors.transparent, Color(0x99000000)],
                    stops: [0, 0.2, 0.6, 1],
                  ),
                ),
              ),
            ),
            SafeArea(child: _overlay()),
            if (_ended || _full || _session.error != null) _blocker(),
          ],
        ),
      ),
    );
  }

  Widget _backdrop() {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_info.hostPhoto.startsWith('http'))
          Opacity(
            opacity: 0.35,
            child: Image.network(_info.hostPhoto,
                fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
          ),
        if (!_ended && !_full && _session.error == null)
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: kLiveOrange),
                SizedBox(height: 14),
                Text('Joining LIVE…',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _overlay() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Flexible(
                child: GestureDetector(
                  onTap: _openHost,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.38),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ReelAvatar(url: _info.hostPhoto, name: _info.hostName, size: 34),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(_info.hostName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13.5)),
                                  ),
                                  if (_info.hostIsMerchant) ...[
                                    const SizedBox(width: 3),
                                    const Icon(Icons.verified_rounded,
                                        size: 14, color: kLiveOrange),
                                  ],
                                ],
                              ),
                              Text('${reelCompact(_info.likeCount)} likes',
                                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_following == false)
                          GestureDetector(
                            onTap: _follow,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: kLiveOrange,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Text('Follow',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12.5)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const LiveBadge(),
              const SizedBox(width: 6),
              LiveViewerPill(count: _info.viewerCount),
              const SizedBox(width: 6),
              LiveRoundButton(
                icon: Icons.close_rounded,
                size: 36,
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
        if (_info.title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _info.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
                ),
              ),
            ),
          ),
        if (!_session.connected && _session.hasVideo && !_ended)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text('Reconnecting…',
                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
          ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  children: [
                    SizedBox(
                      height: 240,
                      child: LiveChatOverlay(liveId: widget.live.id, hostId: widget.live.hostId),
                    ),
                    const SizedBox(height: 10),
                    LiveCommentField(controller: _comment, onSend: _send),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingHearts(key: _hearts),
                  LiveRoundButton(
                    icon: Icons.favorite_rounded,
                    color: Colors.white,
                    background: kLiveRed,
                    size: 50,
                    onTap: _like,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _blocker() {
    final String title;
    final String body;
    if (_ended) {
      title = 'LIVE has ended';
      body = 'Follow ${_info.hostName} to catch their next LIVE.';
    } else if (_full) {
      title = 'This LIVE is full';
      body = 'Up to ${LiveService.maxViewers} people can watch at once. Try again soon.';
    } else {
      title = 'Could not connect';
      body = _session.error ?? '';
    }
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.75),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ReelAvatar(url: _info.hostPhoto, name: _info.hostName, size: 76),
              const SizedBox(height: 16),
              Text(title,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, height: 1.4)),
              const SizedBox(height: 20),
              if (_ended && _following == false)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: FilledButton.icon(
                    onPressed: _follow,
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    label: const Text('Follow', style: TextStyle(fontWeight: FontWeight.w800)),
                    style: FilledButton.styleFrom(
                      backgroundColor: kLiveOrange,
                      minimumSize: const Size(180, 46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              OutlinedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                  minimumSize: const Size(180, 46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Back', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
