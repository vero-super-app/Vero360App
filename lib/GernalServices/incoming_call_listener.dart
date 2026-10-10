import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vero360_app/GeneralModels/call_model.dart';
import 'package:vero360_app/GernalServices/call_service_impl.dart';
import 'package:vero360_app/GernalServices/live_call_session.dart';
import 'package:vero360_app/app_nav_key.dart';

/// Listens for Firestore ringing/incoming calls and presents the answer UI.
class IncomingCallListener {
  IncomingCallListener._();

  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  static String? _showingCallId;
  static bool _busy = false;

  static void start() {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      stop();
      return;
    }
    stop();
    // Query by recipient only (no composite index); filter ringing client-side.
    _sub = FirebaseFirestore.instance
        .collection('calls')
        .where('recipientId', isEqualTo: uid)
        .snapshots()
        .listen(_onSnap, onError: (e) {
      if (kDebugMode) debugPrint('[IncomingCall] listen error: $e');
    });
  }

  static void stop() {
    _sub?.cancel();
    _sub = null;
    _showingCallId = null;
  }

  static void _onSnap(QuerySnapshot<Map<String, dynamic>> snap) {
    if (_busy) return;
    CallSession? newest;
    final cutoff = DateTime.now().subtract(const Duration(minutes: 2));
    for (final doc in snap.docs) {
      final data = doc.data();
      final rawStatus =
          (data['status'] ?? '').toString().trim().toLowerCase();
      if (rawStatus != 'incoming' && rawStatus != 'ringing') continue;
      if (data['answeredAt'] != null) continue;
      final call = CallSession.fromFirestore(doc);
      if (call.initiatedAt.isBefore(cutoff)) continue;
      if (newest == null || call.initiatedAt.isAfter(newest.initiatedAt)) {
        newest = call;
      }
    }
    if (newest == null) return;
    if (_showingCallId == newest.id) return;
    unawaited(_present(newest));
  }

  static Future<void> _present(CallSession call) async {
    final nav = appNavKey.currentState;
    if (nav == null) return;
    _busy = true;
    _showingCallId = call.id;
    try {
      await nav.push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => _IncomingCallRingScreen(call: call),
        ),
      );
    } finally {
      _busy = false;
      if (_showingCallId == call.id) _showingCallId = null;
    }
  }
}

class _IncomingCallRingScreen extends StatefulWidget {
  const _IncomingCallRingScreen({required this.call});

  final CallSession call;

  @override
  State<_IncomingCallRingScreen> createState() =>
      _IncomingCallRingScreenState();
}

class _IncomingCallRingScreenState extends State<_IncomingCallRingScreen> {
  final _calls = CallServiceImpl();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  bool _acting = false;

