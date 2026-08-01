// Merchant post story — photos with caption only, 24h story.

import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:vero360_app/Home/merchant_story_model.dart';
import 'package:vero360_app/Home/story_service.dart';
import 'package:vero360_app/utils/toasthelper.dart';

/// One slide in the composer (before posting) — photo + caption.
class _DraftSlide {
  final Uint8List bytes;
  final TextEditingController captionController;

  _DraftSlide({
    required this.bytes,
    TextEditingController? captionController,
  }) : captionController = captionController ?? TextEditingController();

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
    final Uint8List? bytes = await _pickImage(source);
    if (bytes == null || !mounted) return;
    setState(() {
      _draftSlides.add(_DraftSlide(bytes: bytes));
    });
  }

  Future<Uint8List?> _pickImage(ImageSource source) async {
    final XFile? file = await _picker.pickImage(
      source: source,
      maxWidth: 1024,
      imageQuality: 80,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return bytes.isEmpty ? null : Uint8List.fromList(bytes);
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
          mediaType: 'image',
          caption: cap.isEmpty ? null : cap,
        );
      }).toList();
      await _storyService.postStoryBatch(
        merchantId: widget.merchantId,
        merchantName: widget.merchantName,
        merchantImageUrl: widget.merchantImageUrl,
        serviceType: widget.serviceType,
        slides: slides,
      );
      if (!mounted) return;
      for (final s in _draftSlides) {
        s.dispose();
      }
      _draftSlides.clear();
      ToastHelper.showCustomToast(
        context,
        '${slides.length} story slide(s) posted! Visible for 24 hours.',
        isSuccess: true,
        errorMessage: '',
      );
      setState(() { _loadStoriesAndCounts(); });
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
    final viewers = await _storyService.getStoryViewers(storyId);
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.25,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Text(
                'Viewers (${viewers.length})',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: viewers.isEmpty
                    ? const Center(
                        child: Text(
                          'No one has viewed this story yet.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: viewers.length,
                        itemBuilder: (_, i) {
                          final v = viewers[i];
                          return ListTile(
                            leading: _buildViewerAvatar(v),
                            title: Text(v.viewerName.isEmpty ? 'Unknown' : v.viewerName),
                            subtitle: Text(
                              _formatViewedAt(v.viewedAt),
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildViewerAvatar(StoryViewerInfo v) {
    final hasProfileUrl = v.viewerProfileImageUrl != null && v.viewerProfileImageUrl!.trim().isNotEmpty;
    final fallback = CircleAvatar(
      backgroundColor: const Color(0xFFFF8A00).withOpacity(0.3),
      child: Text(
        (v.viewerName.isNotEmpty ? v.viewerName[0] : '?').toUpperCase(),
        style: const TextStyle(
          color: Color(0xFFFF8A00),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
    if (!hasProfileUrl) return fallback;
    return ClipOval(
      child: Image.network(
        v.viewerProfileImageUrl!,
        fit: BoxFit.cover,
        width: 40,
        height: 40,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }

  String _formatViewedAt(DateTime viewedAt) {
    final d = DateTime.now().difference(viewedAt);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  Widget _buildThumbnail(MerchantStoryItem item) {
    if (item.hasInlineImage && item.imageBase64 != null) {
      try {
        final bytes = base64Decode(item.imageBase64!);
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.store_rounded, color: Colors.grey),
        );
      } catch (_) {
        return const Icon(Icons.store_rounded, color: Colors.grey);
      }
    }
    if (item.mediaUrl.isNotEmpty) {
      return Image.network(
        item.mediaUrl,
        fit: BoxFit.cover,
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
                  'Your current stories',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
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
                  'Add photo',
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
                            'Choose from gallery',
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
                            child: Image.memory(
                              slide.bytes,
                              fit: BoxFit.cover,
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
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _posting ? null : _postAllSlides,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF8A00),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _posting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text('Post all (${_draftSlides.length} slide${_draftSlides.length == 1 ? '' : 's'})'),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Post story'),
        backgroundColor: const Color(0xFFFF8A00),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),
                    const Icon(Icons.auto_stories_rounded, size: 64, color: Color(0xFFFF8A00)),
                    const SizedBox(height: 16),
                    Text(
                      widget.merchantName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF101010),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your story will be visible for 24 hours',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildComposerSection(),
                    _buildCurrentStoriesSection(),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: ElevatedButton.icon(
                onPressed: _posting ? null : _showAddMediaPicker,
                icon: _posting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.add_photo_alternate_rounded),
                label: Text(_posting ? 'Posting...' : 'Add photo'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF8A00),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
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
