// Merchant post story â€” photos, a gallery video, or a camera recording.

import 'package:universal_io/io.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:vero360_app/Home/merchant_story_model.dart';
import 'package:vero360_app/Home/story_service.dart';
import 'package:vero360_app/Home/story_viewer_screen.dart';
import 'package:vero360_app/utils/toasthelper.dart';

/// One slide in the composer (before posting) â€” photo or video.
class _DraftSlide {
  final Uint8List bytes;
  final String mediaType;
  final String? videoPath;
  final TextEditingController captionController;

  _DraftSlide({
    required this.bytes,
    this.mediaType = 'image',
    this.videoPath,
    TextEditingController? captionController,
  }) : captionController = captionController ?? TextEditingController();

  bool get isVideo => mediaType == 'video';

  void dispose() => captionController.dispose();
}

class PostStoryPage extends StatefulWidget {
  final String merchantId;
  final String merchantName;
  final String? merchantImageUrl;
  /// marketplace | accommodation | food | courier | ride | taxi | ...
  final String serviceType;

  const PostStoryPage({
    super.key,
    required this.merchantId,
    required this.merchantName,
    this.merchantImageUrl,
    this.serviceType = 'marketplace',
  });

  @override
  State<PostStoryPage> createState() => _PostStoryPageState();
}

class _PostStoryPageState extends State<PostStoryPage> {
  final ImagePicker _picker = ImagePicker();
  final StoryService _storyService = StoryService();
  bool _posting = false;

  // Product / service details for the story
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _priceCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();

  // Existing stories for this merchant
  String? _deletingStoryId;
  late Future<List<MerchantStoryItem>> _storiesFuture;
  /// Viewer counts by storyId (loaded with stories).
  Future<Map<String, int>>? _viewerCountsFuture;
  final List<_DraftSlide> _draftSlides = [];

  @override
  void initState() {
    super.initState();
    _loadStoriesAndCounts();
  }

  void _loadStoriesAndCounts() {
    _storiesFuture = _storyService.getMerchantStories(widget.merchantId);
    _viewerCountsFuture = _storiesFuture.then((items) {
      if (items.isEmpty) return <String, int>{};
      return _storyService.getStoryViewerCounts(items.map((e) => e.storyId).toList());
    });
  }