  @override
  void initState() {
    super.initState();
    _sub = FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.call.id)
        .snapshots()
        .listen((snap) {
      if (!mounted || !snap.exists) return;
      final status =
          (snap.data()?['status'] ?? '').toString().trim().toLowerCase();
      if (status == 'ended' ||
          status == 'declined' ||
          status == 'missed' ||
          status == 'failed') {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _accept() async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Microphone permission is required for calls.'),
            ),
          );
          setState(() => _acting = false);
        }
        return;
      }
      final video = widget.call.callType == CallType.video;
      if (video) {
        final cam = await Permission.camera.request();
        if (!cam.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Camera permission is required for video calls.'),
              ),
            );
            setState(() => _acting = false);
          }
          return;
        }
      }
      await _calls.answerCall(widget.call.id);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => _ActiveIncomingCallScreen(
            call: widget.call.copyWith(status: CallStatus.active),
            peerName: widget.call.initiatorName ?? 'Caller',
            peerAvatarUrl: widget.call.initiatorAvatar,
            video: video,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not answer: $e')),
        );
        setState(() => _acting = false);
      }
    }
  }

  Future<void> _decline() async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      await _calls.declineCall(widget.call.id);
    } catch (_) {}
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.call.initiatorName?.trim().isNotEmpty == true
        ? widget.call.initiatorName!.trim()
        : 'Incoming call';
    final avatar = (widget.call.initiatorAvatar ?? '').trim();
    final video = widget.call.callType == CallType.video;
    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            CircleAvatar(
              radius: 54,
              backgroundColor: const Color(0xFFFF8A00).withValues(alpha: 0.25),
              backgroundImage:
                  avatar.isNotEmpty ? NetworkImage(avatar) : null,
              child: avatar.isEmpty
                  ? Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 18),
            Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              video ? 'Incoming video call' : 'Incoming voice call',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 0, 40, 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _btn(
                    color: const Color(0xFFEF4444),
                    icon: Icons.call_end_rounded,
                    label: 'Decline',
                    onTap: _acting ? null : _decline,
                  ),
                  _btn(
                    color: const Color(0xFF22C55E),
                    icon: video
                        ? Icons.videocam_rounded
                        : Icons.call_rounded,
                    label: 'Accept',
                    onTap: _acting ? null : _accept,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _btn({
    required Color color,
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return Column(
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 68,
              height: 68,
              child: Icon(icon, color: Colors.white, size: 30),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ActiveIncomingCallScreen extends StatefulWidget {
  const _ActiveIncomingCallScreen({
    required this.call,
    required this.peerName,
    required this.video,
    this.peerAvatarUrl,
  });

  final CallSession call;
  final String peerName;
  final String? peerAvatarUrl;
  final bool video;

  @override
  State<_ActiveIncomingCallScreen> createState() =>
      _ActiveIncomingCallScreenState();
}

class _ActiveIncomingCallScreenState extends State<_ActiveIncomingCallScreen> {
  final _calls = CallServiceImpl();
  late final LiveCallSession _media;
  Timer? _timer;
  int _seconds = 0;
  bool _ending = false;
  bool _micOn = true;
  bool _camOn = true;

  @override
  void initState() {
    super.initState();
    _media = LiveCallSession(
      callId: widget.call.id,
      isCaller: false,
      video: widget.video,
    );
    _media.addListener(_onMedia);
    unawaited(_media.start());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds++);
    });
  }

  void _onMedia() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _media.removeListener(_onMedia);
    unawaited(_media.hangup());
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _end() async {
    if (_ending) return;
    setState(() => _ending = true);
    try {
      await _calls.endCall(widget.call.id, _seconds);
    } catch (_) {}
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatar = (widget.peerAvatarUrl ?? '').trim();
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 28),
            Text(
              widget.video ? 'Video call' : 'Voice call',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            CircleAvatar(
              radius: 54,
              backgroundColor: const Color(0xFFFF8A00).withValues(alpha: 0.25),
              backgroundImage:
                  avatar.isNotEmpty ? NetworkImage(avatar) : null,
              child: avatar.isEmpty
                  ? Text(
                      widget.peerName.isNotEmpty
                          ? widget.peerName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 16),
            Text(
              widget.peerName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$m:$s',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _media.mediaLive
                  ? 'Live'
                  : (_media.error ?? 'Connecting audio…'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _media.error != null
                    ? const Color(0xFFF87171)
                    : const Color(0xFF22C55E),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            if (widget.video) ...[
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: LiveCallVideoPane(session: _media),
                ),
              ),
            ] else ...[
              LiveCallAudioSink(session: _media),
              const Spacer(),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Column(
                    children: [
                      Material(
                        color: const Color(0xFF2A2F3A),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () {
                            final next = !_micOn;
                            setState(() => _micOn = next);
                            unawaited(_media.setMicEnabled(next));
                          },
                          child: SizedBox(
                            width: 64,
                            height: 64,
                            child: Icon(
                              _micOn
                                  ? Icons.mic_rounded
                                  : Icons.mic_off_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _micOn ? 'Mute' : 'Unmute',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      Material(
                        color: const Color(0xFF2A2F3A),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () =>
                              unawaited(_media.setSpeaker(!_media.speakerOn)),
                          child: SizedBox(
                            width: 64,
                            height: 64,
                            child: Icon(
                              _media.speakerOn
                                  ? Icons.volume_up_rounded
                                  : Icons.hearing_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _media.speakerOn ? 'Speaker' : 'Earpiece',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                  if (widget.video)
                    Column(
                      children: [
                        Material(
                          color: const Color(0xFF2A2F3A),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () {
                              final next = !_camOn;
                              setState(() => _camOn = next);
                              unawaited(_media.setCameraEnabled(next));
                            },
                            child: SizedBox(
                              width: 64,
                              height: 64,
                              child: Icon(
                                _camOn
                                    ? Icons.videocam_rounded
                                    : Icons.videocam_off_rounded,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _camOn ? 'Camera' : 'Cam off',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  Column(
                    children: [
                      Material(
                        color: const Color(0xFFEF4444),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _ending ? null : _end,
                          child: const SizedBox(
                            width: 64,
                            height: 64,
                            child: Icon(
                              Icons.call_end_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'End',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
