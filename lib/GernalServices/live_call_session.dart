import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Real voice/video between the two people on a Firestore `calls/{id}` doc.
///
/// The caller writes `offer` + `callerIce`. The callee writes `answer` +
/// `calleeIce`. Media uses the Metered TURN relay so phones on mobile data
/// can still carry audio.
class LiveCallSession extends ChangeNotifier {
  LiveCallSession({
    required this.callId,
    required this.isCaller,
    required this.video,
  });

  final String callId;
  final bool isCaller;
  final bool video;

  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();

  bool ready = false;
  bool mediaLive = false;
  bool remoteVideo = false;
  bool speakerOn = true;
  String? error;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSub;
  bool _closed = false;
  bool _remoteSet = false;
  final Set<String> _appliedIce = {};
  final List<RTCIceCandidate> _pendingIce = [];
  String? _appliedAnswer;
  String? _answeredOffer;
  bool _restarted = false;

  /// Both phones sit on carrier NAT. The call uses the Metered relay and
  /// ignores direct candidates so ICE waits for that relay.
  static Map<String, dynamic> _rtcConfig() {
    const username = '781c3d2db348f03b08b1ca84';
    const credential = '1NyPN7Hm0UE6mSsD';
    Map<String, dynamic> relay(String url) => {
          'urls': url,
          'username': username,
          'credential': credential,
        };
    return {
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
      'iceTransportPolicy': 'relay',
      'continualGatheringPolicy': 'gather_continually',
      'iceServers': [
        {'urls': 'stun:stun.relay.metered.ca:80'},
        relay('turn:global.relay.metered.ca:80'),
        relay('turn:global.relay.metered.ca:80?transport=tcp'),
        relay('turn:global.relay.metered.ca:443'),
        relay('turns:global.relay.metered.ca:443?transport=tcp'),
      ],
    };
  }

  /// Same relay setup for Reels LIVE broadcasts.
  static Map<String, dynamic> rtcConfig() => _rtcConfig();
  static bool keepCandidate(String value) => _keepCandidate(value);

  static bool _keepCandidate(String value) {
    final v = value.toLowerCase();
    if (v.contains(' 127.') ||
        v.contains(' ::1') ||
        v.contains(' 0.0.0.0') ||
        v.contains(' fec0:') ||
        v.contains(' fe80:')) {
      return false;
    }
    return true;
  }

  DocumentReference<Map<String, dynamic>> get _doc =>
      FirebaseFirestore.instance.collection('calls').doc(callId);

  Future<void> start() async {
    if (_closed || ready) return;
    try {
      // Loopback was the only interface TURN allocated on, so the relay
      // packet never left the phone. Ignore it before the first socket opens.
      await WebRTC.initialize(options: {
        'networkIgnoreMask': ['adapterTypeLoopback'],
      });
      await localRenderer.initialize();
      await remoteRenderer.initialize();
      if (_closed) return;

      if (!kIsWeb) {
        try {
          await Helper.ensureAudioSession();
        } catch (_) {}
      }

      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': video
            ? {
                'facingMode': 'user',
                'width': {'ideal': 640},
                'height': {'ideal': 480},
              }
            : false,
      });
      if (_closed) {
        for (final track in _localStream?.getTracks() ?? const <MediaStreamTrack>[]) {
          await track.stop();
        }
        await _localStream?.dispose();
        _localStream = null;
        return;
      }
      localRenderer.srcObject = _localStream;

      _pc = await createPeerConnection(_rtcConfig());
      if (_closed) return;

      for (final track in _localStream!.getTracks()) {
        await _pc!.addTrack(track, _localStream!);
      }

      _pc!.onTrack = (event) async {
        if (_closed) return;
        final track = event.track;
        track.enabled = true;
        MediaStream stream;
        if (event.streams.isNotEmpty) {
          stream = event.streams.first;
        } else {
          stream = await createLocalMediaStream('remote-$callId');
          await stream.addTrack(track);
        }
        if (_closed) return;
        remoteRenderer.srcObject = stream;
        if (track.kind == 'video') remoteVideo = true;
        notifyListeners();
      };

