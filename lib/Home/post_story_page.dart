// Merchant post story — pick image, upload to Firebase (24h story).

import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:vero360_app/Home/merchant_story_model.dart';
import 'package:vero360_app/Home/story_service.dart';
import 'package:vero360_app/utils/toasthelper.dart';

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

  @override
  void initState() {
    super.initState();
    _storiesFuture = _storyService.getMerchantStories(widget.merchantId);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _priceCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _refreshStories() {
    setState(() {
      _storiesFuture = _storyService.getMerchantStories(widget.merchantId);
    });
  }

  Future<void> _pickAndPost(ImageSource source) async {
    if (_posting) return;
    final XFile? file = await _picker.pickImage(
      source: source,
      maxWidth: 512,
      imageQuality: 70,
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || !mounted) return;
    setState(() => _posting = true);
    try {
      final title = _titleCtrl.text.trim();
      final desc = _descCtrl.text.trim();
      final priceText = _priceCtrl.text.trim();
      num? price;
      if (priceText.isNotEmpty) {
        price = num.tryParse(priceText);
      }

      await _storyService.postStory(
        merchantId: widget.merchantId,
        merchantName: widget.merchantName,
        imageBytes: Uint8List.fromList(bytes),
        merchantImageUrl: widget.merchantImageUrl,
        serviceType: widget.serviceType,
        title: title.isEmpty ? null : title,
        description: desc.isEmpty ? null : desc,
        price: price,
      );
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Story posted! It will disappear after 24 hours.',
        isSuccess: true,
        errorMessage: '',
      );
      Navigator.of(context).pop(true);
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

  Widget _buildStoriesList(List<MerchantStoryItem> items) {
    if (items.isEmpty) {
      return const Text(
        'You have no active stories.',
        style: TextStyle(fontSize: 13),
      );
    }
    return SizedBox(
      height: 90,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = items[index];
          final isDeleting = _deletingStoryId == item.storyId;
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 80,
                  height: 80,
                  color: const Color(0xFFF5F5F5),
                  child: _buildThumbnail(item),
                ),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  iconSize: 18,
                  onPressed:
                      isDeleting ? null : () => _confirmDeleteStory(item),
                  icon: isDeleting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline,
                          color: Colors.redAccent),
                ),
              ),
            ],
          );
        },
      ),
    );
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
          return Row(
            children: const [
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
            _buildStoriesList(items),
          ],
        );
      },
    );
  }

  Future<void> _showSourcePicker() async {
    if (_posting) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const Text(
              'Create story',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Use camera'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source != null) {
      await _pickAndPost(source);
    }
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
        child: Padding(
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
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _posting ? null : _showSourcePicker,
                icon: _posting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.add_a_photo_rounded),
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
            ],
          ),
        ),
      ),
    );
  }
}
