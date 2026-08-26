import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vero360_app/features/Marketplace/MarkeplaceService/marketplace.service.dart';
import 'package:vero360_app/features/Restraurants/Models/food_categories.dart';
import 'package:vero360_app/utils/toasthelper.dart';

/// Add or edit a dish in the merchant's Firestore `food_menu_items`.
class FoodMenuPostPage extends StatefulWidget {
  const FoodMenuPostPage({super.key, this.existingItem});

  /// When set, must include Firestore doc `id` — opens in edit mode.
  final Map<String, dynamic>? existingItem;

  @override
  State<FoodMenuPostPage> createState() => _FoodMenuPostPageState();
}

class _PickedDishPhoto {
  _PickedDishPhoto({required this.bytes, required this.name});
  final Uint8List bytes;
  final String name;
}

class _FoodMenuPostPageState extends State<FoodMenuPostPage> {
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandNavy = Color(0xFF16284C);
  static const int _maxPhotos = 5;

  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _desc = TextEditingController();
  final _prep = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _picker = ImagePicker();
  final _photos = <_PickedDishPhoto>[];
  final _existingPhotoUrls = <String>[];
  String? _category;
  bool _isAvailable = true;
  bool _submitting = false;

  final _variantRows = <_NamedPriceRow>[];
  final _addOnRows = <_NamedPriceRow>[];

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  bool get _isEdit {
    final id = widget.existingItem?['id']?.toString().trim() ?? '';
    return id.isNotEmpty;
  }

  int get _totalPhotoCount => _existingPhotoUrls.length + _photos.length;

  @override
  void initState() {
    super.initState();
    final item = widget.existingItem;
    if (item != null) {
      _hydrateFromExisting(item);
    }
  }

  void _hydrateFromExisting(Map<String, dynamic> item) {
    _name.text = item['name']?.toString() ?? '';
    final price = item['price'];
    if (price is num) {
      _price.text = price.round().toString();
    } else {
      _price.text = price?.toString() ?? '';
    }
    _desc.text = item['description']?.toString() ?? '';
    final prep = item['prepTimeMinutes'];
    if (prep is num && prep > 0) {
      _prep.text = prep.round().toString();
    }
    final qty = item['quantity'];
    if (qty is num && qty >= 1) {
      _quantity.text = qty.round().toString();
    }
    _category = item['category']?.toString();
    _isAvailable = item['isAvailable'] != false;

    _existingPhotoUrls.addAll(_photoUrlsFromItem(item));

    final variants = item['variants'];
    if (variants is List) {
      for (final raw in variants) {
        if (raw is! Map) continue;
        final row = _NamedPriceRow();
        row.name.text = raw['name']?.toString() ?? '';
        final delta = raw['priceDeltaMwk'] ?? raw['priceDelta'] ?? raw['delta'];
        if (delta is num) {
          row.price.text = delta.round().toString();
        } else {
          row.price.text = delta?.toString() ?? '';
        }
        _variantRows.add(row);
      }
    }

    final addOns = item['addOns'];
    if (addOns is List) {
      for (final raw in addOns) {
        if (raw is! Map) continue;
        final row = _NamedPriceRow();
        row.name.text = raw['name']?.toString() ?? '';
        final priceMwk = raw['priceMwk'] ?? raw['price'];
        if (priceMwk is num) {
          row.price.text = priceMwk.round().toString();
        } else {
          row.price.text = priceMwk?.toString() ?? '';
        }
        final def = raw['isDefault'];
        row.isDefault = def == true ||
            def?.toString().trim().toLowerCase() == 'true' ||
            def?.toString() == '1';
        _addOnRows.add(row);
      }
    }
  }

