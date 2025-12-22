// lib/Pages/Home/Messages.dart
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:vero360_app/services/chat_service.dart';

class MessagePage extends StatefulWidget {
  final String peerAppId; // REQUIRED: app user id of the seller
  final String? peerName;
  final String? peerAvatarUrl;

  // legacy/unused (kept so old call-sites don’t break)
  final String? peerId;

  const MessagePage({
    super.key,
    required this.peerAppId,
    this.peerName,
    this.peerAvatarUrl,
    this.peerId,
  });

  @override
  State<MessagePage> createState() => _MessagePageState();
}

class _MessagePageState extends State<MessagePage> {
  String? _me;

  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _picker = ImagePicker();

  // Voice notes (record v6+ uses AudioRecorder) :contentReference[oaicite:4]{index=4}
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _recTimer;
  bool _recording = false;
  int _recordMs = 0;

  final List<_PendingImage> _pendingImages = [];
  bool _sending = false;
  double? _uploadProgress; // 0..1

  static const _brandGreen = Color(0xFF1FA855);
  static const _bg = Color(0xFFF3F4F7);

  // We keep ChatService unchanged by sending media as text
  // Images: "img::<downloadUrl>\noptional caption"
  static const String _imgPrefix = 'img::';

  // Audio: "aud::<downloadUrl>|<durationMs>"
  static const String _audPrefix = 'aud::';

  // Calls: "call::<audio|video>::<callDocId>"
  static const String _callPrefix = 'call::';

  @override
  void initState() {
    super.initState();
    _boot();

    _input.addListener(() {
      if (!mounted) return;
      setState(() {});
    });
  }

  Future<void> _boot() async {
    await ChatService.ensureFirebaseAuth();
    final me = await ChatService.myAppUserId();

    if (!mounted) return;
    setState(() => _me = me);

    await ChatService.ensureThread(
      myAppId: me,
      peerAppId: widget.peerAppId,
      peerName: widget.peerName,
      peerAvatar: widget.peerAvatarUrl,
    );
  }

  @override
  void dispose() {
    _recTimer?.cancel();
    _recorder.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String get _threadId => ChatService.threadIdForApp(_me!, widget.peerAppId);

  // -------------------- Message parsers --------------------
  bool _isImageMsg(String txt) => txt.trimLeft().startsWith(_imgPrefix);
  bool _isAudioMsg(String txt) => txt.trimLeft().startsWith(_audPrefix);
  bool _isCallMsg(String txt) => txt.trimLeft().startsWith(_callPrefix);

  String _imgUrl(String txt) {
    final firstLine = txt.split('\n').first;
    return firstLine.trim().substring(_imgPrefix.length).trim();
  }

  String _imgCaption(String txt) {
    final parts = txt.split('\n');
    if (parts.length <= 1) return '';
    return parts.sublist(1).join('\n').trim();
  }

  String _audUrl(String txt) {
    final body = txt.trim().substring(_audPrefix.length).trim();
    final parts = body.split('|');
    return parts.first.trim();
  }

  int _audMs(String txt) {
    final body = txt.trim().substring(_audPrefix.length).trim();
    final parts = body.split('|');
    if (parts.length < 2) return 0;
    return int.tryParse(parts[1].trim()) ?? 0;
  }

  String _callType(String txt) {
    final body = txt.trim().substring(_callPrefix.length).trim(); // audio::id
    final parts = body.split('::');
    return parts.isNotEmpty ? parts[0].trim() : 'audio';
  }

  String _callId(String txt) {
    final body = txt.trim().substring(_callPrefix.length).trim();
    final parts = body.split('::');
    return parts.length >= 2 ? parts[1].trim() : '';
  }

  // -------------------- Pick images --------------------
  Future<void> _pickFromGallery() async {
    try {
      final files = await _picker.pickMultiImage(
        imageQuality: 88,
        maxWidth: 2048,
      );
      if (files.isEmpty) return;

      final remaining = max(0, 8 - _pendingImages.length);
      if (remaining <= 0) {
        _toast('You can select up to 8 photos');
        return;
      }

      final take = files.take(remaining).toList();
      for (final x in take) {
        final bytes = await x.readAsBytes();
        _pendingImages.add(
          _PendingImage(
            bytes: bytes,
            filename: x.name.isEmpty ? 'image.jpg' : x.name,
            mime: lookupMimeType(x.name, headerBytes: bytes) ?? 'image/jpeg',
          ),
        );
      }
      if (!mounted) return;
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      _toast('Could not pick images');
    }
  }

  Future<void> _pickFromCamera() async {
    try {
      final x = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
        maxWidth: 2048,
      );
      if (x == null) return;

      final bytes = await x.readAsBytes();
      _pendingImages.add(
        _PendingImage(
          bytes: bytes,
          filename: x.name.isEmpty ? 'camera.jpg' : x.name,
          mime: lookupMimeType(x.name, headerBytes: bytes) ?? 'image/jpeg',
        ),
      );

      if (!mounted) return;
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      _toast('Camera not available');
    }
  }

