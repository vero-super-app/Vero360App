import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:vero360_app/GernalServices/live_call_session.dart';
import 'package:vero360_app/features/Reels/Live/live_service.dart';
import 'package:vero360_app/features/Reels/reel_service.dart';

/// Signaling per viewer lives on `lives/{id}/viewers/{uid}`:
/// the viewer writes `session` + `answer` + `viewerIce`,
/// the host writes `offer` + `hostIce`. A new `session` means "reconnect me".

Future<void> _initWebRtc() async {
  await WebRTC.initialize(options: {
    'networkIgnoreMask': ['adapterTypeLoopback'],
  });
}

RTCIceCandidate? _iceFrom(Object? raw) {
  if (raw is! Map) return null;
  final value = (raw['candidate'] ?? '').toString().trim();
  if (value.isEmpty || !LiveCallSession.keepCandidate(value)) return null;
  final lineRaw = raw['sdpMLineIndex'];
  final line = lineRaw is num ? lineRaw.toInt() : int.tryParse('$lineRaw');
  return RTCIceCandidate(value, raw['sdpMid']?.toString(), line);
}

Map<String, dynamic> _iceMap(RTCIceCandidate c) => {
      'candidate': c.candidate,
      'sdpMid': c.sdpMid,
      'sdpMLineIndex': c.sdpMLineIndex,
    };

class _Peer {
  _Peer(this.uid, this.session, this.pc);

  final String uid;
  final String session;
  final RTCPeerConnection pc;
  final Set<String> appliedIce = {};
  final List<RTCIceCandidate> pendingIce = [];
  bool remoteSet = false;
}

/// Camera preview, then a broadcast to every viewer.
class LiveHostSession extends ChangeNotifier {
  final localRenderer = RTCVideoRenderer();

  bool previewReady = false;
  bool micOn = true;
  bool frontCamera = true;
  int viewers = 0;
  int peakViewers = 0;
  String? error;

  String? _liveId;
  MediaStream? _stream;
  final Map<String, _Peer> _peers = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  Timer? _heartbeat;
  Future<void> _queue = Future.value();
  bool _closed = false;

  final _live = LiveService.instance;