  List<String> _photoUrlsFromItem(Map<String, dynamic> item) {
    final urls = <String>[];
    void add(String? raw) {
      final s = raw?.trim() ?? '';
      if (s.isNotEmpty && !urls.contains(s)) urls.add(s);
    }

    final gallery = item['gallery'];
    if (gallery is List) {
      for (final e in gallery) {
        add(e?.toString());
      }
    }
    final galleryUrls = item['galleryUrls'];
    if (galleryUrls is List) {
      for (final e in galleryUrls) {
        add(e?.toString());
      }
    }
    add(item['imageUrl']?.toString());
    return urls;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _desc.dispose();
    _prep.dispose();
    _quantity.dispose();
    for (final r in _variantRows) {
      r.dispose();
    }
    for (final r in _addOnRows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImages() async {
    final remaining = _maxPhotos - _totalPhotoCount;
    if (remaining <= 0) {
      ToastHelper.showCustomToast(
        context,
        'You can add up to $_maxPhotos photos.',
        isSuccess: false,
        errorMessage: 'Photo limit',
      );
      return;
    }
    final xs = await _picker.pickMultiImage(
      maxWidth: 1600,
      imageQuality: 82,
    );
    if (xs.isEmpty) return;
    final batch = xs.take(remaining);
    final added = <_PickedDishPhoto>[];
    for (final x in batch) {
      final bytes = await x.readAsBytes();
      added.add(_PickedDishPhoto(
        bytes: bytes,
        name: x.name.isNotEmpty ? x.name : 'dish.jpg',
      ));
    }
    if (!mounted) return;
    setState(() => _photos.addAll(added));
    if (xs.length > remaining && mounted) {
      ToastHelper.showCustomToast(
        context,
        'You can add up to $_maxPhotos photos.',
        isSuccess: false,
        errorMessage: 'Photo limit',
      );
    }
  }

  Future<void> _pickOneFromCamera() async {
    if (_totalPhotoCount >= _maxPhotos) return;
    final x = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      imageQuality: 82,
    );
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (!mounted) return;
    setState(() {
      _photos.add(_PickedDishPhoto(
        bytes: bytes,
        name: x.name.isNotEmpty ? x.name : 'dish.jpg',
      ));
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
    if (_totalPhotoCount < 1) {
      ToastHelper.showCustomToast(
        context,
        'Add at least one photo of your dish.',
        isSuccess: false,
        errorMessage: 'Photo required',
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final svc = MarketplaceService();
      final urls = <String>[..._existingPhotoUrls];
      for (var i = 0; i < _photos.length; i++) {
        final photo = _photos[i];
        final mime = lookupMimeType(photo.name, headerBytes: photo.bytes);
        final url = await svc.uploadBytes(
          photo.bytes,
          filename: photo.name,
          mimeType: mime,
        );
        if (url.trim().isNotEmpty) urls.add(url.trim());
      }
      if (urls.isEmpty) {
        throw Exception('Could not upload photos.');
      }
      final cover = urls.first;
      final gallery = urls;

      final prefs = await SharedPreferences.getInstance();
      final businessName = prefs.getString('business_name') ?? '';

      String? restaurantId;
      try {
        final rs = await _db
            .collection('restaurants')
            .where('ownerUid', isEqualTo: uid)
            .limit(1)
            .get();
        if (rs.docs.isNotEmpty) restaurantId = rs.docs.first.id;
      } catch (_) {}

      final variants = <Map<String, dynamic>>[];
      for (final r in _variantRows) {
        final n = r.name.text.trim();
        if (n.isEmpty) continue;
        variants.add({
          'name': n,
          'priceDeltaMwk': double.tryParse(r.price.text.trim()) ?? 0,
        });
      }
      final addOns = <Map<String, dynamic>>[];
      for (final r in _addOnRows) {
        final n = r.name.text.trim();
        if (n.isEmpty) continue;
        addOns.add({
          'name': n,
          'priceMwk': double.tryParse(r.price.text.trim()) ?? 0,
          'isDefault': r.isDefault,
        });
      }
      final prepMins = int.tryParse(_prep.text.trim());
      final quantity = int.tryParse(_quantity.text.trim()) ?? 0;
      if (quantity < 1) {
        throw Exception('Quantity must be at least 1.');
      }

      final payload = <String, dynamic>{
        'merchantId': uid,
        'name': _name.text.trim(),
        'price': double.tryParse(_price.text.trim()) ?? 0,
        'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        'imageUrl': cover,
        'gallery': gallery,
        'galleryUrls': gallery,
        'category': _category,
        'isAvailable': _isAvailable,
        'quantity': quantity,
        if (businessName.isNotEmpty) 'businessName': businessName,
        if (restaurantId != null && restaurantId.isNotEmpty)
          'restaurantId': restaurantId,
        if (variants.isNotEmpty) 'variants': variants,
        if (addOns.isNotEmpty) 'addOns': addOns,
        if (prepMins != null && prepMins > 0) 'prepTimeMinutes': prepMins,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_isEdit) {
        final docId = widget.existingItem!['id'].toString();
        await _db.collection('food_menu_items').doc(docId).update(payload);
      } else {
        await _db.collection('food_menu_items').add({
          ...payload,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        _isEdit ? 'Menu item updated.' : 'Dish added to your menu.',
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
      labelStyle: TextStyle(
        color: Colors.grey.shade600,
        fontWeight: FontWeight.w600,
      ),
      filled: true,
      fillColor: const Color(0xFFF8F9FB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _brandOrange, width: 1.6),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: _brandNavy,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.grey.shade600,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _namedPriceFields({
    required _NamedPriceRow row,
    required String nameLabel,
    required String priceLabel,
    required VoidCallback onRemove,
    bool showDefault = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: row.name,
                  decoration: _decoration(nameLabel),
                  textCapitalization: TextCapitalization.words,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: row.price,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: false),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'-?[0-9]*')),
                  ],
                  decoration: _decoration(priceLabel),
                ),
              ),
              IconButton(
                onPressed: _submitting ? null : onRemove,
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Remove',
              ),
            ],
          ),
          if (showDefault)
            SwitchListTile(
              value: row.isDefault,
              onChanged: _submitting
                  ? null
                  : (v) => setState(() => row.isDefault = v),
              title: const Text('Selected by default'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F7),
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit dish' : 'Post food'),
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
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
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _brandOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
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
                : Icon(_isEdit ? Icons.save_rounded : Icons.check_rounded),
            label: Text(
              _submitting
                  ? 'Saving…'
                  : (_isEdit ? 'Save changes' : 'Save to menu'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _brandOrange.withValues(alpha: 0.12),
                        _brandNavy.withValues(alpha: 0.06),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _brandOrange.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.restaurant_menu_rounded,
                          color: _brandOrange,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Dishes appear on My menu in your food dashboard.',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade800,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _sectionCard(
                  title: 'Photos',
                  subtitle: 'First photo is the cover. Up to $_maxPhotos images.',
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${_totalPhotoCount}/$_maxPhotos',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 118,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            ..._existingPhotoUrls.asMap().entries.map((e) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(14),
                                      child: Image.network(
                                        e.value,
                                        width: 118,
                                        height: 118,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          width: 118,
                                          height: 118,
                                          color: Colors.grey.shade200,
                                          child: const Icon(
                                            Icons.broken_image_outlined,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: Material(
                                        color: Colors.black54,
                                        shape: const CircleBorder(),
                                        child: InkWell(
                                          customBorder: const CircleBorder(),
                                          onTap: _submitting
                                              ? null
                                              : () => setState(() =>
                                                  _existingPhotoUrls
                                                      .removeAt(e.key)),
                                          child: const Padding(
                                            padding: EdgeInsets.all(4),
                                            child: Icon(
                                              Icons.close_rounded,
                                              size: 16,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (e.key == 0 && _photos.isEmpty)
                                      Positioned(
                                        left: 6,
                                        bottom: 6,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _brandOrange,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: const Text(
                                            'Cover',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            }),
                            ..._photos.asMap().entries.map((e) {
                              final displayIndex =
                                  _existingPhotoUrls.length + e.key;
                              return Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(14),
                                      child: Image.memory(
                                        e.value.bytes,
                                        width: 118,
                                        height: 118,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: Material(
                                        color: Colors.black54,
                                        shape: const CircleBorder(),
                                        child: InkWell(
                                          customBorder: const CircleBorder(),
                                          onTap: _submitting
                                              ? null
                                              : () => setState(
                                                  () => _photos.removeAt(e.key),
                                                ),
                                          child: const Padding(
                                            padding: EdgeInsets.all(4),
                                            child: Icon(
                                              Icons.close_rounded,
                                              size: 16,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (displayIndex == 0)
                                      Positioned(
                                        left: 6,
                                        bottom: 6,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _brandOrange,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: const Text(
                                            'Cover',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            }),
                            if (_totalPhotoCount < _maxPhotos)
                              Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: Material(
                                  color: const Color(0xFFF8F9FB),
                                  borderRadius: BorderRadius.circular(14),
                                  child: InkWell(
                                    onTap: _submitting ? null : _pickImages,
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      width: 118,
                                      height: 118,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: _brandOrange
                                              .withValues(alpha: 0.35),
                                          width: 1.2,
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.add_photo_alternate_outlined,
                                            size: 28,
                                            color: _brandOrange
                                                .withValues(alpha: 0.85),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _totalPhotoCount == 0
                                                ? 'Add photos'
                                                : 'Add more',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _submitting ||
                                  _totalPhotoCount >= _maxPhotos
                              ? null
                              : _pickOneFromCamera,
                          icon: const Icon(
                            Icons.photo_camera_outlined,
                            color: _brandOrange,
                          ),
                          label: const Text(
                            'Take a photo',
                            style: TextStyle(
                              color: _brandOrange,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _sectionCard(
                  title: 'Dish details',
                  subtitle: 'Name, category, price, and how much you have ready.',
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _name,
                        decoration: _decoration('Dish name'),
                        textCapitalization: TextCapitalization.words,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Name is required'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _category,
                        decoration: _decoration('Category'),
                        items: kFoodDishCategories
                            .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)),
                            )
                            .toList(),
                        onChanged: _submitting
                            ? null
                            : (v) => setState(() => _category = v),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Pick a category'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _price,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: false,
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: _decoration('Price (MWK)'),
                              validator: (v) {
                                final p = double.tryParse(v?.trim() ?? '');
                                if (p == null || p <= 0) {
                                  return 'Enter a valid price';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _quantity,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: _decoration('Qty available'),
                              validator: (v) {
                                final q = int.tryParse(v?.trim() ?? '');
                                if (q == null || q < 1) {
                                  return 'At least 1';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _desc,
                        minLines: 2,
                        maxLines: 4,
                        decoration: _decoration('Description (optional)'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _prep,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration:
                            _decoration('Prep time (minutes, optional)'),
                      ),
                    ],
                  ),
                ),
                _sectionCard(
                  title: 'Sizes / variants',
                  subtitle: 'Base price plus a delta, e.g. Large = +1500 MWK.',
                  child: Column(
                    children: [
                      ..._variantRows.asMap().entries.map(
                            (e) => _namedPriceFields(
                              row: e.value,
                              nameLabel: 'Size name',
                              priceLabel: 'Price delta (MWK)',
                              onRemove: () => setState(() {
                                e.value.dispose();
                                _variantRows.removeAt(e.key);
                              }),
                            ),
                          ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _submitting
                              ? null
                              : () => setState(
                                  () => _variantRows.add(_NamedPriceRow()),
                                ),
                          icon: const Icon(Icons.add_rounded, color: _brandOrange),
                          label: const Text(
                            'Add variant',
                            style: TextStyle(
                              color: _brandOrange,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _sectionCard(
                  title: 'Add-ons',
                  subtitle: 'Extras the customer can tick, e.g. Extra cheese.',
                  child: Column(
                    children: [
                      ..._addOnRows.asMap().entries.map(
                            (e) => _namedPriceFields(
                              row: e.value,
                              nameLabel: 'Add-on name',
                              priceLabel: 'Price (MWK)',
                              showDefault: true,
                              onRemove: () => setState(() {
                                e.value.dispose();
                                _addOnRows.removeAt(e.key);
                              }),
                            ),
                          ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _submitting
                              ? null
                              : () => setState(
                                  () => _addOnRows.add(_NamedPriceRow()),
                                ),
                          icon: const Icon(Icons.add_rounded, color: _brandOrange),
                          label: const Text(
                            'Add add-on',
                            style: TextStyle(
                              color: _brandOrange,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _sectionCard(
                  title: 'Availability',
                  subtitle: 'Turn off to hide this dish without deleting it.',
                  child: SwitchListTile(
                    value: _isAvailable,
                    onChanged: _submitting
                        ? null
                        : (v) => setState(() => _isAvailable = v),
                    title: const Text(
                      'Show on menu',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      _isAvailable
                          ? 'Customers can order this dish'
                          : 'Hidden from your menu',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    activeThumbColor: _brandOrange,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(height: 72),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NamedPriceRow {
  final name = TextEditingController();
  final price = TextEditingController();
  bool isDefault = false;

  void dispose() {
    name.dispose();
    price.dispose();
  }
}

