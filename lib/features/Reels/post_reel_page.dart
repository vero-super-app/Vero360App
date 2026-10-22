import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:vero360_app/features/Reels/reel_model.dart';
import 'package:vero360_app/features/Reels/reel_music_picker.dart';
import 'package:vero360_app/features/Reels/reel_service.dart';
import 'package:vero360_app/features/Reels/reel_upload_manager.dart';
import 'package:vero360_app/features/Reels/reels_nav_icon.dart';
import 'package:vero360_app/utils/toasthelper.dart';

const _kOrange = Color(0xFFFF8A00);

/// Record or choose a short video, add a caption, optionally tag a product.
/// Pops `true` after a successful post.
class PostReelPage extends StatefulWidget {
  const PostReelPage({super.key});

  @override
  State<PostReelPage> createState() => _PostReelPageState();
}

class _PostReelPageState extends State<PostReelPage> {
  final _service = ReelService.instance;
  final _picker = ImagePicker();
  final _caption = TextEditingController();
  VideoPlayerController? _preview;
  String? _path;
  Duration _duration = Duration.zero;
  ReelProduct? _product;
  ReelMusic? _music;
  ReelIdentity? _me;
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _service.myIdentity().then((me) {
      if (mounted) setState(() => _me = me);
      if (me?.isMerchant == true) {
        unawaited(_service.myProducts().then((_) {}, onError: (_) {}));
      }
    });
  }

  @override
  void dispose() {
    _preview?.dispose();
    _caption.dispose();
    super.dispose();
  }

  void _toast(String msg, {bool ok = false}) =>
      ToastHelper.showCustomToast(context, msg, isSuccess: ok, errorMessage: '');

  Future<void> _pick(ImageSource source) async {
    if (_posting) return;
    try {
      final file = await _picker.pickVideo(
        source: source,
        maxDuration: ReelService.maxDuration,
      );
      if (file == null || !mounted) return;
      final size = await file.length();
      if (size <= 0) {
        _toast('That video is empty. Record or choose another one.');
        return;
      }
      if (size > ReelService.maxVideoBytes) {
        _toast('That video is too large. Use one under 40 MB.');
        return;
      }
      final controller = VideoPlayerController.file(
        File(file.path),
        viewType: defaultTargetPlatform == TargetPlatform.android
            ? VideoViewType.platformView
            : VideoViewType.textureView,
      );
      await controller.initialize();
      final length = controller.value.duration;
      // Gallery picks ignore maxDuration on many phones.
      if (length > ReelService.maxDuration + const Duration(seconds: 1)) {
        await controller.dispose();
        if (mounted) _toast('Reels can be up to 60 seconds. Trim it and try again.');
        return;
      }
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(true);
      await controller.play();
      final old = _preview;
      setState(() {
        _preview = controller;
        _path = file.path;
        _duration = length;
      });
      await old?.dispose();
    } catch (e) {
      if (kDebugMode) debugPrint('[PostReel] pick failed: $e');
      if (mounted) _toast('Could not open that video');
    }
  }

  Future<void> _chooseProduct() async {
    final picked = await showModalBottomSheet<ReelProduct?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _ProductPickerSheet(),
    );
    if (picked != null && mounted) setState(() => _product = picked);
  }

  Future<void> _chooseMusic() async {
    final picked = await showSpotifyPicker(context);
    if (picked != null && mounted) setState(() => _music = picked);
  }

  Future<void> _post() async {
    final path = _path;
    if (path == null || _posting) return;
    if (!_service.isSignedIn) {
      _toast('Sign in to post a reel.');
      return;
    }
    final started = ReelUploadManager.instance.start(
      filePath: path,
      caption: _caption.text,
      duration: _duration,
      product: _product,
      music: _music,
    );
    if (!started) {
      _toast('Wait for your other reel to finish posting.');
      return;
    }
    _preview?.pause();
    setState(() => _posting = true);
    Navigator.of(context).pop(true);
  }

  String _fmt(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _replaceVideo() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _Handle(),
              const SizedBox(height: 14),
              _SheetOption(
                icon: Icons.videocam_rounded,
                title: 'Record a new video',
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              const SizedBox(height: 8),
              _SheetOption(
                icon: Icons.video_library_rounded,
                title: 'Choose from gallery',
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source != null) await _pick(source);
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final hasVideo = preview != null && preview.value.isInitialized;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: _kBg,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Column(
            children: [
              _topBar(hasVideo),
              Expanded(child: hasVideo ? _editor(preview) : _choosePanel()),
              if (hasVideo) _postBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar(bool hasVideo) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: _posting ? null : () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded, color: _kInk, size: 26),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Text(
              hasVideo ? 'Edit reel' : 'Create reel',
              style: const TextStyle(
                color: _kInk,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (hasVideo)
            TextButton.icon(
              onPressed: _posting ? null : _replaceVideo,
              style: TextButton.styleFrom(foregroundColor: _kOrangeDeep),
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: const Text('Replace', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }

  // ── Step 1: pick a video ──────────────────────────────────────────────────

  Widget _choosePanel() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [Color(0xFFFFA43A), _kOrange, _kOrangeDeep],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: _kOrange.withValues(alpha: 0.30),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Center(child: ReelsNavIcon(color: _kOrange, size: 32)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Share a moment',
                      style: TextStyle(
                          color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _me?.isMerchant == true
                          ? 'Show off your products. Tag one so buyers can shop it.'
                          : 'Post a short vertical video for everyone to watch.',
                      style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 10),
          child: Text('Add a video',
              style: TextStyle(color: _kInk, fontSize: 15, fontWeight: FontWeight.w800)),
        ),
        Row(
          children: [
            Expanded(
              child: _ChoiceTile(
                icon: Icons.videocam_rounded,
                title: 'Record',
                subtitle: 'Use camera',
                highlighted: true,
                onTap: () => _pick(ImageSource.camera),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ChoiceTile(
                icon: Icons.video_library_rounded,
                title: 'Upload',
                subtitle: 'From gallery',
                onTap: () => _pick(ImageSource.gallery),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 10),
          child: Text('Tips for a great reel',
              style: TextStyle(color: _kInk, fontSize: 15, fontWeight: FontWeight.w800)),
        ),
        const _Card(
          child: Column(
            children: [
              _TipRow(icon: Icons.stay_current_portrait_rounded, text: 'Film vertically (9:16)'),
              _TipRow(icon: Icons.timer_outlined, text: 'Keep it under 60 seconds'),
              _TipRow(icon: Icons.wb_sunny_outlined, text: 'Good light makes products pop'),
              _TipRow(icon: Icons.sd_storage_outlined, text: 'Max file size 40 MB', last: true),
            ],
          ),
        ),
      ],
    );
  }

  // ── Step 2: preview, caption, product ─────────────────────────────────────

  Widget _editor(VideoPlayerController preview) {
    final screenH = MediaQuery.sizeOf(context).height;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        Center(
          child: Container(
            height: screenH * 0.46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: AspectRatio(
              aspectRatio: 9 / 16,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: Colors.black),
                    GestureDetector(
                      onTap: () =>
                          preview.value.isPlaying ? preview.pause() : preview.play(),
                      child: FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: preview.value.size.width == 0 ? 9 : preview.value.size.width,
                          height:
                              preview.value.size.height == 0 ? 16 : preview.value.size.height,
                          child: VideoPlayer(preview),
                        ),
                      ),
                    ),
                    IgnorePointer(
                      child: ValueListenableBuilder<VideoPlayerValue>(
                        valueListenable: preview,
                        builder: (context, v, _) => AnimatedOpacity(
                          opacity: v.isPlaying ? 0 : 1,
                          duration: const Duration(milliseconds: 180),
                          child: Center(
                            child: Container(
                              width: 62,
                              height: 62,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.play_arrow_rounded,
                                  color: Colors.white, size: 40),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: _OverlayPill(
                        icon: Icons.timer_outlined,
                        label: _fmt(_duration),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: IgnorePointer(
                        child: ValueListenableBuilder<VideoPlayerValue>(
                          valueListenable: preview,
                          builder: (context, v, _) {
                            final total = v.duration.inMilliseconds;
                            final pos = v.position.inMilliseconds;
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: total <= 0 ? 0 : (pos / total).clamp(0.0, 1.0),
                                minHeight: 3,
                                color: _kOrange,
                                backgroundColor: Colors.white24,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _Card(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: _MeAvatar(name: _me?.name ?? '', photo: _me?.photo ?? ''),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _caption,
                  maxLength: 300,
                  minLines: 2,
                  maxLines: 5,
                  enabled: !_posting,
                  style: const TextStyle(color: _kInk, fontSize: 15, height: 1.35),
                  cursorColor: _kOrange,
                  decoration: const InputDecoration(
                    hintText: 'Describe your reel… add #tags',
                    hintStyle: TextStyle(color: Colors.black38),
                    border: InputBorder.none,
                    counterStyle: TextStyle(color: Colors.black38, fontSize: 11),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          onTap: _posting ? null : _chooseMusic,
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F8EE),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: (_music?.image ?? '').startsWith('http')
                    ? Image.network(_music!.image,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.music_note_rounded, color: kSpotifyGreen))
                    : const Icon(Icons.music_note_rounded, color: kSpotifyGreen),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _music == null ? 'Add music' : _music!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _kInk, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _music == null ? 'Tag a song from Spotify' : _music!.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.black54, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              if (_music == null)
                const Icon(Icons.chevron_right_rounded, color: Colors.black38)
              else
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.black45),
                  onPressed: _posting ? null : () => setState(() => _music = null),
                ),
            ],
          ),
        ),
        if (_me?.isMerchant == true) ...[
          const SizedBox(height: 12),
          _Card(
            onTap: _posting ? null : _chooseProduct,
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: _kOrangeSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: (_product?.image ?? '').startsWith('http')
                      ? Image.network(_product!.image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.sell_rounded, color: _kOrange))
                      : const Icon(Icons.sell_rounded, color: _kOrange),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _product == null ? 'Tag a product' : _product!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _kInk, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _product == null
                            ? 'Buyers can tap Shop on your reel'
                            : 'Tagged · buyers can tap Shop',
                        style: const TextStyle(color: Colors.black54, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                if (_product == null)
                  const Icon(Icons.chevron_right_rounded, color: Colors.black38)
                else
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.black45),
                    onPressed: _posting ? null : () => setState(() => _product = null),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        const Row(
          children: [
            SizedBox(width: 4),
            Icon(Icons.public_rounded, color: Colors.black38, size: 16),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'Everyone can see this reel. Reels that break the rules are removed.',
                style: TextStyle(color: Colors.black45, fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _postBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: GestureDetector(
        onTap: _posting ? null : _post,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 54,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFFFA43A), _kOrange, _kOrangeDeep],
                    ),
                  ),
                ),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Share reel',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          shadows: [Shadow(blurRadius: 4, color: Colors.black26)],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _kBg = Color(0xFFF6F7FB);
const _kInk = Color(0xFF1B1D22);
const _kOrangeDeep = Color(0xFFE85D00);
const _kOrangeSoft = Color(0xFFFFE9D1);

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) => Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(2),
        ),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFECEEF2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(padding: const EdgeInsets.all(14), child: child),
        ),
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: highlighted ? _kOrange : Colors.white,
            border: highlighted ? null : Border.all(color: const Color(0xFFECEEF2)),
            boxShadow: [
              BoxShadow(
                color: highlighted
                    ? _kOrange.withValues(alpha: 0.28)
                    : Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: highlighted ? Colors.white.withValues(alpha: 0.22) : _kOrangeSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: highlighted ? Colors.white : _kOrange, size: 26),
              ),
              const SizedBox(height: 14),
              Text(title,
                  style: TextStyle(
                      color: highlighted ? Colors.white : _kInk,
                      fontSize: 17,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(
                      color: highlighted ? Colors.white : Colors.black54, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TipRow extends StatelessWidget {
  const _TipRow({required this.icon, required this.text, this.last = false});

  final IconData icon;
  final String text;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _kOrangeSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: _kOrange),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: const TextStyle(color: _kInk, fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class _OverlayPill extends StatelessWidget {
  const _OverlayPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  const _SheetOption({required this.icon, required this.title, required this.onTap});

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _kBg,
      borderRadius: BorderRadius.circular(16),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: _kOrangeSoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _kOrange, size: 20),
        ),
        title: Text(title,
            style: const TextStyle(color: _kInk, fontWeight: FontWeight.w700)),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.black38),
      ),
    );
  }
}

class _MeAvatar extends StatelessWidget {
  const _MeAvatar({required this.name, required this.photo});

  final String name;
  final String photo;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return CircleAvatar(
      radius: 18,
      backgroundColor: _kOrangeSoft,
      backgroundImage: photo.startsWith('http') ? NetworkImage(photo) : null,
      child: photo.startsWith('http')
          ? null
          : Text(initial,
              style: const TextStyle(color: _kOrange, fontWeight: FontWeight.w800)),
    );
  }
}

class _ProductPickerSheet extends StatefulWidget {
  const _ProductPickerSheet();

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  final _service = ReelService.instance;
  final _search = TextEditingController();
  List<ReelProduct>? _items;
  bool _refreshing = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final quick = await _service.myProductsQuick();
    if (mounted && quick != null && _items == null) setState(() => _items = quick);
    try {
      final fresh = await _service.myProducts();
      if (!mounted) return;
      setState(() {
        _items = fresh;
        _refreshing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _refreshing = false;
        _failed = _items == null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final items = _items;
    final shown = items == null || q.isEmpty
        ? items
        : items.where((p) => p.name.toLowerCase().contains(q)).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            const SizedBox(height: 10),
            const _Handle(),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Tag one of your products',
                    style: TextStyle(color: _kInk, fontWeight: FontWeight.w900, fontSize: 18)),
              ),
            ),
            if ((items?.length ?? 0) > 6)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search your products',
                    prefixIcon: const Icon(Icons.search_rounded, color: Colors.black45),
                    filled: true,
                    fillColor: const Color(0xFFF2F3F5),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            if (_refreshing && items != null)
              const LinearProgressIndicator(
                minHeight: 2,
                color: _kOrange,
                backgroundColor: Colors.transparent,
              )
            else
              const SizedBox(height: 2),
            Expanded(child: _body(shown)),
          ],
        ),
      ),
    );
  }

  Widget _body(List<ReelProduct>? items) {
    if (_failed) {
      return const Center(child: Text('Could not load your products'));
    }
    if (items == null) {
      return ListView.builder(
        itemCount: 6,
        itemBuilder: (_, _) => const _ProductSkeleton(),
      );
    }
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _search.text.trim().isNotEmpty
                ? 'No products match "${_search.text.trim()}".'
                : 'You have no marketplace products yet. Post one first, then tag it here.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
        ),
      );
    }
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, i) {
        final p = items[i];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: p.image.startsWith('http')
                ? Image.network(
                    p.image,
                    width: 50,
                    height: 50,
                    cacheWidth: (50 * dpr).round(),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const _ProductThumbFallback(),
                  )
                : const _ProductThumbFallback(),
          ),
          title: Text(p.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _kInk, fontWeight: FontWeight.w700)),
          trailing: const Icon(Icons.add_circle_outline_rounded, color: _kOrange),
          onTap: () => Navigator.of(context).pop(p),
        );
      },
    );
  }
}

class _ProductThumbFallback extends StatelessWidget {
  const _ProductThumbFallback();

  @override
  Widget build(BuildContext context) => Container(
        width: 50,
        height: 50,
        color: _kOrangeSoft,
        child: const Icon(Icons.shopping_bag_outlined, color: _kOrange),
      );
}

class _ProductSkeleton extends StatelessWidget {
  const _ProductSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFFF0F1F4),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 12, width: double.infinity, color: const Color(0xFFF0F1F4)),
                const SizedBox(height: 8),
                Container(height: 12, width: 120, color: const Color(0xFFF0F1F4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
