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

  const PostStoryPage({
    super.key,
    required this.merchantId,
    required this.merchantName,
    this.merchantImageUrl,
  });

  @override
  State<PostStoryPage> createState() => _PostStoryPageState();
}

class _PostStoryPageState extends State<PostStoryPage> {
  final ImagePicker _picker = ImagePicker();
  final StoryService _storyService = StoryService();
  bool _posting = false;

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
      await _storyService.postStory(
        merchantId: widget.merchantId,
        merchantName: widget.merchantName,
        imageBytes: Uint8List.fromList(bytes),
        merchantImageUrl: widget.merchantImageUrl,
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
