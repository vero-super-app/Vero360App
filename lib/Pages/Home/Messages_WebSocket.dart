import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:vero360_app/services/chat_service.dart';
import 'package:vero360_app/services/hybrid_chat_service.dart';
import 'package:vero360_app/models/messaging_models.dart';
import 'package:vero360_app/providers/messaging/messaging_provider.dart';

class MessagePageWebSocket extends ConsumerStatefulWidget {
  final String peerAppId;
  final String? peerName;
  final String? peerAvatarUrl;
  final String? peerId;

  const MessagePageWebSocket({
    super.key,
    required this.peerAppId,
    this.peerName,
    this.peerAvatarUrl,
    this.peerId,
  });

  @override
  ConsumerState<MessagePageWebSocket> createState() =>
      _MessagePageWebSocketState();
}

class _MessagePageWebSocketState extends ConsumerState<MessagePageWebSocket> {
  String? _me;
  late String _threadId;
  late HybridChatService _hybrid;

  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _picker = ImagePicker();

  // Voice notes
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _recTimer;
  bool _recording = false;
  int _recordMs = 0;

  bool _sending = false;
  double? _uploadProgress;

  static const _brandGreen = Color(0xFF1FA855);
  static const _bg = Color(0xFFF3F4F7);
  static const String _imgPrefix = 'img::';
  static const String _audPrefix = 'aud::';

  Timer? _typingDebounceTimer;
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    _boot();

    _input.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _input.removeListener(_onInputChanged);
    _input.dispose();
    _scroll.dispose();
    _recTimer?.cancel();
    _typingDebounceTimer?.cancel();
    _stopTyping();
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      await ChatService.ensureFirebaseAuth();
      final me = await ChatService.myAppUserId();
      _threadId = ChatService.threadIdForApp(me, widget.peerAppId);

      setState(() => _me = me);

      // Initialize hybrid service
      _hybrid = HybridChatService(webSocketService: null);

      // Ensure thread exists
      await _hybrid.ensureThread(
        myAppId: me,
        peerAppId: widget.peerAppId,
        peerName: widget.peerName,
        peerAvatar: widget.peerAvatarUrl,
      );

      // Mark as read
      await ChatService.markThreadRead(
          myAppId: me, peerAppId: widget.peerAppId);

