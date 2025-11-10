// lib/pages/marketplace_edit_page.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';

import '../models/marketplace.model.dart';
import '../services/marketplace.service.dart';
import '../toasthelper.dart';

class _LocalMedia {
  final Uint8List bytes;
  final String filename;
  final bool isVideo;
  const _LocalMedia({required this.bytes, required this.filename, this.isVideo = false});
}

class MarketplaceEditPage extends StatefulWidget {
  final MarketplaceDetailModel item;
  const MarketplaceEditPage({super.key, required this.item});

  @override
  State<MarketplaceEditPage> createState() => _MarketplaceEditPageState();
}

class _MarketplaceEditPageState extends State<MarketplaceEditPage> {
  final svc = MarketplaceService();
  final _picker = ImagePicker();

  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _desc;
  bool _isActive = true;
  String? _category;

  String _cover = '';
  final List<String> _gallery = [];
  final List<String> _videos  = [];

  final List<_LocalMedia> _newGallery = [];
  final List<_LocalMedia> _newVideos  = [];

  bool _saving = false;

  // --- Brand (match Airport/Vero Courier) ---
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandSoft   = Color(0xFFFFE8CC);

  @override
  void initState() {
    super.initState();
    final it = widget.item;
    _name  = TextEditingController(text: it.name);
    _price = TextEditingController(text: it.price.toStringAsFixed(0));
    _desc  = TextEditingController(text: it.description);
    _isActive = true; // you can fetch from detail if present
    _category = it.category;
    _cover = it.image;
    _gallery.addAll(it.gallery);
    _videos.addAll(it.videos);
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pickNewImages() async {
    final xs = await _picker.pickMultiImage(imageQuality: 90, maxWidth: 2048);
    for (final x in xs) {
      final b = await x.readAsBytes();
      _newGallery.add(_LocalMedia(bytes: b, filename: x.name));
    }
    setState((){});
  }

  Future<void> _pickNewVideo() async {
    final x = await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 2));
    if (x == null) return;
    _newVideos.add(_LocalMedia(bytes: await x.readAsBytes(), filename: x.name, isVideo: true));
    setState((){});
  }

  Future<void> _changeCover() async {
    final x = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 90, maxWidth: 2048);
    if (x == null) return;
    final url = await svc.uploadBytes(await x.readAsBytes(), filename: x.name);
    setState(() { _cover = url; });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      // upload new media if any
      for (final m in _newGallery) {
        final url = await svc.uploadBytes(m.bytes, filename: m.filename);
        _gallery.add(url);
      }
      for (final m in _newVideos) {
        final url = await svc.uploadBytes(m.bytes, filename: m.filename);
        _videos.add(url);
      }

      final patch = <String, dynamic>{
        'name': _name.text.trim(),
        'price': double.tryParse(_price.text.trim()) ?? widget.item.price,
        'description': _desc.text.trim(),
        'isActive': _isActive,
        if (_category != null) 'category': _category,
        'image': _cover,
        'gallery': _gallery,
        'videos': _videos,
      };

      await svc.updateItem(widget.item.id, patch);
      if (!mounted) return;
      ToastHelper.showCustomToast(context, 'Saved', isSuccess: true, errorMessage: 'Saved');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(context, 'Save failed: $e', isSuccess: false, errorMessage: 'Save failed');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---- UI helpers (no logic changes) ----
  InputDecoration _inputDecoration({String? label, String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.black, width: 1), // black before active
        borderRadius: BorderRadius.circular(12),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: _brandOrange, width: 2),
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    );
  }

  ButtonStyle _filledBtnStyle({double padV = 12}) => FilledButton.styleFrom(
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: padV),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      );

  OutlinedButtonThemeData get _outlinedTheme => OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.black87,
          side: const BorderSide(color: Colors.black, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(outlinedButtonTheme: _outlinedTheme),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Edit Item'),
          backgroundColor: _brandOrange,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: _brandOrange,
          foregroundColor: Colors.white,
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save),
          label: const Text('Save'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            // Cover
            Card(
              elevation: 8,
              shadowColor: Colors.black12,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16/9,
                    child: Image.network(
                      _cover,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade200),
                    ),
                  ),
                  Positioned(
                    right: 8, bottom: 8,
                    child: FilledButton.icon(
                      style: _filledBtnStyle(),
                      onPressed: _changeCover,
                      icon: const Icon(Icons.photo),
                      label: const Text('Change cover'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _name,
              decoration: _inputDecoration(label: 'Name'),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: false),
              decoration: _inputDecoration(label: 'Price (MK)'),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _desc,
              minLines: 2, maxLines: 4,
              decoration: _inputDecoration(label: 'Description'),
            ),
            const SizedBox(height: 16),

            const Text('Photos', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: [
                for (int i = 0; i < _gallery.length; i++)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(_gallery[i], width: 110, height: 90, fit: BoxFit.cover),
                      ),
                      Positioned(
                        right: 4, top: 4,
                        child: InkWell(
                          onTap: () { setState(() { _gallery.removeAt(i); }); },
                          child: const CircleAvatar(
                            radius: 12,
                            backgroundColor: Colors.black54,
                            child: Icon(Icons.close, size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                for (final n in _newGallery)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(n.bytes, width: 110, height: 90, fit: BoxFit.cover),
                  ),
                OutlinedButton.icon(
                  onPressed: _pickNewImages,
                  icon: const Icon(Icons.add_photo_alternate),
                  label: const Text('Add'),
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Text('Videos', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: [
                for (int i = 0; i < _videos.length; i++)
                  Stack(
                    children: [
                      Container(
                        width: 140, height: 80,
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(child: Icon(Icons.play_arrow_rounded)),
                      ),
                      Positioned(
                        right: 4, top: 4,
                        child: InkWell(
                          onTap: () { setState(() { _videos.removeAt(i); }); },
                          child: const CircleAvatar(
                            radius: 12,
                            backgroundColor: Colors.black54,
                            child: Icon(Icons.close, size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                for (final n in _newVideos)
                  Container(
                    width: 140, height: 80,
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(child: Icon(Icons.play_circle_outline)),
                  ),
                OutlinedButton.icon(
                  onPressed: _pickNewVideo,
                  icon: const Icon(Icons.video_library),
                  label: const Text('Add video'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
