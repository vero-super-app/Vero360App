import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vero360_app/features/Reels/reel_model.dart';
import 'package:vero360_app/features/Reels/reel_service.dart';
import 'package:vero360_app/utils/toasthelper.dart';

const _kOrange = Color(0xFFFF8A00);
const _kInk = Color(0xFF16181D);
const _kMuted = Color(0xFF8A8F98);

/// Opens the comments sheet. [onCountChanged] receives the live comment total.
Future<void> showReelComments(
  BuildContext context, {
  required Reel reel,
  required bool canModerate,
  ValueChanged<int>? onCountChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) => _ReelCommentsSheet(
      reel: reel,
      canModerate: canModerate,
      onCountChanged: onCountChanged,
    ),
  );
}

String reelTimeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  if (d.inDays < 365) return '${(d.inDays / 7).floor()}w';
  return '${(d.inDays / 365).floor()}y';
}

String _count(int n) {
  if (n < 1000) return '$n';
  if (n < 1000000) return '${(n / 1000).toStringAsFixed(n < 10000 ? 1 : 0)}K';
  return '${(n / 1000000).toStringAsFixed(1)}M';
}

class _ReelCommentsSheet extends StatefulWidget {
  const _ReelCommentsSheet({
    required this.reel,
    required this.canModerate,
    this.onCountChanged,
  });

  final Reel reel;
  final bool canModerate;
  final ValueChanged<int>? onCountChanged;

  @override
  State<_ReelCommentsSheet> createState() => _ReelCommentsSheetState();
}

class _ReelCommentsSheetState extends State<_ReelCommentsSheet> {
  final _service = ReelService.instance;
  final _text = TextEditingController();
  final _focus = FocusNode();
  late final Stream<List<ReelComment>> _stream;
  final Set<String> _expanded = <String>{};
  /// Optimistic reactions so taps feel instant before Firestore echoes back.
  final Map<String, String?> _pendingReaction = <String, String?>{};
  ReelComment? _replyTo;
  bool _sending = false;
  int? _lastCount;
  String _myPhoto = '';
  String _myName = '';

  static const _quickEmojis = ['❤️', '😂', '🔥', '😍', '👏', '😮', '🙌'];

