import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'package:vero360_app/GernalServices/backend_chat_service.dart';

class MessagePageBackendApi extends StatefulWidget {
  final String peerId; // Chat ID from backend
  final String peerName;
  final String? peerAvatarUrl;

  const MessagePageBackendApi({
    super.key,
    required this.peerId,
    required this.peerName,
    this.peerAvatarUrl,
  });

  @override
  State<MessagePageBackendApi> createState() => _MessagePageBackendApiState();
}

class _MessagePageBackendApiState extends State<MessagePageBackendApi> {
  String? _me;
  int? _myUserId;

  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _picker = ImagePicker();

  bool _sending = false;
  List<BackendChatMessage> _messages = [];
  Timer? _refreshTimer;

  static const _brandOrange = Color(0xFFFF8A00);
  static const _bg = Color(0xFFF3F4F7);

  @override
  void initState() {
    super.initState();
    _boot();

    _input.addListener(() {
      if (!mounted) return;
      setState(() {});
    });

    // Refresh messages periodically
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) _loadMessages();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      await BackendChatService.ensureAuth();
      final userId = await BackendChatService.getUserId();
      await _loadMessages();

      if (!mounted) return;
      setState(() {
        _myUserId = userId;
        _me = userId.toString();
      });
    } catch (e) {
      if (!mounted) return;
      _toast('Error: ${e.toString()}');
    }
  }

  Future<void> _loadMessages() async {
    try {
      final messages = await BackendChatService.getMessages(widget.peerId);
      if (!mounted) return;
      // Sort by createdAt ascending so newest messages are at the end
      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      setState(() => _messages = messages);

      // Scroll to bottom after loading
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients && _scroll.position.maxScrollExtent > 0) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    } catch (e) {
      print('[MessagePageBackendApi] Error loading messages: $e');
    }
  }

  Future<void> _sendMessage() async {
    final content = _input.text.trim();
    if (content.isEmpty) return;

    _input.clear();
    setState(() => _sending = true);

    try {
      await BackendChatService.sendMessage(
        chatId: widget.peerId,
        content: content,
        type: 'text',
      );

      await _loadMessages();

      if (mounted) {
        setState(() => _sending = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients && _scroll.position.maxScrollExtent > 0) {
            _scroll.animateTo(
              _scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      _toast('Failed to send message: $e');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _timeLabel(BackendChatMessage m) {
    return DateFormat('HH:mm').format(m.createdAt);
  }

  String _dateLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final msgDate = DateTime(dt.year, dt.month, dt.day);

    if (msgDate == today) {
      return 'Today';
    } else if (msgDate == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('MMM d, yyyy').format(dt);
    }
  }

  bool _isDifferentDay(
      BackendChatMessage current, BackendChatMessage? previous) {
    if (previous == null) return true;
    final curr = DateTime(
        current.createdAt.year, current.createdAt.month, current.createdAt.day);
    final prev = DateTime(previous.createdAt.year, previous.createdAt.month,
        previous.createdAt.day);
    return curr != prev;
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.peerName;
    final canSend = !_sending && _input.text.trim().isNotEmpty;

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
              onPressed: _me == null ? null : () {},
              icon: const Icon(Icons.call),
            ),
            IconButton(
              onPressed: _me == null ? null : () {},
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
                      child: _messages.isEmpty
                          ? const Center(
                              child: Text(
                                'Say hi 👋',
                                style: TextStyle(
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: _scroll,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 16,
                              ),
                              itemCount: _messages.length,
                              itemBuilder: (context, i) {
                                final msg = _messages[i];
                                final prevMsg = i > 0 ? _messages[i - 1] : null;
                                final isMine = msg.isMine(_myUserId!);
                                final showDateSeparator =
                                    _isDifferentDay(msg, prevMsg);

                                return Column(
                                  children: [
                                    if (showDateSeparator) ...[
                                      const SizedBox(height: 16),
                                      Center(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.grey[200],
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            _dateLabel(msg.createdAt),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.black54,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                    ],
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 12),
                                      child: Row(
                                        mainAxisAlignment: isMine
                                            ? MainAxisAlignment.end
                                            : MainAxisAlignment.start,
                                        children: [
                                          if (!isMine)
                                            _avatar(widget.peerAvatarUrl,
                                                size: 28)
                                          else
                                            const SizedBox(width: 28),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Column(
                                              crossAxisAlignment: isMine
                                                  ? CrossAxisAlignment.end
                                                  : CrossAxisAlignment.start,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 12,
                                                    vertical: 8,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: isMine
                                                        ? _brandOrange
                                                        : Colors.white,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black
                                                            .withOpacity(0.05),
                                                        blurRadius: 2,
                                                        offset:
                                                            const Offset(0, 1),
                                                      ),
                                                    ],
                                                  ),
                                                  child: Text(
                                                    msg.content ??
                                                        '(no message)',
                                                    style: TextStyle(
                                                      color: isMine
                                                          ? Colors.white
                                                          : Colors.black87,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  _timeLabel(msg),
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.black54,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                    ),
                    _buildInputArea(canSend),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildInputArea(bool canSend) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              enabled: !_sending,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(
                hintText: 'Message...',
                hintStyle: const TextStyle(color: Colors.black54),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: const BorderSide(color: Colors.black12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FloatingActionButton(
            onPressed: canSend ? _sendMessage : null,
            backgroundColor: _brandOrange,
            disabledElevation: 0,
            elevation: 2,
            child: _sending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : const Icon(Icons.send),
          ),
        ],
      ),
    );
  }

  Widget _avatar(String? url, {double size = 40}) {
    final initials = _getInitials(widget.peerName);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey[300],
      ),
      child: url != null && url.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(size / 2),
              child: Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(
                    initials,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
            )
          : Center(
              child: Text(
                initials,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Colors.black87,
                ),
              ),
            ),
    );
  }

  String _getInitials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'C';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

class _ChatBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFF3F4F7)
      ..style = PaintingStyle.fill;

    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
