import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vero360_app/features/Marketplace/MarkeplaceService/marketplace.service.dart';
import 'package:vero360_app/utils/toasthelper.dart';

/// Add a dish to the merchant's Firestore `food_menu_items` (food category only).
class FoodMenuPostPage extends StatefulWidget {
  const FoodMenuPostPage({super.key});

  @override
  State<FoodMenuPostPage> createState() => _FoodMenuPostPageState();
}

class _FoodMenuPostPageState extends State<FoodMenuPostPage> {
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandNavy = Color(0xFF16284C);

  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _desc = TextEditingController();
  final _picker = ImagePicker();

  Uint8List? _imageBytes;
  String? _imageName;
  bool _isAvailable = true;
  bool _submitting = false;

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 82,
    );
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (!mounted) return;
    setState(() {
      _imageBytes = bytes;
      _imageName = x.name.isNotEmpty ? x.name : 'dish.jpg';
    });
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      ToastHelper.showCustomToast(
        context,
        'Please sign in to add a menu item.',
        isSuccess: false,
        errorMessage: 'Not signed in',
      );
      return;
    }
    if (_imageBytes == null || _imageBytes!.isEmpty) {
      ToastHelper.showCustomToast(
        context,
        'Add a photo of your dish.',
        isSuccess: false,
        errorMessage: 'Photo required',
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final svc = MarketplaceService();
      final mime = lookupMimeType(_imageName ?? 'dish.jpg', headerBytes: _imageBytes);
      final url = await svc.uploadBytes(
        _imageBytes!,
        filename: _imageName ?? 'dish.jpg',
        mimeType: mime,
      );

      final prefs = await SharedPreferences.getInstance();
      final businessName = prefs.getString('business_name') ?? '';

      await _db.collection('food_menu_items').add({
        'merchantId': uid,
        'name': _name.text.trim(),
        'price': double.tryParse(_price.text.trim()) ?? 0,
        'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        'imageUrl': url,
        'category': 'food',
        'isAvailable': _isAvailable,
        if (businessName.isNotEmpty) 'businessName': businessName,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Dish added to your menu.',
        isSuccess: true,
        errorMessage: 'Saved',
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Could not save: $e',
        isSuccess: false,
        errorMessage: 'Save failed',
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add menu item'),
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE8CC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _brandOrange.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.restaurant_menu_rounded, color: _brandNavy),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Food menu only — this appears under My menu on your dashboard.',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: _submitting ? null : _pickImage,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      height: 200,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: _imageBytes == null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_photo_alternate_outlined,
                                    size: 48, color: Colors.grey.shade400),
                                const SizedBox(height: 8),
                                Text(
                                  'Tap to add dish photo',
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              ],
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(15),
                              child: Image.memory(
                                _imageBytes!,
                                width: double.infinity,
                                height: 200,
                                fit: BoxFit.cover,
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _name,
                  decoration: _decoration('Dish name'),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: false),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _decoration('Price (MWK)'),
                  validator: (v) {
                    final p = double.tryParse(v?.trim() ?? '');
                    if (p == null || p <= 0) return 'Enter a valid price';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _desc,
                  minLines: 2,
                  maxLines: 4,
                  decoration: _decoration('Description (optional)'),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _isAvailable,
                  onChanged: _submitting ? null : (v) => setState(() => _isAvailable = v),
                  title: const Text('Available on menu'),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _brandOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(_submitting ? 'Saving…' : 'Save to menu'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