  Future<void> startPreview() async {
    try {
      await _initWebRtc();
      await localRenderer.initialize();
      if (!kIsWeb) {
        try {
          await Helper.ensureAudioSession();
        } catch (_) {}
      }
      _stream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 960},
          'height': {'ideal': 540},
          'frameRate': {'ideal': 24, 'max': 30},
        },
      });
      if (_closed) {
        await _stopStream();
        return;
      }
      localRenderer.srcObject = _stream;
      previewReady = true;
      error = null;
    } catch (e) {
      if (kDebugMode) debugPrint('[Live] preview failed: $e');
      error = 'Camera or microphone could not start. Allow access and try again.';
    }
    if (!_closed) notifyListeners();
  }

  Future<void> goLive(String liveId) async {
    _liveId = liveId;
    _sub = _live.lives
        .doc(liveId)
        .collection('viewers')
        .snapshots()
        .listen((snap) => _queue = _queue.then((_) => _onViewers(snap)), onError: (_) {});
    _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) => _live.heartbeat(liveId));
  }

  Future<void> _onViewers(QuerySnapshot<Map<String, dynamic>> snap) async {
    if (_closed) return;
    for (final change in snap.docChanges) {
      final uid = change.doc.id;
      if (change.type == DocumentChangeType.removed) {
        await _closePeer(uid);
        continue;
      }
      final data = change.doc.data() ?? const <String, dynamic>{};
      final session = (data['session'] ?? '').toString();
      if (session.isEmpty) continue;
      var peer = _peers[uid];
      if (peer == null || peer.session != session) {
        if (peer != null) await _closePeer(uid);
        if (_peers.length >= LiveService.maxViewers) continue;
        peer = await _createPeer(uid, session);
        if (peer == null) continue;
      }
      await _applyViewerData(peer, data);
    }
    final count = math.min(snap.docs.length, LiveService.maxViewers);
    if (count != viewers) {
      viewers = count;
      peakViewers = math.max(peakViewers, count);
      notifyListeners();
      final id = _liveId;
      if (id != null) unawaited(_live.setViewerCount(id, viewers, peakViewers));
    }
  }

  Future<_Peer?> _createPeer(String uid, String session) async {
    final stream = _stream;
    final liveId = _liveId;
    if (stream == null || liveId == null || _closed) return null;
    try {
      final pc = await createPeerConnection(LiveCallSession.rtcConfig());
      final peer = _Peer(uid, session, pc);
      _peers[uid] = peer;
      for (final track in stream.getTracks()) {
        await pc.addTrack(track, stream);
      }
      final doc = _live.viewerDoc(liveId, uid);
      pc.onIceCandidate = (c) {
        final value = (c.candidate ?? '').trim();
        if (_closed || value.isEmpty || !LiveCallSession.keepCandidate(value)) return;
        if (_peers[uid] != peer) return;
        unawaited(doc.update({
          'hostIce': FieldValue.arrayUnion([_iceMap(c)]),
        }).catchError((_) {}));
      };
      pc.onIceConnectionState = (state) {
        if (state == RTCIceConnectionState.RTCIceConnectionStateFailed &&
            _peers[uid] == peer) {
          // The viewer reconnects with a fresh session; drop this one.
          _queue = _queue.then((_) => _closePeer(uid));
        }
      };
      final offer = await pc.createOffer({
        'offerToReceiveAudio': false,
        'offerToReceiveVideo': false,
      });
      await pc.setLocalDescription(offer);
      await _capBitrate(pc);
      await doc.update({
        'offer': {'sdp': offer.sdp, 'type': offer.type, 'session': session},
      });
      return peer;
    } catch (e) {
      if (kDebugMode) debugPrint('[Live] peer for $uid failed: $e');
      await _closePeer(uid);
      return null;
    }
  }

  /// ~600 kbps per viewer keeps a phone on mobile data able to serve the room.
  Future<void> _capBitrate(RTCPeerConnection pc) async {
    try {
      for (final sender in await pc.getSenders()) {
        if (sender.track?.kind != 'video') continue;
        final params = sender.parameters;
        final encodings = params.encodings;
        if (encodings == null || encodings.isEmpty) continue;
        encodings[0].maxBitrate = 600000;
        encodings[0].maxFramerate = 24;
        await sender.setParameters(params);
      }
    } catch (_) {}
  }

  Future<void> _applyViewerData(_Peer peer, Map<String, dynamic> data) async {
    final answer = data['answer'];
    if (!peer.remoteSet && answer is Map && answer['session'] == peer.session) {
      final sdp = (answer['sdp'] ?? '').toString();
      if (sdp.isNotEmpty) {
        try {
          await peer.pc.setRemoteDescription(
            RTCSessionDescription(sdp, (answer['type'] ?? 'answer').toString()),
          );
          peer.remoteSet = true;
        } catch (e) {
          if (kDebugMode) debugPrint('[Live] answer failed: $e');
        }
      }
    }
    final list = data['viewerIce'];
    if (list is List) {
      for (final raw in list) {
        final ice = _iceFrom(raw);
        if (ice == null || peer.appliedIce.contains(ice.candidate)) continue;
        if (!peer.remoteSet) {
          if (!peer.pendingIce.any((c) => c.candidate == ice.candidate)) {
            peer.pendingIce.add(ice);
          }
          continue;
        }
        peer.appliedIce.add(ice.candidate!);
        try {
          await peer.pc.addCandidate(ice);
        } catch (_) {}
      }
    }
    if (peer.remoteSet && peer.pendingIce.isNotEmpty) {
      final queued = List<RTCIceCandidate>.from(peer.pendingIce);
      peer.pendingIce.clear();
      for (final ice in queued) {
        if (peer.appliedIce.contains(ice.candidate)) continue;
        peer.appliedIce.add(ice.candidate!);
        try {
          await peer.pc.addCandidate(ice);
        } catch (_) {}
      }
    }
  }

  Future<void> _closePeer(String uid) async {
    final peer = _peers.remove(uid);
    if (peer == null) return;
    try {
      await peer.pc.close();
    } catch (_) {}
  }

  Future<void> flipCamera() async {
    final track = _stream?.getVideoTracks().firstOrNull;
    if (track == null) return;
    try {
      await Helper.switchCamera(track);
      frontCamera = !frontCamera;
      notifyListeners();
    } catch (_) {}
  }

  void toggleMic() {
    micOn = !micOn;
    for (final t in _stream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = micOn;
    }
    notifyListeners();
  }

  Future<void> _stopStream() async {
    for (final t in _stream?.getTracks() ?? const <MediaStreamTrack>[]) {
      try {
        await t.stop();
      } catch (_) {}
    }
    try {
      await _stream?.dispose();
    } catch (_) {}
    _stream = null;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _heartbeat?.cancel();
    await _sub?.cancel();
    for (final uid in _peers.keys.toList()) {
      await _closePeer(uid);
    }
    await _stopStream();
    try {
      await localRenderer.dispose();
    } catch (_) {}
  }
}

/// Receives one broadcast.
class LiveViewerSession extends ChangeNotifier {
  LiveViewerSession(this.liveId);

  final String liveId;
  final remoteRenderer = RTCVideoRenderer();

  bool connected = false;
  bool hasVideo = false;
  String? error;

  RTCPeerConnection? _pc;
  String _session = '';
  String? _answeredOffer;
  bool _remoteSet = false;
  final Set<String> _appliedIce = {};
  final List<RTCIceCandidate> _pendingIce = [];
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  bool _closed = false;
  bool _rendererReady = false;
  int _retries = 0;
  Timer? _connectTimeout;

  final _live = LiveService.instance;

  DocumentReference<Map<String, dynamic>>? get _doc {
    final uid = _live.uid;
    return uid == null ? null : _live.viewerDoc(liveId, uid);
  }

