import 'dart:convert';
import 'dart:io' show File;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/marketplace_time.dart';
import 'package:vero360_app/utils/description_contact_mask.dart';

/// One photo or video a merchant posted of their shop.
class ShopMediaItem {
  final String id;
  final String merchantId;
  final String url;
  final String storagePath;
  final String kind;
  final DateTime? createdAt;

  const ShopMediaItem({
    required this.id,
    required this.merchantId,
    required this.url,
    required this.storagePath,
    required this.kind,
    this.createdAt,
  });

  bool get isVideo => kind == 'video';

  factory ShopMediaItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    final raw = data['createdAt'];
    DateTime? created;
    if (raw is Timestamp) created = raw.toDate();
    return ShopMediaItem(
      id: doc.id,
      merchantId: (data['merchantId'] ?? '').toString(),
      url: (data['url'] ?? '').toString(),
      storagePath: (data['storagePath'] ?? '').toString(),
      kind: (data['kind'] ?? 'image').toString(),
      createdAt: created,
    );
  }
}

/// Merchant upload screen and the customer gallery for the same shop.
class ShopPicturesPage extends StatefulWidget {
  /// Firebase uids (and any other keys) that own this shop.
  final List<String> merchantIds;
  final String shopName;
  final String description;
  final String? openingHours;
  final List<int> openingDays;
  final String? profileUrl;

  /// True on the merchant dashboard. Customers only browse.
  final bool canManage;

  const ShopPicturesPage({
    super.key,
    required this.merchantIds,
    this.shopName = '',
    this.description = '',
    this.openingHours,
    this.openingDays = const [],
    this.profileUrl,
    this.canManage = false,
  });

  @override
  State<ShopPicturesPage> createState() => _ShopPicturesPageState();
}

class _ShopPicturesPageState extends State<ShopPicturesPage> {
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandNavy = Color(0xFF16284C);

  final _picker = ImagePicker();
  List<ShopMediaItem> _items = const [];
  bool _loading = true;
  bool _uploading = false;
  String? _uploadLabel;
  double? _uploadProgress;
  String? _error;