  void _removePending(int index) {
    if (index < 0 || index >= _pendingImages.length) return;
    setState(() => _pendingImages.removeAt(index));
  }

  void _showAttachSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _attachTile(
                      icon: Icons.photo_library_rounded,
                      title: 'Gallery',
                      subtitle: 'Upload photos',
                      color: _brandGreen,
                      onTap: () {
                        Navigator.pop(context);
                        _pickFromGallery();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _attachTile(
                      icon: Icons.photo_camera_rounded,
                      title: 'Camera',
                      subtitle: 'Take a photo',
                      color: const Color(0xFF16284C),
                      onTap: () {
                        Navigator.pop(context);
                        _pickFromCamera();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_pendingImages.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    setState(() => _pendingImages.clear());
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text(
                    'Clear selected',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.black12),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------- Upload helpers --------------------
  Future<String> _uploadBytesToFirebase({
    required Uint8List bytes,
    required String folder,
    required String filename,
    required String mime,
  }) async {
    final me = _me!;
    final tid = _threadId;

    final ext = _safeExt(filename, mime);
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final rand = _rand(6);
    final path = '$folder/$tid/$me/$id-$rand.$ext';

    final ref = FirebaseStorage.instance.ref().child(path);
    final task = ref.putData(bytes, SettableMetadata(contentType: mime));

    task.snapshotEvents.listen((snap) {
      final total = snap.totalBytes;
      if (total <= 0) return;
      final p = snap.bytesTransferred / total;
      if (!mounted) return;
      setState(() => _uploadProgress = p.clamp(0, 1));
    });

    await task;
    return await ref.getDownloadURL();
  }

  // -------------------- Send (text + images) --------------------
  Future<void> _send() async {
    if (_me == null) return;
    if (_sending) return;

    final caption = _input.text.trim();
    final hasPics = _pendingImages.isNotEmpty;

    if (!hasPics && caption.isEmpty) return;

    setState(() {
      _sending = true;
      _uploadProgress = null;
    });

    try {
      if (hasPics) {
        for (final img in _pendingImages) {
          final url = await _uploadBytesToFirebase(
            bytes: img.bytes,
            folder: 'chat_media',
            filename: img.filename,
            mime: img.mime,
          );

          // ✅ IMPORTANT: no space after $  (this fixes your error)
          final text = '$_imgPrefix$url${caption.isEmpty ? '' : '\n$caption'}';

          await ChatService.sendMessage(
            myAppId: _me!,
            peerAppId: widget.peerAppId,
            text: text,
          );
        }

        _pendingImages.clear();
        _input.clear();
      } else {
        _input.clear();
        await ChatService.sendMessage(
          myAppId: _me!,
          peerAppId: widget.peerAppId,
          text: caption,
        );
      }

      if (!mounted) return;
      setState(() => _uploadProgress = null);
      _jumpToBottom();
    } catch (_) {
      if (!mounted) return;
      _toast('Failed to send');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // -------------------- Voice notes --------------------
  String _formatMs(int ms) {
    final s = (ms / 1000).floor();
    final m = (s / 60).floor();
    final r = s % 60;
    return '${m.toString().padLeft(1, '0')}:${r.toString().padLeft(2, '0')}';
  }

  Future<void> _startVoiceRecording() async {
    if (_me == null) return;
    if (_sending) return;

    if (kIsWeb) {
      _toast('Voice notes: web not enabled in this build');
      return;
    }

    try {
      final ok = await _recorder.hasPermission();
      if (!ok) {
        _toast('Microphone permission denied');
        return;
      }

      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      // record package v6 API :contentReference[oaicite:5]{index=5}
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );

      _recTimer?.cancel();
      _recordMs = 0;

      setState(() => _recording = true);
      _recTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted) return;
        setState(() => _recordMs += 200);
      });
    } catch (_) {
      _toast('Could not start recording');
    }
  }

  Future<void> _cancelVoiceRecording() async {
    try {
      _recTimer?.cancel();
      await _recorder.cancel(); // removes file/blob :contentReference[oaicite:6]{index=6}
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recordMs = 0;
    });
  }

  Future<void> _stopVoiceRecordingAndSend() async {
    if (_me == null) return;
    if (!_recording) return;

    _recTimer?.cancel();

    setState(() {
      _sending = true;
      _uploadProgress = null;
    });

    try {
      final path = await _recorder.stop(); // returns path :contentReference[oaicite:7]{index=7}
      if (path == null || path.isEmpty) {
        _toast('Recording failed');
        setState(() {
          _recording = false;
          _recordMs = 0;
          _sending = false;
        });
        return;
      }

      final bytes = await File(path).readAsBytes();
      final url = await _uploadBytesToFirebase(
        bytes: bytes,
        folder: 'chat_audio',
        filename: 'voice.m4a',
        mime: 'audio/mp4',
      );

      final text = '$_audPrefix$url|$_recordMs';

      await ChatService.sendMessage(
        myAppId: _me!,
        peerAppId: widget.peerAppId,
        text: text,
      );

      if (!mounted) return;
      setState(() {
        _recording = false;
        _recordMs = 0;
        _uploadProgress = null;
      });
      _jumpToBottom();
    } catch (_) {
      _toast('Failed to send voice note');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openAudioUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // -------------------- Call / Video call signaling (skeleton) --------------------
  Future<void> _startCall({required String type}) async {
    if (_me == null) return;

    try {
      final callDoc = FirebaseFirestore.instance.collection('calls').doc();
      await callDoc.set({
        'threadId': _threadId,
        'callerId': _me,
        'calleeId': widget.peerAppId,
        'type': type, // audio | video
        'status': 'ringing',
        'createdAt': FieldValue.serverTimestamp(),
      });

      await ChatService.sendMessage(
        myAppId: _me!,
        peerAppId: widget.peerAppId,
        text: '$_callPrefix$type::${callDoc.id}',
      );

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _CallPlaceholderScreen(
            callId: callDoc.id,
            type: type,
            peerName: widget.peerName ?? 'User',
          ),
        ),
      );
    } catch (_) {
      _toast('Could not start $type call');
    }
  }

  // -------------------- UI helpers --------------------
  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _rand(int len) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random();
    return List.generate(len, (_) => chars[r.nextInt(chars.length)]).join();
  }