      _pc!.onIceCandidate = (RTCIceCandidate candidate) {
        final value = (candidate.candidate ?? '').trim();
        if (_closed || value.isEmpty || !_keepCandidate(value)) return;
        unawaited(_publishIce(value, candidate.sdpMid, candidate.sdpMLineIndex));
      };

      _pc!.onIceConnectionState = (state) {
        if (_closed) return;
        final live = state ==
                RTCIceConnectionState.RTCIceConnectionStateConnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateCompleted;
        if (live && !mediaLive) {
          mediaLive = true;
          error = null;
          unawaited(setSpeaker(speakerOn));
          notifyListeners();
        } else if (!live && mediaLive) {
          mediaLive = false;
          notifyListeners();
        }
        if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          if (isCaller && !_restarted) {
            unawaited(_restartIce());
          } else if (error == null) {
            error = 'Could not open the audio path. Try again on Wi‑Fi.';
            notifyListeners();
          }
        }
      };

      _docSub = _doc.snapshots().listen(_onDoc, onError: (_) {});

      if (isCaller) {
        final offer = await _pc!.createOffer({
          'offerToReceiveAudio': true,
          'offerToReceiveVideo': video,
        });
        if (_closed) return;
        await _pc!.setLocalDescription(offer);
        await _doc.update({
          'offer': {'sdp': offer.sdp, 'type': offer.type},
        });
      }

      await setSpeaker(true);
      ready = true;
      error = null;
      notifyListeners();
    } catch (e) {
      if (_closed) return;
      error = 'Microphone or camera could not start.';
      if (kDebugMode) debugPrint('[LiveCall] start failed: $e');
      notifyListeners();
    }
  }

  Future<void> _onDoc(DocumentSnapshot<Map<String, dynamic>> snap) async {
    if (_closed || !snap.exists || _pc == null) return;
    final data = snap.data() ?? const <String, dynamic>{};

    if (isCaller) {
      final answer = data['answer'];
      if (answer is Map) {
        final sdp = (answer['sdp'] ?? '').toString();
        final type = (answer['type'] ?? 'answer').toString();
        if (sdp.isNotEmpty && sdp != _appliedAnswer) {
          _appliedAnswer = sdp;
          _remoteSet = true;
          await _pc!.setRemoteDescription(RTCSessionDescription(sdp, type));
          await _flushPendingIce();
        }
      }
    } else {
      final offer = data['offer'];
      if (offer is Map) {
        final sdp = (offer['sdp'] ?? '').toString();
        final type = (offer['type'] ?? 'offer').toString();
        if (sdp.isNotEmpty && sdp != _answeredOffer) {
          _answeredOffer = sdp;
          await _pc!.setRemoteDescription(RTCSessionDescription(sdp, type));
          _remoteSet = true;
          await _flushPendingIce();
          final answer = await _pc!.createAnswer({
            'offerToReceiveAudio': true,
            'offerToReceiveVideo': video,
          });
          if (_closed) return;
          await _pc!.setLocalDescription(answer);
          await _doc.update({
            'answer': {'sdp': answer.sdp, 'type': answer.type},
          });
        }
      }
    }

    final iceKey = isCaller ? 'calleeIce' : 'callerIce';
    final rawList = data[iceKey];
    if (rawList is List) {
      for (final raw in rawList) {
        if (raw is! Map) continue;
        final value = (raw['candidate'] ?? '').toString().trim();
        if (value.isEmpty ||
            !_keepCandidate(value) ||
            _appliedIce.contains(value)) {
          continue;
        }
        final mid = raw['sdpMid']?.toString();
        final lineRaw = raw['sdpMLineIndex'];
        final line = lineRaw is num ? lineRaw.toInt() : int.tryParse('$lineRaw');
        final ice = RTCIceCandidate(value, mid, line);
        if (!_remoteSet) {
          if (!_pendingIce.any((c) => c.candidate == value)) {
            _pendingIce.add(ice);
          }
          continue;
        }
        _appliedIce.add(value);
        try {
          await _pc?.addCandidate(ice);
        } catch (_) {}
      }
    }
  }

  Future<void> _publishIce(String value, String? sdpMid, int? line) async {
    try {
      await _doc.update({
        isCaller ? 'callerIce' : 'calleeIce': FieldValue.arrayUnion([
          {
            'candidate': value,
            'sdpMid': sdpMid,
            'sdpMLineIndex': line,
          },
        ]),
      });
    } catch (_) {}
  }

  Future<void> _restartIce() async {
    if (_closed || _restarted || _pc == null) return;
    _restarted = true;
    error = null;
    notifyListeners();
    try {
      _remoteSet = false;
      _appliedIce.clear();
      _pendingIce.clear();
      await _pc!.restartIce();
      if (!isCaller || _closed) return;
      final offer = await _pc!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': video,
        'iceRestart': true,
      });
      if (_closed) return;
      await _pc!.setLocalDescription(offer);
      await _doc.update({
        'offer': {'sdp': offer.sdp, 'type': offer.type},
        'answer': FieldValue.delete(),
      });
      _appliedAnswer = null;
    } catch (e) {
      if (_closed) return;
      error = 'Could not open the audio path. Try again on Wi‑Fi.';
      if (kDebugMode) debugPrint('[LiveCall] restart failed: $e');
      notifyListeners();
    }
  }

  Future<void> _flushPendingIce() async {
    final queued = List<RTCIceCandidate>.from(_pendingIce);
    _pendingIce.clear();
    for (final ice in queued) {
      final value = (ice.candidate ?? '').trim();
      if (value.isEmpty || _appliedIce.contains(value)) continue;
      _appliedIce.add(value);
      try {
        await _pc?.addCandidate(ice);
      } catch (_) {}
    }
  }

  Future<void> setMicEnabled(bool enabled) async {
    final stream = _localStream;
    if (stream == null) return;
    for (final track in stream.getAudioTracks()) {
      track.enabled = enabled;
      try {
        await Helper.setMicrophoneMute(!enabled, track);
      } catch (_) {}
    }
  }

  Future<void> setCameraEnabled(bool enabled) async {
    final stream = _localStream;
    if (stream == null) return;
    for (final track in stream.getVideoTracks()) {
      track.enabled = enabled;
    }
    notifyListeners();
  }

  Future<void> setSpeaker(bool on) async {
    speakerOn = on;
    try {
      if (!kIsWeb) await Helper.setSpeakerphoneOn(on);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> hangup() async {
    if (_closed) return;
    _closed = true;
    await _docSub?.cancel();
    _docSub = null;
    try {
      for (final track in _localStream?.getTracks() ?? const <MediaStreamTrack>[]) {
        await track.stop();
      }
      await _localStream?.dispose();
      _localStream = null;
      await _pc?.close();
      _pc = null;
    } catch (_) {}
    try {
      await localRenderer.dispose();
    } catch (_) {}
    try {
      await remoteRenderer.dispose();
    } catch (_) {}
  }
}

/// Keeps the remote audio track attached on voice calls (no video view).
class LiveCallAudioSink extends StatelessWidget {
  const LiveCallAudioSink({super.key, required this.session});

  final LiveCallSession session;

  @override
  Widget build(BuildContext context) {
    if (!session.ready) return const SizedBox.shrink();
    return Offstage(
      offstage: true,
      child: SizedBox(
        width: 1,
        height: 1,
        child: RTCVideoView(session.remoteRenderer),
      ),
    );
  }
}

/// Remote picture with a small self view. Used on video calls.
class LiveCallVideoPane extends StatelessWidget {
  const LiveCallVideoPane({super.key, required this.session});

  final LiveCallSession session;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (session.remoteVideo)
          RTCVideoView(
            session.remoteRenderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          )
        else
          const ColoredBox(
            color: Color(0xFF1A1D24),
            child: Center(
              child: Icon(Icons.person_rounded, color: Colors.white38, size: 72),
            ),
          ),
        if (session.ready)
          Positioned(
            right: 12,
            bottom: 12,
            width: 108,
            height: 148,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: ColoredBox(
                color: const Color(0xFF111111),
                child: RTCVideoView(
                  session.localRenderer,
                  mirror: true,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