  List<String> get _ids {
    final seen = <String>{};
    final out = <String>[];
    for (final raw in widget.merchantIds) {
      final id = raw.trim();
      if (id.isEmpty || !seen.add(id)) continue;
      out.add(id);
      if (out.length >= 8) break;
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ids = _ids;
    if (ids.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _items = const [];
      });
      return;
    }
    try {
      final snaps = await Future.wait(
        ids.map(
          (id) => FirebaseFirestore.instance
              .collection('shop_media')
              .where('merchantId', isEqualTo: id)
              .limit(60)
              .get(),
        ),
      );
      final byId = <String, ShopMediaItem>{};
      for (final snap in snaps) {
        for (final doc in snap.docs) {
          final item = ShopMediaItem.fromDoc(doc);
          if (item.url.isEmpty) continue;
          byId[item.id] = item;
        }
      }
      final items = byId.values.toList()
        ..sort((a, b) {
          final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bt.compareTo(at);
        });
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load shop pictures.';
      });
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<ImageSource?> _chooseSource({required bool video}) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                video ? 'Add video' : 'Add photos',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF222222),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                video
                    ? 'Up to 2 minutes and 40 MB. Keep this page open while it uploads.'
                    : 'Each photo up to 8 MB. Photos are resized so they upload faster.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              _cameraAction(
                label: video ? 'Record a video' : 'Take a photo',
                icon: video
                    ? Icons.videocam_outlined
                    : Icons.photo_camera_outlined,
                color: _brandOrange,
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              _cameraAction(
                label: video ? 'Choose a video' : 'Choose photos',
                icon: video
                    ? Icons.video_library_outlined
                    : Icons.photo_library_outlined,
                color: const Color(0xFF1E88E5),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickPhotos() async {
    final source = await _chooseSource(video: false);
    if (source == null || !mounted) return;
    if (source == ImageSource.camera) {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (file == null) return;
      await _uploadAll([file], 'image');
      return;
    }
    final files = await _picker.pickMultiImage(
      imageQuality: 70,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (files.isEmpty) return;
    await _uploadAll(files, 'image');
  }

  Future<void> _pickVideo() async {
    final source = await _chooseSource(video: true);
    if (source == null || !mounted) return;
    final file = await _picker.pickVideo(
      source: source,
      maxDuration: const Duration(minutes: 2),
    );
    if (file == null) return;
    await _uploadAll([file], 'video');
  }

  Future<void> _uploadAll(List<XFile> files, String kind) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      _toast('Sign in to add shop pictures.');
      return;
    }
    setState(() {
      _uploading = true;
      _uploadProgress = null;
      _uploadLabel = kind == 'video'
          ? 'Preparing your video…'
          : 'Preparing your photo…';
    });
    var failed = 0;
    var tooLarge = 0;
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final which = files.length == 1 ? '' : ' ${i + 1} of ${files.length}';
      try {
        final length = await file.length();
        final max = kind == 'video' ? 40 * 1024 * 1024 : 8 * 1024 * 1024;
        if (length > max) {
          tooLarge++;
          continue;
        }
        if (mounted) {
          setState(() {
            _uploadProgress = null;
            _uploadLabel = kind == 'video'
                ? 'Uploading video$which. Keep this page open.'
                : 'Uploading photo$which. This can take a moment.';
          });
        }
        await _uploadOne(
          uid,
          file,
          kind,
          progressPrefix: kind == 'video'
              ? 'Uploading video$which'
              : 'Uploading photo$which',
        );
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() {
      _uploading = false;
      _uploadLabel = null;
      _uploadProgress = null;
    });
    if (tooLarge > 0) {
      _toast(
        kind == 'video'
            ? 'Video must be under 40 MB.'
            : 'Each photo must be under 8 MB.',
      );
    } else if (failed > 0) {
      _toast(
        failed == files.length
            ? 'Upload failed. Try again.'
            : '$failed file${failed == 1 ? '' : 's'} did not upload.',
      );
    }
    await _load();
  }

  Future<void> _uploadOne(
    String uid,
    XFile file,
    String kind, {
    required String progressPrefix,
  }) async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final ext = kind == 'video' ? 'mp4' : 'jpg';
    // profile_photos is already allowed for this account. A new shop_media
    // folder is denied until storage rules are deployed (403).
    final path = 'profile_photos/${uid}_shopmedia_$stamp.$ext';
    final ref = FirebaseStorage.instance.ref(path);
    final meta = SettableMetadata(
      contentType: kind == 'video' ? 'video/mp4' : 'image/jpeg',
    );
    final UploadTask task;
    if (!kIsWeb && file.path.isNotEmpty) {
      task = ref.putFile(File(file.path), meta);
    } else {
      task = ref.putData(await file.readAsBytes(), meta);
    }
    final sub = task.snapshotEvents.listen((snap) {
      if (!mounted) return;
      final total = snap.totalBytes;
      if (total <= 0) return;
      final fraction = (snap.bytesTransferred / total).clamp(0.0, 1.0);
      final percent = (fraction * 100).round();
      final hint = kind == 'video'
          ? 'Keep this page open.'
          : 'This can take a moment.';
      setState(() {
        _uploadProgress = fraction;
        _uploadLabel = '$progressPrefix… $percent%. $hint';
      });
    });
    try {
      await task;
    } finally {
      await sub.cancel();
    }
    final url = await ref.getDownloadURL();
    await FirebaseFirestore.instance.collection('shop_media').add({
      'merchantId': uid,
      'url': url,
      'storagePath': path,
      'kind': kind,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _delete(ShopMediaItem item) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (!widget.canManage || uid.isEmpty || item.merchantId != uid) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this?'),
        content: Text(
          item.isVideo
              ? 'This video will leave your shop gallery.'
              : 'This photo will leave your shop gallery.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      if (item.storagePath.isNotEmpty) {
        await FirebaseStorage.instance.ref(item.storagePath).delete();
      }
    } catch (_) {}
    try {
      await FirebaseFirestore.instance
          .collection('shop_media')
          .doc(item.id)
          .delete();
    } catch (_) {
      _toast('Could not remove that file.');
      return;
    }
    if (!mounted) return;
    setState(() {
      _items = _items.where((e) => e.id != item.id).toList();
    });
  }

  void _open(ShopMediaItem item) {
    if (item.isVideo) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _ShopVideoPage(url: item.url),
        ),
      );
      return;
    }
    final photos = _items.where((e) => !e.isVideo).toList();
    final index = photos.indexWhere((e) => e.id == item.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ShopPhotoPage(
          urls: photos.map((e) => e.url).toList(),
          initialIndex: index < 0 ? 0 : index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.shopName.trim().isEmpty
        ? 'Shop pictures'
        : widget.shopName.trim();
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _brandNavy,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: Color(0xFF222222),
          ),
        ),
      ),
      body: Column(
        children: [
          if (!widget.canManage) _buildShopIntro(),
          if (widget.canManage) _buildAddActions(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  String _hoursLabel() {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final pair = MarketplaceShopHours.parseRange(widget.openingHours);
    final time = pair == null
        ? ''
        : MarketplaceShopHours.formatRangeDisplay(pair.open, pair.close);
    final selected = widget.openingDays.where((d) => d >= 1 && d <= 7).toList()
      ..sort();
    final dayText = selected.isEmpty
        ? ''
        : selected.length == 7
            ? 'Every day'
            : selected.map((d) => days[d - 1]).join(', ');
    if (time.isEmpty && dayText.isEmpty) return 'Hours not set';
    if (dayText.isEmpty) return time;
    if (time.isEmpty) return dayText;
    return '$dayText · $time';
  }

  Widget _profilePhoto() {
    final raw = widget.profileUrl?.trim() ?? '';
    const size = 72.0;
    Widget fallback() => Container(
          width: size,
          height: size,
          color: const Color(0xFFFFF3E6),
          child: const Icon(
            Icons.storefront_rounded,
            color: Color(0xFFFF8A00),
            size: 32,
          ),
        );
    if (raw.isEmpty) return fallback();
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: raw,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) => fallback(),
      );
    }
    try {
      final part = raw.contains(',') ? raw.split(',').last : raw;
      return Image.memory(
        base64Decode(part),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback(),
      );
    } catch (_) {
      return fallback();
    }
  }

  Widget _buildShopIntro() {
    final name = widget.shopName.trim().isEmpty ? 'Shop' : widget.shopName.trim();
    final description = DescriptionContactMask.mask(widget.description.trim());
    final open = MarketplaceShopHours.isOpenNow(
      widget.openingHours,
      widget.openingDays,
    );
    final hasHours = MarketplaceShopHours.parseRange(widget.openingHours) != null;
    final statusColor = !hasHours
        ? Colors.grey.shade700
        : open
            ? Colors.green.shade700
            : Colors.red.shade700;
    final statusLabel = !hasHours
        ? 'HOURS'
        : open
            ? 'OPEN'
            : 'CLOSED';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E6EF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipOval(child: _profilePhoto()),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF222222),
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    description,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.schedule_rounded, size: 16, color: statusColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _hoursLabel(),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF222222),
                        ),
                      ),
                    ),
                  ],
                ),
                if (hasHours) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddActions() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E6EF)),
      ),
      child: Column(
        children: [
          _cameraAction(
            label: 'Add photos',
            subtitle: 'Each photo up to 8 MB',
            icon: Icons.photo_camera_outlined,
            color: _brandOrange,
            onTap: _uploading ? null : _pickPhotos,
          ),
          _cameraAction(
            label: 'Add video',
            subtitle: 'Up to 2 minutes and 40 MB',
            icon: Icons.videocam_outlined,
            color: _brandNavy,
            onTap: _uploading ? null : _pickVideo,
          ),
          if (_uploading)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: _uploadProgress,
                    minHeight: 4,
                    color: const Color(0xFFFF8A00),
                    backgroundColor: const Color(0xFFFFE4C4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _uploadLabel ?? 'Uploading… Keep this page open.',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _cameraAction({
    required String label,
    String? subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: onTap == null ? color.withValues(alpha: 0.45) : color,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF222222),
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF8A00),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.photo_camera_outlined,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                widget.canManage
                    ? 'Add photos and videos of your shop so buyers can see it.'
                    : 'This shop has not added pictures yet.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF222222),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1,
      ),
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        return _tile(item);
      },
    );
  }

  Widget _tile(ShopMediaItem item) {
    return Material(
      color: Colors.white,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E6EF)),
      ),
      child: InkWell(
        onTap: () => _open(item),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (item.isVideo)
              const ColoredBox(
                color: Color(0xFF16284C),
                child: Icon(Icons.videocam_rounded, color: Colors.white70, size: 36),
              )
            else
              CachedNetworkImage(
                imageUrl: item.url,
                fit: BoxFit.cover,
                placeholder: (_, _) => const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                errorWidget: (_, _, _) =>
                    const Icon(Icons.broken_image_outlined),
              ),
            if (item.isVideo)
              const Center(
                child: CircleAvatar(
                  backgroundColor: Colors.black45,
                  child: Icon(Icons.play_arrow_rounded, color: Colors.white),
                ),
              ),
            if (widget.canManage)
              Positioned(
                top: 4,
                right: 4,
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _delete(item),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close_rounded, color: Colors.white, size: 16),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ShopPhotoPage extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;

  const _ShopPhotoPage({required this.urls, required this.initialIndex});

  @override
  State<_ShopPhotoPage> createState() => _ShopPhotoPageState();
}