  String _safeExt(String filename, String mime) {
    final lower = filename.toLowerCase();
    if (lower.contains('.')) {
      final ext = lower.split('.').last.trim();
      if (ext.isNotEmpty && ext.length <= 5) return ext;
    }
    if (mime.contains('png')) return 'png';
    if (mime.contains('webp')) return 'webp';
    if (mime.contains('m4a') || mime.contains('mp4')) return 'm4a';
    if (mime.contains('aac')) return 'aac';
    return 'jpg';
  }

  DateTime? _extractTime(ChatMessage m) {
    try {
      final dyn = (m as dynamic).createdAt;
      if (dyn is DateTime) return dyn;
      if (dyn is Timestamp) return dyn.toDate();
      if (dyn is int) return DateTime.fromMillisecondsSinceEpoch(dyn);
    } catch (_) {}
    try {
      final dyn = (m as dynamic).timestamp;
      if (dyn is DateTime) return dyn;
      if (dyn is Timestamp) return dyn.toDate();
      if (dyn is int) return DateTime.fromMillisecondsSinceEpoch(dyn);
    } catch (_) {}
    return null;
  }

  String _timeLabel(ChatMessage m) {
    final t = _extractTime(m);
    if (t == null) return '';
    return DateFormat('HH:mm').format(t);
  }

