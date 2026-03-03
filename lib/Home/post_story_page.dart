// Merchant post story — pick image, upload to Firebase (24h story).

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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

  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _priceCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();

  Future<void> _pickAndPost() async {
    if (_posting) return;
    final XFile? file = await _picker.pickImage(
      source: ImageSource.gallery,
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
              const SizedBox(height: 18),
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Item / service name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _priceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Price (optional)',
                  prefixText: 'MWK ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Short description (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _posting ? null : _pickAndPost,
                icon: _posting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.add_photo_alternate_rounded),
                label: Text(_posting ? 'Posting...' : 'Choose photo'),
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