class _ShopPhotoPageState extends State<_ShopPhotoPage> {
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Shop'),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.urls.length,
        itemBuilder: (_, i) => InteractiveViewer(
          child: Center(
            child: CachedNetworkImage(
              imageUrl: widget.urls[i],
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}

class _ShopVideoPage extends StatefulWidget {
  final String url;

  const _ShopVideoPage({required this.url});

  @override
  State<_ShopVideoPage> createState() => _ShopVideoPageState();
}

class _ShopVideoPageState extends State<_ShopVideoPage> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _controller.play();
    }).catchError((_) {
      if (!mounted) return;
      setState(() => _error = 'Could not play this video.');
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Shop video'),
      ),
      body: Center(
        child: _error != null
            ? Text(_error!, style: const TextStyle(color: Colors.white))
            : !_ready
                ? const CircularProgressIndicator(color: Colors.white)
                : AspectRatio(
                    aspectRatio: _controller.value.aspectRatio == 0
                        ? 16 / 9
                        : _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  ),
      ),
      floatingActionButton: _ready
          ? FloatingActionButton(
              onPressed: () {
                setState(() {
                  _controller.value.isPlaying
                      ? _controller.pause()
                      : _controller.play();
                });
              },
              child: Icon(
                _controller.value.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
              ),
            )
          : null,
    );
  }
}
