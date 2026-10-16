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

/// Camera preview with a title, then the host's broadcast screen.
class GoLivePage extends StatefulWidget {
  const GoLivePage({super.key});

  @override
  State<GoLivePage> createState() => _GoLivePageState();
}

class _GoLivePageState extends State<GoLivePage> {
  final _session = LiveHostSession();
  final _title = TextEditingController();
  final _comment = TextEditingController();
  final _hearts = GlobalKey<FloatingHeartsState>();
  final _live = LiveService.instance;

  String? _liveId;
  bool _starting = false;
  bool _ended = false;
  DateTime? _startedAt;
  Timer? _clock;
  StreamSubscription<LiveStream?>? _liveSub;
  int _likes = 0;
  ReelIdentity? _me;
  String _filter = 'normal';
  String _effect = 'none';
  String? _flashName;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSession);
    _session.startPreview();
    ReelService.instance.myIdentity().then((me) {
      if (mounted) setState(() => _me = me);
    });
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _clock?.cancel();
    _flashTimer?.cancel();
    _liveSub?.cancel();
    final id = _liveId;
    if (id != null) unawaited(_live.end(id));
    _session.removeListener(_onSession);
    unawaited(_session.close());
    _title.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _goLive() async {
    if (_starting || !_session.previewReady) return;
    setState(() => _starting = true);
    try {
      final title = _title.text.trim().isEmpty
          ? '${_me?.name ?? 'Vero360'} is live'
          : _title.text.trim();
      final id = await _live.start(title: title, filter: _filter, effect: _effect);
      if (!mounted) {
        unawaited(_live.end(id));
        return;
      }
      await _session.goLive(id);
      HapticFeedback.mediumImpact();
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() {
        _liveId = id;
        _starting = false;
        _startedAt = DateTime.now();
      });
      _clock = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
      _liveSub = _live.watch(id).listen((l) {
        if (l == null || !mounted) return;
        if (l.likeCount > _likes) {
          _hearts.currentState?.burst((l.likeCount - _likes).clamp(1, 4));
        }
        setState(() => _likes = l.likeCount);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _starting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
      ));
    }
  }

  void _setFilter(String id, {bool flash = false}) {
    if (id == _filter) return;
    setState(() => _filter = id);
    if (flash) _flash(liveFilterById(id).name);
    _pushLook();
  }

  void _setEffect(String id) {
    if (id == _effect) return;
    setState(() => _effect = id);
    _pushLook();
  }

  void _pushLook() {
    final id = _liveId;
    if (id != null) unawaited(_live.setLook(id, filter: _filter, effect: _effect));
  }

  void _flash(String name) {
    _flashTimer?.cancel();
    setState(() => _flashName = name);
    _flashTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _flashName = null);
    });
  }

  void _swipeFilter(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v.abs() < 150) return;
    final i = liveFilters.indexWhere((f) => f.id == _filter);
    final next = (i + (v < 0 ? 1 : -1)) % liveFilters.length;
    HapticFeedback.selectionClick();
    _setFilter(liveFilters[next].id, flash: true);
  }

  void _openLooks() {
    showLiveLookPicker(
      context,
      filter: _filter,
      effect: _effect,
      onFilter: (id) => _setFilter(id),
      onEffect: _setEffect,
    );
  }

  Future<void> _sendComment() async {
    final id = _liveId;
    final text = _comment.text.trim();
    if (id == null || text.isEmpty) return;
    _comment.clear();
    try {
      await _live.sendChat(id, text);
    } catch (_) {}
  }

  Future<void> _end() async {
    final id = _liveId;
    if (id == null) {
      Navigator.of(context).pop();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End your LIVE?'),
        content: const Text('Viewers will be disconnected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep going')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: kLiveRed),
            child: const Text('End LIVE'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final duration = DateTime.now().difference(_startedAt ?? DateTime.now());
    final peak = _session.peakViewers;
    final likes = _likes;
    setState(() {
      _liveId = null;
      _ended = true;
    });
    _clock?.cancel();
    await _live.end(id);
    await _session.close();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _SummarySheet(duration: duration, peak: peak, likes: likes),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final live = _liveId != null;
    return PopScope(
      canPop: !live,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _end();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Colors.black,
          resizeToAvoidBottomInset: true,
          body: Stack(
            fit: StackFit.expand,
            children: [
              if (_ended)
                const ColoredBox(color: Colors.black)
              else if (_session.previewReady)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragEnd: _swipeFilter,
                  child: applyLiveFilter(
                    _filter,
                    RTCVideoView(
                      _session.localRenderer,
                      mirror: _session.frontCamera,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                )
              else
                _cameraPlaceholder(),
              if (!_ended) LiveEffectLayer(effectId: _effect),
              const _Shade(),
              if (!_ended) SafeArea(child: live ? _liveOverlay() : _setupOverlay()),
              IgnorePointer(
                child: Center(
                  child: AnimatedOpacity(
                    opacity: _flashName == null ? 0 : 1,
                    duration: const Duration(milliseconds: 180),
                    child: Text(
                      _flashName ?? '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 12)],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cameraPlaceholder() {
    final error = _session.error;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: error == null
            ? const CircularProgressIndicator(color: kLiveOrange)
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.videocam_off_rounded, color: Colors.white54, size: 48),
                  const SizedBox(height: 12),
                  Text(error,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70)),
                ],
              ),
      ),
    );
  }

  Widget _setupOverlay() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
              ),
              const Spacer(),
              Column(
                children: [
                  LiveRoundButton(icon: Icons.cameraswitch_rounded, onTap: _session.flipCamera),
                  const SizedBox(height: 12),
                  LiveRoundButton(icon: Icons.auto_awesome_rounded, onTap: _openLooks),
                ],
              ),
            ],
          ),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  children: [
                    ReelAvatar(url: _me?.photo ?? '', name: _me?.name ?? '', size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _title,
                        maxLength: 60,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                        cursorColor: kLiveOrange,
                        decoration: const InputDecoration(
                          hintText: 'Add a title to your LIVE',
                          hintStyle: TextStyle(color: Colors.white60),
                          border: InputBorder.none,
                          counterText: '',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _FilterStrip(selected: _filter, onPick: (id) => _setFilter(id, flash: true)),
              const SizedBox(height: 12),
              const Text(
                'Swipe left or right to change filter. Up to 20 viewers can watch at once. Wi‑Fi gives the best picture.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: _goLive,
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: LinearGradient(
                      colors: _session.previewReady
                          ? const [kLiveRed, kLiveOrange]
                          : const [Colors.grey, Colors.grey],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: kLiveRed.withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Center(
                    child: _starting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5),
                          )
                        : const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.sensors_rounded, color: Colors.white),
                              SizedBox(width: 8),
                              Text('Go LIVE',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900)),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _liveOverlay() {
    final elapsed = DateTime.now().difference(_startedAt ?? DateTime.now());
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.38),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    ReelAvatar(url: _me?.photo ?? '', name: _me?.name ?? '', size: 32),
                    const SizedBox(width: 8),
                    const LiveBadge(),
                    const SizedBox(width: 8),
                    Text(liveDuration(elapsed),
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                  ],
                ),
              ),
              const Spacer(),
              LiveViewerPill(count: _session.viewers),
              const SizedBox(width: 8),
              LiveRoundButton(icon: Icons.close_rounded, onTap: _end, size: 38),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            children: [
              const Icon(Icons.favorite_rounded, color: kLiveRed, size: 16),
              const SizedBox(width: 4),
              Text(reelCompact(_likes),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ],
          ),
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
                      child: LiveChatOverlay(liveId: _liveId!, hostId: _me?.uid),
                    ),
                    const SizedBox(height: 10),
                    LiveCommentField(controller: _comment, onSend: _sendComment),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingHearts(key: _hearts),
                  LiveRoundButton(
                    icon: _session.micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                    color: _session.micOn ? Colors.white : kLiveRed,
                    onTap: _session.toggleMic,
                  ),
                  const SizedBox(height: 10),
                  LiveRoundButton(icon: Icons.auto_awesome_rounded, onTap: _openLooks),
                  const SizedBox(height: 10),
                  LiveRoundButton(icon: Icons.cameraswitch_rounded, onTap: _session.flipCamera),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FilterStrip extends StatelessWidget {
  const _FilterStrip({required this.selected, required this.onPick});

  final String selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: liveFilters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final f = liveFilters[i];
          final on = f.id == selected;
          return GestureDetector(
            onTap: () => onPick(f.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? kLiveOrange : Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: on ? kLiveOrange : Colors.white24),
              ),
              child: Text(
                f.name,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Shade extends StatelessWidget {
  const _Shade();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
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
    );
  }
}

class _SummarySheet extends StatelessWidget {
  const _SummarySheet({required this.duration, required this.peak, required this.likes});

  final Duration duration;
  final int peak;
  final int likes;

  @override
  Widget build(BuildContext context) {
    Widget stat(IconData icon, String value, String label) => Expanded(
          child: Column(
            children: [
              Icon(icon, color: kLiveOrange),
              const SizedBox(height: 6),
              Text(value,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              Text(label, style: const TextStyle(color: Colors.black54, fontSize: 12.5)),
            ],
          ),
        );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('LIVE ended',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            const Text('Thanks for going live!', style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 20),
            Row(
              children: [
                stat(Icons.timer_outlined, liveDuration(duration), 'Duration'),
                stat(Icons.groups_rounded, '$peak', 'Top viewers'),
                stat(Icons.favorite_rounded, reelCompact(likes), 'Likes'),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                  backgroundColor: kLiveOrange,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