  void _viewImage(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(14),
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(
                child: Image.network(url, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => Navigator.pop(context),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.close, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.peerName ?? 'Chat';

    final canSend = !_sending &&
        (_input.text.trim().isNotEmpty || _pendingImages.isNotEmpty);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        titleSpacing: 0,
        title: Row(
          children: [
            const SizedBox(width: 6),
            _avatar(widget.peerAvatarUrl),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: const [
                      Icon(Icons.circle, size: 8, color: Color(0xFF39C16C)),
                      SizedBox(width: 6),
                      Text(
                        'Online',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: _me == null ? null : () => _startCall(type: 'audio'),
              icon: const Icon(Icons.call),
            ),
            IconButton(
              onPressed: _me == null ? null : () => _startCall(type: 'video'),
              icon: const Icon(Icons.videocam),
            ),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.more_vert_rounded),
            ),
          ],
        ),
      ),
      body: _me == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Positioned.fill(child: CustomPaint(painter: _ChatBgPainter())),
                Column(
                  children: [
                    Expanded(
                      child: StreamBuilder<List<ChatMessage>>(
                        stream: ChatService.messagesStream(_threadId, myAppId: '', peerAppId: ''),
                        builder: (context, snap) {
                          if (snap.hasError) {
                            return Center(
                              child: Text(
                                'Messages unavailable\n${snap.error}',
                                textAlign: TextAlign.center,
                              ),
                            );
                          }

                          final msgs = snap.data ?? const <ChatMessage>[];
                          if (msgs.isEmpty) {
                            return const Center(
                              child: Text(
                                'Say hi 👋',
                                style: TextStyle(
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            );
                          }

                          final rev = msgs.reversed.toList();

                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (_scroll.hasClients && _scroll.offset > 40) return;
                            _jumpToBottom();
                          });

                          return ListView.builder(
                            controller: _scroll,
                            reverse: true,
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                            itemCount: rev.length,
                            itemBuilder: (_, i) {
                              final m = rev[i];
                              final mine = m.isMine(_me!);
                              final time = _timeLabel(m);

                              final txt = m.text;

                              if (_isImageMsg(txt)) {
                                final url = _imgUrl(txt);
                                return _MessageBubble(
                                  mine: mine,
                                  time: time,
                                  child: _ImageBubble(
                                    url: url,
                                    caption: _imgCaption(txt),
                                    onTap: () => _viewImage(url),
                                  ),
                                );
                              }

                              if (_isAudioMsg(txt)) {
                                final url = _audUrl(txt);
                                final ms = _audMs(txt);
                                return _MessageBubble(
                                  mine: mine,
                                  time: time,
                                  child: _AudioBubble(
                                    duration: _formatMs(ms),
                                    onTap: () => _openAudioUrl(url),
                                  ),
                                );
                              }

                              if (_isCallMsg(txt)) {
                                final type = _callType(txt);
                                final callId = _callId(txt);
                                return _MessageBubble(
                                  mine: mine,
                                  time: time,
                                  child: _CallBubble(
                                    type: type,
                                    callId: callId,
                                  ),
                                );
                              }

                              return _MessageBubble(
                                mine: mine,
                                time: time,
                                child: Text(
                                  txt,
                                  style: TextStyle(
                                    color: mine ? Colors.white : Colors.black87,
                                    fontWeight: FontWeight.w600,
                                    height: 1.25,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_uploadProgress != null)
                            LinearProgressIndicator(
                              value: _uploadProgress,
                              minHeight: 3,
                              backgroundColor: Colors.black12,
                            ),
                          if (_pendingImages.isNotEmpty) _buildSelectedImages(),
                          if (_recording) _recordingBar(),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                            child: Row(
                              children: [
                                Material(
                                  color: Colors.white,
                                  shape: const CircleBorder(),
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: _sending ? null : _showAttachSheet,
                                    child: const SizedBox(
                                      width: 44,
                                      height: 44,
                                      child: Center(
                                        child: Icon(Icons.add_rounded),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(22),
                                      border: Border.all(color: Colors.black12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.04),
                                          blurRadius: 12,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: TextField(
                                            controller: _input,
                                            minLines: 1,
                                            maxLines: 4,
                                            textInputAction: TextInputAction.send,
                                            onSubmitted: (_) => _send(),
                                            decoration: const InputDecoration(
                                              hintText: 'Message…',
                                              border: InputBorder.none,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          onPressed: _sending ? null : _showAttachSheet,
                                          icon: const Icon(Icons.attach_file),
                                          color: Colors.black54,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // Send OR Mic (WhatsApp style)
                                if (canSend)
                                  _sendButton()
                                else
                                  _micButton(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _recordingBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          const Icon(Icons.mic, color: Colors.red),
          const SizedBox(width: 10),
          Text(
            'Recording  ${_formatMs(_recordMs)}',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const Spacer(),
          TextButton(
            onPressed: _sending ? null : _cancelVoiceRecording,
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 6),
          ElevatedButton(
            onPressed: _sending ? null : _stopVoiceRecordingAndSend,
            style: ElevatedButton.styleFrom(
              backgroundColor: _brandGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  Widget _micButton() {
    return GestureDetector(
      onLongPressStart: (_) => _startVoiceRecording(),
      onLongPressEnd: (_) => _stopVoiceRecordingAndSend(),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: _brandGreen,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: _brandGreen.withOpacity(0.25),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: const Icon(Icons.mic, color: Colors.white),
      ),
    );
  }

  Widget _buildSelectedImages() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: SizedBox(
        height: 86,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _pendingImages.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            if (i == _pendingImages.length) {
              return InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: _sending ? null : _pickFromGallery,
                child: Container(
                  width: 86,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: const Center(
                    child: Icon(Icons.add_photo_alternate_outlined,
                        color: Colors.black54),
                  ),
                ),
              );
            }

            final img = _pendingImages[i];
            return Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.memory(
                    img.bytes,
                    width: 86,
                    height: 86,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: InkWell(
                    onTap: _sending ? null : () => _removePending(i),
                    child: const CircleAvatar(
                      radius: 12,
                      backgroundColor: Colors.black54,
                      child: Icon(Icons.close, size: 14, color: Colors.white),
                    ),
                  ),
                )
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _sendButton() {
    final canSend = !_sending &&
        (_input.text.trim().isNotEmpty || _pendingImages.isNotEmpty);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: canSend ? _brandGreen : Colors.black12,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          if (canSend)
            BoxShadow(
              color: _brandGreen.withOpacity(0.25),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: IconButton(
        onPressed: canSend ? _send : null,
        icon: _sending
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.send_rounded, color: Colors.white),
      ),
    );
  }

  Widget _avatar(String? url) {
    final u = (url ?? '').trim();
    if (u.isNotEmpty) {
      return CircleAvatar(radius: 18, backgroundImage: NetworkImage(u));
    }
    return const CircleAvatar(
      radius: 18,
      backgroundColor: Color(0xFFEDEFF3),
      child: Icon(Icons.person, size: 18, color: Colors.black54),
    );
  }
}

// -------------------- Bubbles --------------------
class _MessageBubble extends StatelessWidget {
  final bool mine;
  final String time;
  final Widget child;

  const _MessageBubble({
    required this.mine,
    required this.time,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.of(context).size.width * (kIsWeb ? 0.58 : 0.76);

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          decoration: BoxDecoration(
            gradient: mine
                ? const LinearGradient(
                    colors: [Color(0xFF1FA855), Color(0xFF169A74)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: mine ? null : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(mine ? 18 : 6),
              bottomRight: Radius.circular(mine ? 6 : 18),
            ),
            border: mine ? null : Border.all(color: Colors.black12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              child,
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    time,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: mine ? Colors.white70 : Colors.black45,
                    ),
                  ),
                  if (mine) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.done_all,
                        size: 14, color: Colors.white70),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageBubble extends StatelessWidget {
  final String url;
  final String caption;
  final VoidCallback onTap;

  const _ImageBubble({
    required this.url,
    required this.caption,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 1.2,
              child: Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.black12,
                  child: const Center(child: Icon(Icons.broken_image_outlined)),
                ),
                loadingBuilder: (_, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    color: Colors.black12,
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        if (caption.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            caption,
            style: const TextStyle(fontWeight: FontWeight.w600, height: 1.25),
          ),
        ],
      ],
    );
  }
}

class _AudioBubble extends StatelessWidget {
  final String duration;
  final VoidCallback onTap;

  const _AudioBubble({
    required this.duration,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.play_arrow_rounded),
            const SizedBox(width: 10),
            Text(
              'Voice note • $duration',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallBubble extends StatelessWidget {
  final String type; // audio|video
  final String callId;

  const _CallBubble({required this.type, required this.callId});

  @override
  Widget build(BuildContext context) {
    final icon = type == 'video' ? Icons.videocam : Icons.call;
    final label = type == 'video' ? 'Video call' : 'Voice call';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon),
          const SizedBox(width: 10),
          Text(
            '$label • id: ${callId.isEmpty ? '—' : callId.substring(0, min(6, callId.length))}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

// -------------------- Background painter --------------------
class _ChatBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFFF3F4F7);
    canvas.drawRect(Offset.zero & size, bgPaint);

    final dotPaint = Paint()..color = Colors.black.withOpacity(0.03);
    const step = 22.0;
    for (double y = 8; y < size.height; y += step) {
      for (double x = 8; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1.2, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// -------------------- Pending image model --------------------
class _PendingImage {
  final Uint8List bytes;
  final String filename;
  final String mime;

  const _PendingImage({
    required this.bytes,
    required this.filename,
    required this.mime,
  });
}

// -------------------- Call placeholder screen --------------------
class _CallPlaceholderScreen extends StatelessWidget {
  final String callId;
  final String type;
  final String peerName;

  const _CallPlaceholderScreen({
    required this.callId,
    required this.type,
    required this.peerName,
  });

  @override
  Widget build(BuildContext context) {
    final label = type == 'video' ? 'Video calling' : 'Calling';
    final icon = type == 'video' ? Icons.videocam : Icons.call;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('$label $peerName'),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 72),
            const SizedBox(height: 14),
            Text(
              '$label…',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              'Signaling only (WebRTC not implemented yet)',
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
            ),
            const SizedBox(height: 22),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              icon: const Icon(Icons.call_end),
              label: const Text('End'),
            ),
          ],
        ),
      ),
    );
  }
}