  @override
  void dispose() {
    for (final s in _draftSlides) {
      s.dispose();
    }
    _titleCtrl.dispose();
    _priceCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _refreshStories() {
    setState(() {
      _loadStoriesAndCounts();
    });
  }

  Future<void> _addSlide(ImageSource source) async {
    if (_posting) return;
    try {
      if (source == ImageSource.gallery) {
        final files = await _picker.pickMultiImage(
          maxWidth: 1600,
          imageQuality: 85,
        );
        if (files.isEmpty || !mounted) return;
        var added = 0;
        var failed = 0;
        for (final file in files) {
          final bytes = await _bytesFromPickedFile(file);
          if (bytes == null) {
            failed++;
            continue;
          }
          _draftSlides.add(_DraftSlide(bytes: bytes));
          added++;
        }
        if (!mounted) return;
        setState(() {});
        if (added > 0 && failed == 0) return;
        if (added > 0 && failed > 0) {
          ToastHelper.showCustomToast(
            context,
            'Added $added photo${added == 1 ? '' : 's'}; $failed could not be used',
            isSuccess: true,
            errorMessage: '',
          );
          return;
        }
        ToastHelper.showCustomToast(
          context,
          'Could not load those photos. Try another photo or take a new one.',
          isSuccess: false,
          errorMessage: '',
        );
        return;
      }

      final XFile? file = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (file == null || !mounted) return; // user cancelled
      final bytes = await _bytesFromPickedFile(file);
      if (bytes == null || !mounted) {
        if (mounted) {
          ToastHelper.showCustomToast(
            context,
            'Could not load that photo. Try another one.',
            isSuccess: false,
            errorMessage: '',
          );
        }
        return;
      }
      setState(() {
        _draftSlides.add(_DraftSlide(bytes: bytes));
      });
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Could not add photo',
        isSuccess: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<Uint8List?> _bytesFromPickedFile(XFile file) async {
    try {
      final raw = await file.readAsBytes();
      if (raw.isEmpty) return null;
      final prepared = await StoryService.prepareStoryImageBytes(
        Uint8List.fromList(raw),
      );
      return prepared.isEmpty ? null : prepared;
    } catch (_) {
      return null;
    }
  }

  void _removeDraftSlide(int index) {
    if (index < 0 || index >= _draftSlides.length) return;
    _draftSlides[index].dispose();
    setState(() => _draftSlides.removeAt(index));
  }

  Future<void> _postAllSlides() async {
    if (_posting || _draftSlides.isEmpty) return;
    setState(() => _posting = true);
    try {
      final slides = _draftSlides.map((s) {
        final cap = s.captionController.text.trim();
        return StorySlideInput(
          bytes: s.bytes,
          mediaType: s.mediaType,
          videoPath: s.videoPath,
          caption: cap.isEmpty ? null : cap,
        );
      }).toList();
      final result = await _storyService.postStoryBatch(
        merchantId: widget.merchantId,
        merchantName: widget.merchantName,
        merchantImageUrl: widget.merchantImageUrl,
        serviceType: widget.serviceType,
        slides: slides,
      );
      if (!mounted) return;

      if (result.allSucceeded) {
        for (final s in _draftSlides) {
          s.dispose();
        }
        _draftSlides.clear();
        ToastHelper.showCustomToast(
          context,
          result.posted == 1
              ? 'Status posted! Visible for 24 hours.'
              : '${result.posted} status updates posted! Visible for 24 hours.',
          isSuccess: true,
          errorMessage: '',
        );
        setState(() {
          _loadStoriesAndCounts();
        });
        return;
      }

      if (result.partial) {
        // Keep only slides that failed so the user can retry them.
        final keep = <_DraftSlide>[];
        for (var i = 0; i < _draftSlides.length; i++) {
          if (result.failedIndexes.contains(i)) {
            keep.add(_draftSlides[i]);
          } else {
            _draftSlides[i].dispose();
          }
        }
        _draftSlides
          ..clear()
          ..addAll(keep);
        ToastHelper.showCustomToast(
          context,
          'Posted ${result.posted}, ${result.failed} failed â€” retry remaining',
          isSuccess: true,
          errorMessage: result.errors.isEmpty ? '' : result.errors.first,
        );
        setState(() {
          _loadStoriesAndCounts();
        });
        return;
      }

      final detail = result.errors.isNotEmpty
          ? result.errors.first
          : 'Please try again with a smaller photo.';
      ToastHelper.showCustomToast(
        context,
        'Failed to post story',
        isSuccess: false,
        errorMessage: detail,
      );
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Failed to post story',
        isSuccess: false,
        errorMessage: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _confirmDeleteStory(MerchantStoryItem item) async {
    if (_deletingStoryId != null) return;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete story'),
        content: const Text('Are you sure you want to delete this story?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _deletingStoryId = item.storyId);
    try {
      await _storyService.deleteStory(item.storyId);
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Story deleted',
        isSuccess: true,
        errorMessage: '',
      );
      _refreshStories();
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Failed to delete story',
        isSuccess: false,
        errorMessage: e.toString(),
      );
    } finally {
      if (mounted) {
        setState(() => _deletingStoryId = null);
      }
    }
  }

  Widget _buildStoriesList(
    List<MerchantStoryItem> items,
    Map<String, int> viewerCounts,
  ) {
    if (items.isEmpty) {
      return const Text(
        'You have no active stories.',
        style: TextStyle(fontSize: 13),
      );
    }
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = items[index];
          final isDeleting = _deletingStoryId == item.storyId;
          final count = viewerCounts[item.storyId] ?? 0;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  GestureDetector(
                    onTap: () => _showViewersSheet(item.storyId),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 80,
                        height: 80,
                        color: const Color(0xFFF5F5F5),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildThumbnail(item),
                            Positioned(
                              left: 4,
                              bottom: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.visibility, color: Colors.white, size: 12),
                                    const SizedBox(width: 4),
                                    Text(
                                      '$count',
                                      style: const TextStyle(color: Colors.white, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      iconSize: 18,
                      onPressed: isDeleting ? null : () => _confirmDeleteStory(item),
                      icon: isDeleting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.delete_outline, color: Colors.redAccent),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '$count view${count == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showViewersSheet(String storyId) async {
    List<StoryViewerInfo> viewers = const [];
    try {
      viewers = await _storyService.getStoryViewers(storyId);
    } catch (_) {}
    if (!mounted) return;
    await showStoryViewersSheet(context, viewers);
  }

  Widget _buildThumbnail(MerchantStoryItem item) {
    if (item.mediaType == 'video') {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 32),
        ),
      );
    }
    final inline = StoryInlineImageCache.bytesFor(item.storyId, item.imageBase64);
    if (inline != null) {
      return Image.memory(
        inline,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.store_rounded, color: Colors.grey),
      );
    }
    if (item.mediaUrl.isNotEmpty) {
      return Image.network(
        item.mediaUrl,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.store_rounded, color: Colors.grey),
      );
    }
    return const Icon(Icons.store_rounded, color: Colors.grey);
  }

  Widget _buildCurrentStoriesSection() {
    return FutureBuilder<List<MerchantStoryItem>>(
      future: _storiesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8),
              Text('Loading your stories...'),
            ],
          );
        }
        if (snapshot.hasError) {
          return const Text(
            'Could not load your stories.',
            style: TextStyle(fontSize: 13, color: Colors.redAccent),
          );
        }
        final items = snapshot.data ?? const <MerchantStoryItem>[];
        return FutureBuilder<Map<String, int>>(
          future: _viewerCountsFuture,
          builder: (ctx, countSnap) {
            final counts = countSnap.data ?? {};
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your current status',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap a photo to see who viewed it',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                _buildStoriesList(items, counts),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showAddMediaPicker() async {
    if (_posting) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Add to status',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: () => Navigator.of(ctx).pop('photo_camera'),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
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
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF8A00),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.photo_camera_outlined,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Take photo',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF222222),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              InkWell(
                onTap: () => Navigator.of(ctx).pop('photo_gallery'),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
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
                          decoration: const BoxDecoration(
                            color: Color(0xFF1E88E5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.photo_library_outlined,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Choose photos',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF222222),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              InkWell(
                onTap: () => Navigator.of(ctx).pop('video_camera'),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
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
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF8A00),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.videocam_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Record video',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF222222),
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Up to 1 minute',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF8A5A32),
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
              InkWell(
                onTap: () => Navigator.of(ctx).pop('video_gallery'),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
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
                          decoration: const BoxDecoration(
                            color: Color(0xFF111111),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.videocam_outlined,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Choose video',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF222222),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'photo_camera') {
      await _addSlide(ImageSource.camera);
    } else if (choice == 'photo_gallery') {
      await _addSlide(ImageSource.gallery);
    } else if (choice == 'video_camera') {
      await _addVideo(ImageSource.camera);
    } else if (choice == 'video_gallery') {
      await _addVideo(ImageSource.gallery);
    }
  }

  Future<void> _addVideo(ImageSource source) async {
    if (_posting) return;
    try {
      final file = await _picker.pickVideo(
        source: source,
        maxDuration: const Duration(minutes: 1),
      );
      if (file == null || !mounted) return;
      final length = await file.length();
      const maxBytes = 40 * 1024 * 1024;
      if (length > maxBytes) {
        ToastHelper.showCustomToast(
          context,
          'That video is too large. Use one under 40 MB.',
          isSuccess: false,
          errorMessage: '',
        );
        return;
      }
      if (length <= 0) {
        ToastHelper.showCustomToast(
          context,
          'That video is empty. Record or choose another one.',
          isSuccess: false,
          errorMessage: '',
        );
        return;
      }
      setState(() {
        _draftSlides.add(
          _DraftSlide(
            bytes: Uint8List(0),
            mediaType: 'video',
            videoPath: file.path,
          ),
        );
      });
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Could not add that video',
        isSuccess: false,
        errorMessage: e.toString(),
      );
    }
  }

  Widget _buildComposerSection() {
    if (_draftSlides.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Add a caption (optional)',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 320,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _draftSlides.length,
            itemBuilder: (context, index) {
              final slide = _draftSlides[index];
              return Container(
                width: 220,
                margin: const EdgeInsets.only(right: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                          child: SizedBox(
                            height: 200,
                            width: double.infinity,
                            child: slide.isVideo
                                ? const ColoredBox(
                                    color: Colors.black,
                                    child: Center(
                                      child: Icon(
                                        Icons.play_circle_fill_rounded,
                                        color: Colors.white,
                                        size: 48,
                                      ),
                                    ),
                                  )
                                : Image.memory(
                                    slide.bytes,
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                  ),
                          ),
                        ),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: IconButton(
                            icon: const Icon(Icons.close, color: Colors.white, size: 22),
                            onPressed: () => _removeDraftSlide(index),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black54,
                              padding: const EdgeInsets.all(6),
                              minimumSize: const Size(36, 36),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: TextField(
                        controller: slide.captionController,
                        decoration: InputDecoration(
                          hintText: 'Type your caption...',
                          hintStyle: TextStyle(fontSize: 14, color: Colors.grey[600]),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFFF8A00), width: 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        maxLines: 3,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${_draftSlides.length} item${_draftSlides.length == 1 ? '' : 's'} ready Â· visible 24h after posting',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildBottomActions() {
    final hasDrafts = _draftSlides.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: hasDrafts
            ? Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _posting ? null : _showAddMediaPicker,
                      icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
                      label: const Text('Add more'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF101010),
                        side: BorderSide(color: Colors.grey.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _posting ? null : _postAllSlides,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF8A00),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _posting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Post now${_draftSlides.length > 1 ? ' (${_draftSlides.length})' : ''}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                    ),
                  ),
                ],
              )
            : SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _posting ? null : _showAddMediaPicker,
                  icon: const Icon(Icons.add_photo_alternate_rounded),
                  label: const Text(
                    'Add photo or video',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8A00),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: const Text(
          'New status',
          style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
        ),
        backgroundColor: const Color(0xFFFF8A00),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFFFF8A00).withValues(alpha: 0.12),
                          const Color(0xFFFFB347).withValues(alpha: 0.06),
                        ],
                      ),
                      border: Border.all(color: const Color(0xFFFF8A00).withValues(alpha: 0.18)),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF8A00).withValues(alpha: 0.25),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.auto_stories_rounded,
                            size: 36,
                            color: Color(0xFFFF8A00),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          widget.merchantName,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF101010),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Share a photo status Â· disappears in 24 hours',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildComposerSection(),
                  _buildCurrentStoriesSection(),
                ],
              ),
            ),
          ),
          _buildBottomActions(),
        ],
      ),
    );
  }
}