  Future<void> join() async {
    final doc = _doc;
    if (doc == null) {
      error = 'Sign in to watch LIVE.';
      notifyListeners();
      return;
    }
    try {
      if (!_rendererReady) {
        await _initWebRtc();
        await remoteRenderer.initialize();
        _rendererReady = true;
      }
      if (!kIsWeb) {
        try {
          await Helper.ensureAudioSession();
          await Helper.setSpeakerphoneOn(true);
        } catch (_) {}
      }
      await _connect(doc);
    } catch (e) {
      if (kDebugMode) debugPrint('[Live] join failed: $e');
      error = 'Could not join this LIVE.';
      if (!_closed) notifyListeners();
    }
  }

  Future<void> _connect(DocumentReference<Map<String, dynamic>> doc) async {
    await _sub?.cancel();
    try {
      await _pc?.close();
    } catch (_) {}
    _remoteSet = false;
    _answeredOffer = null;
    _appliedIce.clear();
    _pendingIce.clear();
    _session = '${DateTime.now().microsecondsSinceEpoch}${math.Random().nextInt(9999)}';

    final pc = await createPeerConnection(LiveCallSession.rtcConfig());
    _pc = pc;
    pc.onTrack = (event) async {
      if (_closed) return;
      MediaStream stream;
      if (event.streams.isNotEmpty) {
        stream = event.streams.first;
      } else {
        stream = await createLocalMediaStream('live-$liveId');
        await stream.addTrack(event.track);
      }
      remoteRenderer.srcObject = stream;
      if (event.track.kind == 'video') hasVideo = true;
      notifyListeners();
    };
    final session = _session;
    pc.onIceCandidate = (c) {
      final value = (c.candidate ?? '').trim();
      if (_closed || session != _session || value.isEmpty) return;
      if (!LiveCallSession.keepCandidate(value)) return;
      unawaited(doc.update({
        'viewerIce': FieldValue.arrayUnion([_iceMap(c)]),
      }).catchError((_) {}));
    };
    pc.onIceConnectionState = (state) {
      if (_closed || session != _session) return;
      final live = state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted;
      if (live != connected) {
        connected = live;
        if (live) {
          error = null;
          _retries = 0;
          _connectTimeout?.cancel();
        }
        notifyListeners();
      }
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) _retry();
    };

    final me = await ReelService.instance.myIdentity();
    await doc.set({
      'uid': _live.uid,
      'name': me?.name ?? 'Vero360 member',
      'photo': me?.photo ?? '',
      'session': _session,
      'joinedAt': FieldValue.serverTimestamp(),
    });
    _sub = doc.snapshots().listen(_onDoc, onError: (_) {});
    _connectTimeout?.cancel();
    _connectTimeout = Timer(const Duration(seconds: 25), () {
      if (!connected && !_closed) _retry();
    });
  }

  void _retry() {
    final doc = _doc;
    if (_closed || doc == null) return;
    if (_retries >= 2) {
      error = 'Connection to this LIVE was lost.';
      notifyListeners();
      return;
    }
    _retries++;
    unawaited(_connect(doc).catchError((_) {}));
  }

  Future<void> _onDoc(DocumentSnapshot<Map<String, dynamic>> snap) async {
    final pc = _pc;
    if (_closed || pc == null || !snap.exists) return;
    final data = snap.data() ?? const <String, dynamic>{};
    final offer = data['offer'];
    if (offer is Map && offer['session'] == _session) {
      final sdp = (offer['sdp'] ?? '').toString();
      if (sdp.isNotEmpty && sdp != _answeredOffer) {
        _answeredOffer = sdp;
        try {
          await pc.setRemoteDescription(
            RTCSessionDescription(sdp, (offer['type'] ?? 'offer').toString()),
          );
          _remoteSet = true;
          final answer = await pc.createAnswer({
            'offerToReceiveAudio': true,
            'offerToReceiveVideo': true,
          });
          await pc.setLocalDescription(answer);
          await snap.reference.update({
            'answer': {'sdp': answer.sdp, 'type': answer.type, 'session': _session},
          });
        } catch (e) {
          if (kDebugMode) debugPrint('[Live] offer failed: $e');
        }
      }
    }
    final list = data['hostIce'];
    if (list is List) {
      for (final raw in list) {
        final ice = _iceFrom(raw);
        if (ice == null || _appliedIce.contains(ice.candidate)) continue;
        if (!_remoteSet) {
          if (!_pendingIce.any((c) => c.candidate == ice.candidate)) _pendingIce.add(ice);
          continue;
        }
        _appliedIce.add(ice.candidate!);
        try {
          await pc.addCandidate(ice);
        } catch (_) {}
      }
    }
    if (_remoteSet && _pendingIce.isNotEmpty) {
      final queued = List<RTCIceCandidate>.from(_pendingIce);
      _pendingIce.clear();
      for (final ice in queued) {
        if (_appliedIce.contains(ice.candidate)) continue;
        _appliedIce.add(ice.candidate!);
        try {
          await pc.addCandidate(ice);
        } catch (_) {}
      }
    }
  }

  Future<void> leave() async {
    if (_closed) return;
    _closed = true;
    _connectTimeout?.cancel();
    await _sub?.cancel();
    try {
      await _doc?.delete();
    } catch (_) {}
    try {
      await _pc?.close();
    } catch (_) {}
    try {
      await remoteRenderer.dispose();
    } catch (_) {}
  }
}
