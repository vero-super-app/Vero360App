import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vero360_app/GernalServices/help_center_chat_service.dart';

/// Live chat with Vero360 Help Center (same inbox as the website widget).
class HelpCenterLiveChatPage extends StatefulWidget {
  const HelpCenterLiveChatPage({
    super.key,
    this.visitorName,
    this.visitorEmail,
    this.initialMessage,
  });

  final String? visitorName;
  final String? visitorEmail;
  final String? initialMessage;

  @override
  State<HelpCenterLiveChatPage> createState() => _HelpCenterLiveChatPageState();
}

class _HelpCenterLiveChatPageState extends State<HelpCenterLiveChatPage> {
  static const _brand = Color(0xFFFF8A00);
  static const _bg = Color(0xFFF3F4F7);
  static const _ink = Color(0xFF101010);

  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _picker = ImagePicker();

  String? _sessionId;
  StreamSubscription<List<HelpCenterMessage>>? _sub;
  List<HelpCenterMessage> _messages = const [];
  bool _booting = true;
  bool _sending = false;
  String _error = '';
  bool _seededInitial = false;

  String get _name {
    final fromWidget = (widget.visitorName ?? '').trim();
    if (fromWidget.isNotEmpty) return fromWidget;
    final user = FirebaseAuth.instance.currentUser;
    final dn = (user?.displayName ?? '').trim();
    if (dn.isNotEmpty) return dn;
    final email = (user?.email ?? '').trim();
    if (email.isNotEmpty && !email.endsWith('@phone.vero360.app')) {
      return email.split('@').first;
    }
    return 'App user';
  }

  String get _email {
    final fromWidget = (widget.visitorEmail ?? '').trim();
    if (fromWidget.isNotEmpty && !fromWidget.endsWith('@phone.vero360.app')) {
      return fromWidget;
    }
    final email = (FirebaseAuth.instance.currentUser?.email ?? '').trim();
    if (email.isNotEmpty && !email.endsWith('@phone.vero360.app')) return email;
    return 'app-user@vero.local';
  }

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  Future<void> _boot() async {
    try {
      final id = await HelpCenterChatService.resolveSessionId();
      await HelpCenterChatService.ensureSession(
        sessionId: id,
        visitorName: _name,
        visitorEmail: _email,
      );
      if (!mounted) return;
      setState(() {
        _sessionId = id;
        _booting = false;
      });
      _sub = HelpCenterChatService.watchMessages(id).listen((msgs) {
        if (!mounted) return;
        setState(() => _messages = msgs);
        _scrollToEnd();
        _maybeSendInitial();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _booting = false;
        _error = 'Could not start Help Center chat. Check your connection.';
      });
    }
  }

  Future<void> _maybeSendInitial() async {
    if (_seededInitial) return;
    final text = (widget.initialMessage ?? '').trim();
    if (text.isEmpty || _sessionId == null) return;
    // Wait until welcome message is present so we don't race create.
    if (_messages.isEmpty) return;
    _seededInitial = true;
    await _sendText(text);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendText(String raw) async {
    final text = raw.trim();
    final sessionId = _sessionId;
    if (text.isEmpty || sessionId == null || _sending) return;
    setState(() {
      _sending = true;
      _error = '';
    });
    try {
      await HelpCenterChatService.sendText(
        sessionId: sessionId,
        text: text,
        visitorName: _name,
        visitorEmail: _email,
      );
      _input.clear();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not send. Try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickPhoto() async {
    final sessionId = _sessionId;
    if (sessionId == null || _sending) return;
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (file == null) return;
    setState(() {
      _sending = true;
      _error = '';
    });
    try {
      final bytes = await file.readAsBytes();
      await HelpCenterChatService.sendImage(
        sessionId: sessionId,
        bytes: bytes,
        filename: file.name,
        contentType: 'image/jpeg',
        visitorName: _name,
        visitorEmail: _email,
        caption: _input.text.trim().isEmpty ? null : _input.text.trim(),
      );
      _input.clear();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not upload photo. Try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFFFFF4E5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.headset_mic_rounded, color: _brand),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Help Center',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: _ink,
                    ),
                  ),
                  Text(
                    'Live chat with Vero360 support',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFECEEF2)),
        ),
      ),
      body: Column(
        children: [
          if (_error.isNotEmpty)
            Container(
              width: double.infinity,
              color: const Color(0xFFFEF2F2),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Text(
                _error,
                style: const TextStyle(
                  color: Color(0xFFB91C1C),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Expanded(
            child: _booting
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
                    itemCount: _messages.length + (_sending ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (_sending && i == _messages.length) {
                        return const Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: EdgeInsets.only(bottom: 10),
                            child: Text(
                              'Sending…',
                              style: TextStyle(
                                color: Color(0xFF9CA3AF),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        );
                      }
                      return _HelpBubble(msg: _messages[i]);
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Send photo',
                    onPressed: _sending || _sessionId == null ? null : _pickPhoto,
                    icon: const Icon(Icons.photo_outlined, color: _brand),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      textInputAction: TextInputAction.send,
                      minLines: 1,
                      maxLines: 4,
                      enabled: !_booting && _sessionId != null,
                      onSubmitted: _sendText,
                      decoration: InputDecoration(
                        hintText: 'Message Help Center…',
                        filled: true,
                        fillColor: _bg,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Material(
                    color: _brand,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _sending || _sessionId == null
                          ? null
                          : () => _sendText(_input.text),
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.send_rounded, color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HelpBubble extends StatelessWidget {
  const _HelpBubble({required this.msg});
  final HelpCenterMessage msg;

  @override
  Widget build(BuildContext context) {
    final fromAgent = msg.fromAgent;
    final align = fromAgent ? Alignment.centerLeft : Alignment.centerRight;
    final bg = fromAgent ? Colors.white : const Color(0xFFFF8A00);
    final fg = fromAgent ? const Color(0xFF101010) : Colors.white;

    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(fromAgent ? 4 : 16),
              bottomRight: Radius.circular(fromAgent ? 16 : 4),
            ),
            boxShadow: [
              if (fromAgent)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (fromAgent && (msg.agentName ?? '').trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    msg.agentName!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              if (msg.kind == 'image' && (msg.imageUrl ?? '').isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    msg.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Text(
                      'Photo',
                      style: TextStyle(color: fg, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                if (msg.text.trim().isNotEmpty) const SizedBox(height: 8),
              ],
              if (msg.text.trim().isNotEmpty)
                Text(
                  msg.text,
                  style: TextStyle(
                    color: fg,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                    fontSize: 14.5,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