  @override
  void initState() {
    super.initState();
    _stream = _service.watchComments(widget.reel.id);
    _service.myIdentity().then((me) {
      if (!mounted || me == null) return;
      setState(() {
        _myPhoto = me.photo;
        _myName = me.name;
      });
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _toast(String msg) =>
      ToastHelper.showCustomToast(context, msg, isSuccess: false, errorMessage: '');

  void _startReply(ReelComment c) {
    if (!_service.isSignedIn) {
      _toast('Sign in to reply.');
      return;
    }
    setState(() => _replyTo = c);
    _focus.requestFocus();
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    if (!_service.isSignedIn) {
      _toast('Sign in to comment.');
      return;
    }
    final replyTo = _replyTo;
    setState(() => _sending = true);
    try {
      await _service.addComment(
        widget.reel.id,
        body,
        parentId: replyTo == null ? null : (replyTo.parentId ?? replyTo.id),
        replyToName: replyTo?.name,
      );
      _text.clear();
      if (replyTo != null) _expanded.add(replyTo.parentId ?? replyTo.id);
      if (mounted) setState(() => _replyTo = null);
    } catch (_) {
      if (mounted) _toast('Could not post comment');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String? _myReaction(ReelComment c) {
    if (_pendingReaction.containsKey(c.id)) return _pendingReaction[c.id];
    final uid = _service.myUid;
    if (uid == null) return null;
    if (c.likedBy.contains(uid)) return 'like';
    if (c.dislikedBy.contains(uid)) return 'dislike';
    return null;
  }

  Future<void> _react(ReelComment c, String reaction) async {
    if (!_service.isSignedIn) {
      _toast('Sign in to react.');
      return;
    }
    HapticFeedback.selectionClick();
    final current = _myReaction(c);
    setState(() => _pendingReaction[c.id] = current == reaction ? null : reaction);
    try {
      await _service.reactToComment(widget.reel.id, c, reaction);
    } catch (_) {
      if (mounted) _toast('Could not save reaction');
    } finally {
      if (mounted) setState(() => _pendingReaction.remove(c.id));
    }
  }

  Future<void> _showOptions(ReelComment c) async {
    final mine = c.uid == _service.myUid;
    final canDelete = mine || widget.canModerate;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            _handle(),
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('Reply'),
              onTap: () => Navigator.pop(ctx, 'reply'),
            ),
            if (c.text.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Copy text'),
                onTap: () => Navigator.pop(ctx, 'copy'),
              ),
            if (canDelete)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                title: const Text('Delete', style: TextStyle(color: Colors.red)),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'reply':
        _startReply(c);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: c.text));
      case 'delete':
        try {
          await _service.deleteComment(widget.reel.id, c);
        } catch (_) {
          if (mounted) _toast('Could not delete comment');
        }
    }
  }

  Widget _handle() => Container(
        width: 38,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(2),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.72;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        height: height,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: StreamBuilder<List<ReelComment>>(
          stream: _stream,
          builder: (context, snap) {
            final all = snap.data ?? const <ReelComment>[];
            final visibleCount = all.where((c) => !c.deleted).length;
            if (snap.hasData && _lastCount != visibleCount) {
              _lastCount = visibleCount;
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => widget.onCountChanged?.call(visibleCount),
              );
            }
            return Column(
              children: [
                const SizedBox(height: 10),
                _handle(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 8, 6),
                  child: Row(
                    children: [
                      Text(
                        snap.hasData
                            ? '${_count(visibleCount)} ${visibleCount == 1 ? 'comment' : 'comments'}'
                            : 'Comments',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: _kInk,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: _kMuted),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _body(snap, all)),
                _composer(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _body(AsyncSnapshot<List<ReelComment>> snap, List<ReelComment> all) {
    if (snap.hasError) {
      return const Center(
        child: Text('Could not load comments', style: TextStyle(color: _kMuted)),
      );
    }
    if (!snap.hasData) {
      return const Center(child: CircularProgressIndicator(color: _kOrange));
    }
    final top = all.where((c) => !c.isReply).toList();
    final replies = <String, List<ReelComment>>{};
    for (final c in all.where((c) => c.isReply)) {
      replies.putIfAbsent(c.parentId!, () => []).add(c);
    }
    for (final list in replies.values) {
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
    // Hide blanked parents whose replies are all gone.
    top.removeWhere((c) => c.deleted && (replies[c.id]?.isEmpty ?? true));
    // Most-liked first, then newest.
    top.sort((a, b) {
      final byLikes = b.likeCount.compareTo(a.likeCount);
      return byLikes != 0 ? byLikes : b.createdAt.compareTo(a.createdAt);
    });

    if (top.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0xFFFFF3E3),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.chat_bubble_outline_rounded,
                  color: _kOrange, size: 30),
            ),
            const SizedBox(height: 14),
            const Text('No comments yet',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: _kInk)),
            const SizedBox(height: 4),
            const Text('Start the conversation.', style: TextStyle(color: _kMuted)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: top.length,
      itemBuilder: (context, i) {
        final c = top[i];
        final kids = replies[c.id] ?? const <ReelComment>[];
        final open = _expanded.contains(c.id);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _commentTile(c),
            if (kids.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 68, bottom: 4),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() {
                    open ? _expanded.remove(c.id) : _expanded.add(c.id);
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 22, height: 1, color: Colors.black26),
                        const SizedBox(width: 8),
                        Text(
                          open
                              ? 'Hide replies'
                              : 'View ${kids.length} ${kids.length == 1 ? 'reply' : 'replies'}',
                          style: const TextStyle(
                            color: _kMuted,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                        Icon(
                          open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                          size: 18,
                          color: _kMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (open)
              for (final r in kids) _commentTile(r, reply: true),
          ],
        );
      },
    );
  }

  Widget _commentTile(ReelComment c, {bool reply = false}) {
    final reaction = _myReaction(c);
    final liked = reaction == 'like';
    final disliked = reaction == 'dislike';
    final uid = _service.myUid;
    // Adjust counts for the optimistic state.
    var likes = c.likeCount;
    var dislikes = c.dislikeCount;
    if (_pendingReaction.containsKey(c.id) && uid != null) {
      if (c.likedBy.contains(uid)) likes--;
      if (c.dislikedBy.contains(uid)) dislikes--;
      if (liked) likes++;
      if (disliked) dislikes++;
    }
    final isCreator = c.uid == widget.reel.ownerId;
    final avatarSize = reply ? 26.0 : 36.0;

    if (c.deleted) {
      return Padding(
        padding: EdgeInsets.fromLTRB(reply ? 68 : 20, 10, 20, 6),
        child: const Text(
          'Comment deleted',
          style: TextStyle(color: _kMuted, fontStyle: FontStyle.italic),
        ),
      );
    }

    return InkWell(
      onLongPress: () => _showOptions(c),
      child: Padding(
        padding: EdgeInsets.fromLTRB(reply ? 68 : 16, 10, 12, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _avatar(c.photo, c.name, avatarSize),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _kMuted,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      if (isCreator) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E3),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Creator',
                            style: TextStyle(
                              color: _kOrange,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 6),
                      Text('· ${reelTimeAgo(c.createdAt)}',
                          style: const TextStyle(color: _kMuted, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text.rich(
                    TextSpan(
                      children: [
                        if (c.replyToName != null && reply)
                          TextSpan(
                            text: '@${c.replyToName} ',
                            style: const TextStyle(
                              color: _kOrange,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        TextSpan(text: c.text),
                      ],
                    ),
                    style: const TextStyle(color: _kInk, fontSize: 14.5, height: 1.35),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _ReactionButton(
                        icon: liked ? Icons.thumb_up_alt_rounded : Icons.thumb_up_alt_outlined,
                        active: liked,
                        activeColor: _kOrange,
                        count: likes,
                        onTap: () => _react(c, 'like'),
                      ),
                      const SizedBox(width: 6),
                      _ReactionButton(
                        icon: disliked
                            ? Icons.thumb_down_alt_rounded
                            : Icons.thumb_down_alt_outlined,
                        active: disliked,
                        activeColor: _kInk,
                        count: dislikes,
                        onTap: () => _react(c, 'dislike'),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () => _startReply(c),
                        behavior: HitTestBehavior.opaque,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                          child: Text(
                            'Reply',
                            style: TextStyle(
                              color: _kMuted,
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => _showOptions(c),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.more_horiz_rounded, size: 18, color: _kMuted),
                        ),
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

  Widget _avatar(String url, String name, double size) {
    final initial = name.trim().isEmpty ? 'V' : name.trim()[0].toUpperCase();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: const Color(0xFFFFF3E3),
      backgroundImage: url.startsWith('http') ? NetworkImage(url) : null,
      child: url.startsWith('http')
          ? null
          : Text(initial,
              style: TextStyle(
                color: _kOrange,
                fontWeight: FontWeight.w800,
                fontSize: size * 0.4,
              )),
    );
  }

  Widget _guestComposer() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEDEEF1))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              const Icon(Icons.lock_outline_rounded, size: 18, color: _kMuted),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Sign in to like and comment',
                  style: TextStyle(color: _kMuted, fontWeight: FontWeight.w600),
                ),
              ),
              FilledButton(
                onPressed: () {
                  final nav = Navigator.of(context);
                  nav.pop();
                  nav.pushNamed('/login');
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF8A00),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text('Sign in', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _composer() {
    if (!_service.isSignedIn) return _guestComposer();
    final replyTo = _replyTo;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEDEEF1))),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (replyTo != null)
              Container(
                color: const Color(0xFFF7F7F9),
                padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                child: Row(
                  children: [
                    const Icon(Icons.reply_rounded, size: 16, color: _kMuted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Replying to ${replyTo.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _kMuted, fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded, size: 18, color: _kMuted),
                      onPressed: () => setState(() => _replyTo = null),
                    ),
                  ],
                ),
              ),
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final e in _quickEmojis)
                    GestureDetector(
                      onTap: () {
                        final sel = _text.selection;
                        final t = _text.text;
                        final at = sel.isValid ? sel.start : t.length;
                        _text.value = TextEditingValue(
                          text: t.replaceRange(at, sel.isValid ? sel.end : t.length, e),
                          selection: TextSelection.collapsed(offset: at + e.length),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Center(child: Text(e, style: const TextStyle(fontSize: 22))),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 8, 10),
              child: Row(
                children: [
                  _avatar(_myPhoto, _myName, 32),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      maxLength: 500,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: replyTo == null
                            ? 'Add a comment…'
                            : 'Reply to ${replyTo.name}…',
                        hintStyle: const TextStyle(color: _kMuted),
                        filled: true,
                        fillColor: const Color(0xFFF3F4F7),
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _text.text.trim().isEmpty
                          ? const Color(0xFFF3F4F7)
                          : _kOrange,
                    ),
                    child: IconButton(
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Icon(
                              Icons.arrow_upward_rounded,
                              color: _text.text.trim().isEmpty ? _kMuted : Colors.white,
                            ),
                    ),
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

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({
    required this.icon,
    required this.active,
    required this.activeColor,
    required this.count,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final Color activeColor;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: active ? 1.15 : 1,
              duration: const Duration(milliseconds: 160),
              child: Icon(icon, size: 17, color: active ? activeColor : _kMuted),
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                _count(count),
                style: TextStyle(
                  color: active ? activeColor : _kMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