      // Join chat room
      await _hybrid.joinChat(_threadId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${ChatService.friendlyError(e)}')),
        );
      }
    }
  }

  void _onInputChanged() {
    if (_input.text.isEmpty) {
      _stopTyping();
      return;
    }

    if (!_isTyping) {
      _startTyping();
    }

    // Debounce stop typing
    _typingDebounceTimer?.cancel();
    _typingDebounceTimer = Timer(const Duration(seconds: 2), _stopTyping);
  }

  void _startTyping() {
    if (_isTyping) return;
    _isTyping = true;
    _hybrid.sendTypingIndicator(chatId: _threadId, isTyping: true);
  }

  void _stopTyping() {
    if (!_isTyping) return;
    _isTyping = false;
    _hybrid.sendTypingIndicator(chatId: _threadId, isTyping: false);
  }

  Future<void> _sendMessage() async {
    if (_input.text.isEmpty) return;

    final text = _input.text.trim();
    _input.clear();

    try {
      setState(() => _sending = true);
      await _hybrid.sendMessage(
        myAppId: _me!,
        peerAppId: widget.peerAppId,
        text: text,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to send: ${ChatService.friendlyError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAndSendImage() async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      setState(() => _sending = true);

      final file = File(picked.path);
      final ref = FirebaseStorage.instance.ref().child(
            'chat-images/${DateTime.now().millisecondsSinceEpoch}-${picked.name}',
          );

      final upload = ref.putFile(file);
      upload.snapshotEvents.listen((snap) {
        setState(() {
          _uploadProgress = snap.bytesTransferred / snap.totalBytes;
        });
      });

      final snapshot = await upload;
      final url = await snapshot.ref.getDownloadURL();

      final text = '$_imgPrefix$url\n${_input.text}';
      _input.clear();

      await _hybrid.sendMessage(
        myAppId: _me!,
        peerAppId: widget.peerAppId,
        text: text,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Image upload failed: ${ChatService.friendlyError(e)}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _uploadProgress = null;
        });
      }
    }
  }

  Future<void> _recordAndSendVoiceNote() async {
    try {
      if (!_recording) {
        final hasPermission = await _recorder.hasPermission();
        if (!hasPermission) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Microphone permission denied')),
            );
          }
          return;
        }

        final tempDir = await getTemporaryDirectory();
        final audioPath =
            '${tempDir.path}/voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a';

        await _recorder.start(
          const RecordConfig(),
          path: audioPath,
        );

        setState(() => _recording = true);
        _recordMs = 0;

        _recTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
          setState(() => _recordMs += 100);
        });
      } else {
        // Stop recording
        final audioPath = await _recorder.stop();
        _recTimer?.cancel();

        setState(() => _recording = false);

        if (audioPath == null) return;

        setState(() => _sending = true);

        // Upload audio
        final file = File(audioPath);
        final ref = FirebaseStorage.instance.ref().child(
              'chat-audio/${DateTime.now().millisecondsSinceEpoch}.m4a',
            );

        final snapshot = await ref.putFile(file);
        final url = await snapshot.ref.getDownloadURL();
        final durationMs = _recordMs;

        final text = '$_audPrefix$url|$durationMs';
        await _hybrid.sendMessage(
          myAppId: _me!,
          peerAppId: widget.peerAppId,
          text: text,
        );

        await file.delete();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Voice note error: ${ChatService.friendlyError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_me == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.peerName ?? 'Chat')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child: _buildMessagesList(),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0.6,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.peerName ?? 'Chat',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 2),
          Consumer(
            builder: (context, ref, child) {
              final isOnline =
                  ref.watch(userOnlineStatusProvider(widget.peerAppId));
              final typingUsers =
                  ref.watch(typingUsersForChatProvider(_threadId));

              if (typingUsers.isNotEmpty) {
                return Text(
                  '${widget.peerName} is typing...',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFFF8A00),
                    fontWeight: FontWeight.w500,
                  ),
                );
              }

              return Text(
                isOnline ? 'Online' : 'Offline',
                style: TextStyle(
                  fontSize: 11,
                  color: isOnline ? Colors.green : Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              );
            },
          ),
        ],
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.black87),
        onPressed: () => Navigator.pop(context),
      ),
    );
  }

  Widget _buildMessagesList() {
    return Consumer(
      builder: (context, ref, child) {
        final messagesAsync = ref.watch(
          chatMessagesStreamProvider(_threadId),
        );

        return messagesAsync.when(
          data: (messages) {
            if (messages.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chat_bubble_outline,
                        size: 44, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    Text(
                      'No messages yet',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              );
            }

            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scroll.animateTo(
                _scroll.position.maxScrollExtent,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            });

            return ListView.builder(
              controller: _scroll,
              reverse: true,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              itemCount: messages.length,
              itemBuilder: (_, i) {
                final msg = messages[messages.length - 1 - i];
                final isMine = msg.isMine(_me!);

                return _MessageBubble(
                  message: msg,
                  isMine: isMine,
                  onDelete: () => _deleteMessage(msg),
                  onEdit: () => _editMessage(msg),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, st) => Center(
            child: Text('Error: $err'),
          ),
        );
      },
    );
  }

  Widget _buildInputArea() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_uploadProgress != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _uploadProgress!,
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  enabled: !_sending,
                  maxLines: null,
                  decoration: InputDecoration(
                    hintText: 'Message...',
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF3F3F3),
                    prefixIcon: IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: _sending ? null : _pickAndSendImage,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(_recording ? Icons.stop_circle : Icons.mic),
                      color: _recording ? Colors.red : Colors.grey,
                      onPressed: _sending ? null : _recordAndSendVoiceNote,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FloatingActionButton(
                mini: true,
                backgroundColor:
                    _input.text.isEmpty ? Colors.grey.shade300 : _brandGreen,
                foregroundColor: Colors.white,
                onPressed: _input.text.isEmpty ? null : _sendMessage,
                child: const Icon(Icons.send),
              ),
            ],
          ),
          if (_recording) ...[
            const SizedBox(height: 8),
            Text(
              'Recording... ${_formatDuration(_recordMs)}',
              style: const TextStyle(
                color: Colors.red,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _deleteMessage(Message msg) async {
    try {
      await _hybrid.deleteMessage(
        threadId: _threadId,
        messageId: msg.id,
        myAppId: _me!,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Delete failed: ${ChatService.friendlyError(e)}')),
        );
      }
    }
  }

  Future<void> _editMessage(Message msg) async {
    final controller = TextEditingController(text: msg.content);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Message'),
        content: TextField(
          controller: controller,
          maxLines: null,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      try {
        await _hybrid.editMessage(
          threadId: _threadId,
          messageId: msg.id,
          myAppId: _me!,
          newText: result,
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Edit failed: ${ChatService.friendlyError(e)}')),
          );
        }
      }
    }

    controller.dispose();
  }

  String _formatDuration(int ms) {
    final seconds = (ms / 1000).floor();
    final minutes = (seconds / 60).floor();
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}

class _MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMine;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final content = _parseContent(message.content);

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: isMine ? () => _showContextMenu(context) : null,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: isMine ? const Color(0xFF1FA855) : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (content.isImage)
                Image.network(
                  content.imageUrl!,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                )
              else if (content.isAudio)
                _AudioBubble(
                    url: content.audioUrl!,
                    durationMs: content.audioDuration ?? 0)
              else if (content.isCall)
                _CallBubble(callType: content.callType ?? 'audio')
              else
                Text(
                  content.text ?? message.content,
                  style: TextStyle(
                    color: isMine ? Colors.white : Colors.black87,
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(message.createdAt),
                    style: TextStyle(
                      fontSize: 10,
                      color: isMine ? Colors.white70 : Colors.grey.shade600,
                    ),
                  ),
                  if (isMine) ...[
                    const SizedBox(width: 4),
                    _StatusIcon(status: message.status),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Edit'),
            onTap: () {
              Navigator.pop(context);
              onEdit();
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete),
            title: const Text('Delete'),
            onTap: () {
              Navigator.pop(context);
              onDelete();
            },
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return DateFormat('HH:mm').format(dt);
  }
}

class _ContentParsed {
  final bool isImage;
  final bool isAudio;
  final bool isCall;
  final String? text;
  final String? imageUrl;
  final String? audioUrl;
  final int? audioDuration;
  final String? callType;

  _ContentParsed({
    this.isImage = false,
    this.isAudio = false,
    this.isCall = false,
    this.text,
    this.imageUrl,
    this.audioUrl,
    this.audioDuration,
    this.callType,
  });
}

_ContentParsed _parseContent(String content) {
  const imgPrefix = 'img::';
  const audPrefix = 'aud::';
  const callPrefix = 'call::';

  if (content.startsWith(imgPrefix)) {
    final url = content.substring(imgPrefix.length).split('\n').first;
    return _ContentParsed(isImage: true, imageUrl: url);
  }

  if (content.startsWith(audPrefix)) {
    final parts = content.substring(audPrefix.length).split('|');
    return _ContentParsed(
      isAudio: true,
      audioUrl: parts[0],
      audioDuration: int.tryParse(parts.length > 1 ? parts[1] : '0'),
    );
  }

  if (content.startsWith(callPrefix)) {
    final parts = content.substring(callPrefix.length).split('::');
    return _ContentParsed(isCall: true, callType: parts[0]);
  }

  return _ContentParsed(text: content);
}

class _AudioBubble extends StatefulWidget {
  final String url;
  final int durationMs;

  const _AudioBubble({required this.url, required this.durationMs});

  @override
  State<_AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<_AudioBubble> {
  bool _playing = false;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
          onPressed: () async {
            if (await canLaunchUrl(Uri.parse(widget.url))) {
              await launchUrl(Uri.parse(widget.url));
              setState(() => _playing = !_playing);
            }
          },
        ),
        Text(
          '${(widget.durationMs / 1000).toStringAsFixed(1)}s',
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}

class _CallBubble extends StatelessWidget {
  final String callType;

  const _CallBubble({required this.callType});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          callType == 'video' ? Icons.videocam : Icons.call,
          size: 18,
        ),
        const SizedBox(width: 6),
        Text('${callType.capitalize()} call'),
      ],
    );
  }
}

class _StatusIcon extends StatelessWidget {
  final MessageStatus status;

  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    return Icon(
      status == MessageStatus.read
          ? Icons.done_all
          : status == MessageStatus.delivered
              ? Icons.done
              : Icons.schedule,
      size: 12,
      color: Colors.white70,
    );
  }
}

extension on String {
  String capitalize() {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1);
  }
}
