// lib/Pages/MerchantDashboards/accommodation_merchant_dashboard.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import 'package:vero360_app/config/api_config.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vero360_app/GernalServices/merchant_service_helper.dart';
import 'package:vero360_app/features/Marketplace/presentation/pages/main_marketPlace.dart';
import 'package:vero360_app/Home/CustomersProfilepage.dart';
import 'package:vero360_app/GernalScreens/chat_list_page.dart';
import 'package:vero360_app/features/Cart/CartPresentaztion/pages/cartpage.dart';
import 'package:vero360_app/features/Cart/CartService/cart_services.dart';
import 'package:vero360_app/Gernalproviders/cart_service_provider.dart';
import 'package:vero360_app/features/BottomnvarBars/BottomNavbar.dart';
import 'package:vero360_app/features/Marketplace/presentation/MarketplaceMerchant/merchant_wallet.dart';
import 'package:vero360_app/Home/homepage.dart';
import 'package:vero360_app/settings/Settings.dart';
import 'package:vero360_app/Home/post_story_page.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/features/Accomodation/AccomodationModel/accomodation_model.dart';
import 'package:vero360_app/features/Accomodation/AccomodationModel/my_Accodation_bookingdata_model.dart';
import 'package:vero360_app/features/Accomodation/AccomodationService/Accomodation_service.dart';
import 'package:vero360_app/features/Accomodation/AccomodationService/mybookingData_service.dart';
import 'package:vero360_app/features/Accomodation/Presentation/widgets/booking_delete_confirm_dialog.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';
import 'package:intl/intl.dart';

/// Local media for Add Property (cover + gallery) – like marketplace LocalMedia.
class _PropertyMedia {
  final Uint8List bytes;
  final String filename;
  final String? mime;
  const _PropertyMedia({
    required this.bytes,
    required this.filename,
    this.mime,
  });
}

/// Full-screen add listing — avoids bottom sheets closing when opening the image picker.
class _AddPropertyPage extends StatefulWidget {
  const _AddPropertyPage({
    required this.accommodationApi,
    required this.onUploadPhoto,
    required this.showPhotoSourcePicker,
  });

  final AccommodationService accommodationApi;
  final Future<String> Function(_PropertyMedia media) onUploadPhoto;
  final void Function(
    BuildContext anchorContext, {
    required void Function(ImageSource source) onSource,
  }) showPhotoSourcePicker;

  @override
  State<_AddPropertyPage> createState() => _AddPropertyPageState();
}

class _AddPropertyPageState extends State<_AddPropertyPage> {
  static const List<String> _accommodationTypes = [
    'hotel',
    'lodge',
    'bnb',
    'house',
    'hostel',
    'apartment',
  ];
  static const int _maxGalleryPhotos = 5;

  static const Color _orange = Color(0xFFFF8A00);
  static const Color _navy = Color(0xFF16284C);

  final ImagePicker _picker = ImagePicker();
  late final TextEditingController _nameController;
  late final TextEditingController _locationController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _priceController;

  String _selectedType = _accommodationTypes.first;
  AccommodationPricePeriod _selectedPricePeriod =
      AccommodationPricePeriod.night;
  bool _submitting = false;
  _PropertyMedia? _cover;
  final List<_PropertyMedia> _gallery = [];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _locationController = TextEditingController();
    _descriptionController = TextEditingController();
    _priceController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration({
    String? label,
    String? hint,
    bool alignLabelWithHint = false,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      alignLabelWithHint: alignLabelWithHint,
      filled: true,
      fillColor: const Color(0xFFF8F9FC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(14),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: _orange, width: 2),
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _orange.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: _orange),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: Colors.grey.shade900,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickCover(ImageSource src) async {
    final x = await _picker.pickImage(
      source: src,
      imageQuality: 75,
      maxWidth: 1280,
    );
    if (x == null || !mounted) return;
    final bytes = await x.readAsBytes();
    if (!mounted) return;
    final mime = lookupMimeType(x.name, headerBytes: bytes);
    setState(() {
      _cover = _PropertyMedia(bytes: bytes, filename: x.name, mime: mime);
    });
  }

  Future<void> _pickMorePhotos() async {
    if (_gallery.length >= _maxGalleryPhotos) return;
    final files =
        await _picker.pickMultiImage(imageQuality: 72, maxWidth: 1280);
    if (!mounted || files.isEmpty) return;
    final remaining = _maxGalleryPhotos - _gallery.length;
    final batch = <_PropertyMedia>[];
    for (final x in files.take(remaining)) {
      final bytes = await x.readAsBytes();
      batch.add(_PropertyMedia(
        bytes: bytes,
        filename: x.name,
        mime: lookupMimeType(x.name, headerBytes: bytes),
      ));
    }
    if (!mounted) return;
    setState(() => _gallery.addAll(batch));
  }

  Future<void> _pickOneFromCamera() async {
    try {
      if (_gallery.length >= _maxGalleryPhotos) return;
      final x = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 72,
        maxWidth: 1280,
      );
      if (x == null || !mounted) return;
      final bytes = await x.readAsBytes();
      if (!mounted) return;
      setState(() {
        _gallery.add(_PropertyMedia(
          bytes: bytes,
          filename: x.name,
          mime: lookupMimeType(x.name, headerBytes: bytes),
        ));
      });
    } catch (_) {
      if (mounted) {
        ToastHelper.showCustomToast(
          context,
          'Could not take photo. Please try again.',
          isSuccess: false,
          errorMessage: '',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F7),
      appBar: AppBar(
        backgroundColor: _orange,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text(
          'Add property',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Photos, details, and price',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _sectionHeader('Photos', Icons.photo_library_rounded),
                  const SizedBox(height: 12),
                  Text(
                    'Cover image *',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade700,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: _cover == null
                        ? Container(
                            height: 168,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F4F7),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.grey.shade200,
                              ),
                            ),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.image_outlined,
                                    size: 44,
                                    color: Colors.grey.shade400,
                                  ),
                                  const SizedBox(height: 10),
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: _orange,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 12,
                                      ),
                                    ),
                                    onPressed: () {
                                      widget.showPhotoSourcePicker(
                                        context,
                                        onSource: _pickCover,
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.add_photo_alternate_rounded,
                                    ),
                                    label: const Text(
                                      'Select image',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Stack(
                            children: [
                              Image.memory(
                                _cover!.bytes,
                                height: 168,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                              Positioned(
                                top: 10,
                                right: 10,
                                child: Material(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(20),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(20),
                                    onTap: () => setState(() => _cover = null),
                                    child: const Padding(
                                      padding: EdgeInsets.all(8),
                                      child: Icon(
                                        Icons.close_rounded,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Gallery (optional)',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _navy.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_gallery.length}/$_maxGalleryPhotos',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            color: _navy,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _gallery.length >= _maxGalleryPhotos
                              ? null
                              : () {
                                  widget.showPhotoSourcePicker(
                                    context,
                                    onSource: (src) async {
                                      if (src == ImageSource.camera) {
                                        await _pickOneFromCamera();
                                      } else {
                                        await _pickMorePhotos();
                                      }
                                    },
                                  );
                                },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.grey.shade900,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                          icon: const Icon(Icons.collections_outlined),
                          label: Text(
                            _gallery.isEmpty ? 'Add photos' : 'Add more',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                      if (_gallery.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade700,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            side: BorderSide(color: Colors.red.shade200),
                          ),
                          onPressed: () => setState(_gallery.clear),
                          child: const Text(
                            'Clear',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (_gallery.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _gallery.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 1,
                      ),
                      itemBuilder: (_, i) {
                        final m = _gallery[i];
                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.memory(
                                m.bytes,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
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
                                  onTap: () => setState(
                                    () => _gallery.removeAt(i),
                                  ),
                                  child: const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(
                                      Icons.close_rounded,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Divider(height: 1, color: Colors.grey.shade200),
                  ),
                  _sectionHeader('Property details', Icons.home_work_outlined),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: _selectedType,
                    isExpanded: true,
                    decoration: _fieldDecoration(label: 'Type *'),
                    borderRadius: BorderRadius.circular(14),
                    items: _accommodationTypes
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(
                              t[0].toUpperCase() + t.substring(1),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(
                      () => _selectedType = v ?? _accommodationTypes.first,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: _fieldDecoration(
                      label: 'Property name *',
                      hint: 'e.g. Sunset Lodge',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _locationController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: _fieldDecoration(
                      label: 'Location *',
                      hint: 'City, area,district',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descriptionController,
                    minLines: 3,
                    maxLines: 5,
                    decoration: _fieldDecoration(
                      label: 'Description',
                      hint:
                          'Amenities, house rules, what makes it special…',
                      alignLabelWithHint: true,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Divider(height: 1, color: Colors.grey.shade200),
                  ),
                  _sectionHeader('Pricing', Icons.payments_outlined),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<AccommodationPricePeriod>(
                    value: _selectedPricePeriod,
                    isExpanded: true,
                    decoration: _fieldDecoration(label: 'Price is charged *'),
                    borderRadius: BorderRadius.circular(14),
                    items: [
                      for (final e in AccommodationPricePeriod.values)
                        DropdownMenuItem(
                          value: e,
                          child: Text(labelForAccommodationPricePeriod(e)),
                        ),
                    ],
                    onChanged: (v) => setState(
                      () => _selectedPricePeriod =
                          v ?? AccommodationPricePeriod.night,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _fieldDecoration(
                      label: 'Amount (MWK) *',
                      hint: 'e.g. 45000',
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _submitting
                          ? null
                          : () async {
                              if (_cover == null) {
                                ToastHelper.showCustomToast(
                                  context,
                                  'Please add a cover photo',
                                  isSuccess: false,
                                  errorMessage: '',
                                );
                                return;
                              }
                              final name = _nameController.text.trim();
                              final location = _locationController.text.trim();
                              final price = double.tryParse(
                                _priceController.text.trim(),
                              );
                              if (name.isEmpty || location.isEmpty) {
                                ToastHelper.showCustomToast(
                                  context,
                                  'Name and location are required',
                                  isSuccess: false,
                                  errorMessage: '',
                                );
                                return;
                              }
                              if (price == null || price <= 0) {
                                ToastHelper.showCustomToast(
                                  context,
                                  'Enter a valid amount',
                                  isSuccess: false,
                                  errorMessage: '',
                                );
                                return;
                              }
                              setState(() => _submitting = true);
                              try {
                                final coverUrl =
                                    await widget.onUploadPhoto(_cover!);
                                final galleryUrls = <String>[];
                                for (final m in _gallery) {
                                  galleryUrls
                                      .add(await widget.onUploadPhoto(m));
                                }
                                final desc =
                                    _descriptionController.text.trim();
                                final created = await widget
                                    .accommodationApi
                                    .createAccommodation(
                                  name: name,
                                  location: location,
                                  description: desc,
                                  pricePerNight: price,
                                  pricingPeriod: _selectedPricePeriod.apiValue,
                                  accommodationType: _selectedType,
                                  image: coverUrl,
                                  gallery: galleryUrls,
                                );
                                if (!mounted) return;
                                Navigator.pop(
                                  context,
                                  <String, dynamic>{
                                    'created': created,
                                    'name': name,
                                    'location': location,
                                    'description': desc,
                                    'price': price,
                                    'pricingPeriod':
                                        _selectedPricePeriod.apiValue,
                                    'selectedType': _selectedType,
                                    'coverUrl': coverUrl,
                                    'galleryUrls': galleryUrls,
                                  },
                                );
                              } catch (e) {
                                if (mounted) {
                                  setState(() => _submitting = false);
                                }
                                final msg = e is ApiException
                                    ? e.message
                                    : 'Failed to add property';
                                if (mounted) {
                                  ToastHelper.showCustomToast(
                                    context,
                                    msg,
                                    isSuccess: false,
                                    errorMessage: '',
                                  );
                                }
                              }
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: _orange,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Publish property',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AccommodationMerchantDashboard extends StatefulWidget {
  final String email;
  const AccommodationMerchantDashboard({super.key, required this.email});

  @override
  State<AccommodationMerchantDashboard> createState() => _AccommodationMerchantDashboardState();
}

class _AccommodationMerchantDashboardState extends State<AccommodationMerchantDashboard>
    with TickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final MerchantServiceHelper _helper = MerchantServiceHelper();
  // ✅ Use CartService singleton from provider
  final CartService _cartService = CartServiceProvider.getInstance();
  final AccommodationService _accommodationApi = AccommodationService();

  // Brand (match Marketplace merchant)
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandNavy = Color(0xFF16284C);
  static const Color _dialogFieldFill = Color(0xFFF4F6FA);
  static const String _fallbackBusinessLabel = 'Accommodation Provider';

  /// `accommodation_merchants` / `users` — keys backends use for listing name.
  String? _businessNameFromFirestoreMap(Map<String, dynamic>? m) {
    if (m == null) return null;
    for (final k in [
      'businessName',
      'business_name',
      'companyName',
      'company_name',
    ]) {
      final v = m[k]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  bool get _businessNameIsPlaceholder =>
      _businessName.isEmpty || _businessName == _fallbackBusinessLabel;

  void _toastOk(String msg) {
    ToastHelper.showCustomToast(
      context,
      msg,
      isSuccess: true,
      errorMessage: '',
    );
  }

  void _toastErr(String msg) {
    ToastHelper.showCustomToast(
      context,
      msg,
      isSuccess: false,
      errorMessage: '',
    );
  }

  InputDecoration _walletPinFieldDecoration(String hint) {
    final r = BorderRadius.circular(14);
    return InputDecoration(
      hintText: hint,
      counterText: '',
      filled: true,
      fillColor: _dialogFieldFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: r),
      enabledBorder: OutlineInputBorder(
        borderRadius: r,
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: r,
        borderSide: const BorderSide(color: _brandOrange, width: 2),
      ),
    );
  }

  Widget _walletPinDialogHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF8A00), Color(0xFFFFA64D)],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    letterSpacing: -0.35,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Wallet lock (PIN) – like marketplace
  DateTime? _walletUnlockedUntil;
  static const Duration _walletUnlockDuration = Duration(minutes: 5);

  bool get _walletUnlockedNow {
    final until = _walletUnlockedUntil;
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  Map<String, dynamic>? _merchantData;
  List<dynamic> _recentBookings = [];
  final MyBookingService _myBookingService = MyBookingService();
  List<BookingItem> _veroMerchantBookings = [];

  // Profile (editable)
  String _merchantEmail = 'No Email';
  String _merchantPhone = 'No Phone';
  String _merchantProfileUrl = '';
  bool _profileUploading = false;
  final _picker = ImagePicker();

  // Services offered (conferences, bar, pool, etc.)
  List<String> _servicesOffered = [];
  List<dynamic> _rooms = [];
  List<dynamic> _reviews = [];
  bool _isLoading = true;
  bool _initialLoadComplete = false;
  String _uid = '';
  String _businessName = '';
  double _walletBalance = 0;
  
  // Stats (Business Overview uses Vero bookings getters below)
  double _rating = 0.0;
  String _status = 'pending';
  int _availableRooms = 0;

  /// Business Overview — from Vero API (`_veroMerchantBookings`), not Firestore `bookings` capped at 20.
  int get _overviewBookingCount => _veroMerchantBookings.length;

  /// Sum of `price + bookingFee` for paid/settled stays ([BookingItem.countsTowardHostRevenue]).
  double get _overviewRevenueMwk => _veroMerchantBookings
      .where((b) => b.countsTowardHostRevenue)
      .fold<double>(0, (s, b) => s + b.total.toDouble());

  /// Distinct guests among pending + confirmed stays (email, else name, else booking id).
  int get _overviewActiveGuestsCount {
    final relevant = _veroMerchantBookings.where((b) =>
        b.status == BookingStatus.pending ||
        b.status == BookingStatus.confirmed);
    if (relevant.isEmpty) return 0;
    final keys = <String>{};
    for (final b in relevant) {
      final email = (b.guestEmail ?? '').trim().toLowerCase();
      final name = (b.guestName ?? '').trim().toLowerCase();
      keys.add(email.isNotEmpty
          ? email
          : (name.isNotEmpty ? name : b.id));
    }
    return keys.length;
  }

  // Navigation State
  int _selectedIndex = 0;

  // Tabs for dashboard content
  TabController? _accommodationTabs;

  @override
  void initState() {
    super.initState();
    _accommodationTabs = TabController(length: 3, vsync: this);
    _loadMerchantData();
    // No periodic refresh – data updates only on pull-to-refresh
  }

  @override
  void dispose() {
    _accommodationTabs?.dispose();
    super.dispose();
  }

  

  Future<void> _loadMerchantData({bool showLoading = true}) async {
    if (!mounted) return;

    if (showLoading) setState(() => _isLoading = true);
    
    final prefs = await SharedPreferences.getInstance();
    _uid = _auth.currentUser?.uid ?? prefs.getString('uid') ?? '';
    _businessName = (prefs.getString('business_name') ?? '').trim();
    if (_businessName.isEmpty) {
      _businessName = _fallbackBusinessLabel;
    }

    if (_uid.isNotEmpty) {
      try {
        final dashboardData = await _helper.getMerchantDashboardData(_uid, 'accommodation');

        if (!dashboardData.containsKey('error')) {
          final merchantMap =
              dashboardData['merchant'] as Map<String, dynamic>?;
          final fromMerchant = _businessNameFromFirestoreMap(merchantMap);
          if (fromMerchant != null && fromMerchant.isNotEmpty) {
            unawaited(prefs.setString('business_name', fromMerchant));
          }
          setState(() {
            _merchantData = merchantMap;
            _recentBookings = dashboardData['recentOrders'] ?? [];
            _rating = dashboardData['merchant']?['rating'] ?? 0.0;
            _status = dashboardData['merchant']?['status'] ?? 'pending';
            if (fromMerchant != null && fromMerchant.isNotEmpty) {
              _businessName = fromMerchant;
            }
          });
        }

        // Parallelize independent I/O; reviews/services refresh UI when ready (non-blocking).
        await Future.wait<void>([
          _loadRooms(),
          _loadWalletBalance(),
          _loadProfileFromAuthAndFirestore(),
          _loadVeroMerchantBookings(),
        ]);
        await _calculateAvailableRooms();
      } catch (e) {
        print('Error loading accommodation data: $e');
      }
    }

    if (mounted) {
      setState(() {
        if (showLoading) _isLoading = false;
        _initialLoadComplete = true;
      });
    }

    if (_uid.isNotEmpty && mounted) {
      unawaited(_loadServicesOffered());
      unawaited(_loadReviews());
    }
  }

  Future<void> _loadRooms() async {
    try {
      final email = (_auth.currentUser?.email ?? widget.email).trim();

      final fsFuture = _firestore
          .collection('accommodation_rooms')
          .where('merchantId', isEqualTo: _uid)
          .get();

      final Future<List<Accommodation>> apiFuture = email.isNotEmpty
          ? _accommodationApi.fetchOwnedByEmail(email).catchError((e, _) {
              print('Error loading API properties: $e');
              return <Accommodation>[];
            })
          : Future<List<Accommodation>>.value([]);

      final results = await Future.wait<Object?>([fsFuture, apiFuture]);
      final snapshot = results[0]! as QuerySnapshot<Map<String, dynamic>>;
      final mine = results[1]! as List<Accommodation>;

      final fsRooms = snapshot.docs.map((doc) {
        final data = doc.data();
        return <String, dynamic>{
          'id': doc.id,
          ...data,
        };
      }).toList();

      final apiRows = mine.map(_accommodationRowFromApi).toList();

      final apiIds = apiRows
          .map((r) => r['apiAccommodationId'])
          .whereType<int>()
          .toSet();
      final fsFiltered = fsRooms.where((r) {
        final pid = _apiAccommodationId(r);
        if (pid != null && apiIds.contains(pid)) return false;
        return true;
      }).toList();

      if (mounted) {
        setState(() {
          _rooms = [...apiRows, ...fsFiltered];
        });
      }
    } catch (e) {
      print('Error loading properties: $e');
    }
  }

  int? _apiAccommodationId(Map<String, dynamic> room) {
    final direct = room['apiAccommodationId'];
    if (direct is int) return direct;
    if (direct is num) return direct.toInt();
    final id = room['id'];
    if (id is int && id > 0) return id;
    if (id is String) {
      final parsed = int.tryParse(id);
      if (parsed != null && parsed > 0) return parsed;
      if (id.startsWith('api-')) {
        final rest = int.tryParse(id.substring(4));
        if (rest != null && rest > 0) return rest;
      }
    }
    return null;
  }

  Map<String, dynamic> _accommodationRowFromApi(Accommodation a) {
    final img = (a.image ?? '').trim();
    return {
      'id': a.id.toString(),
      'apiAccommodationId': a.id,
      'name': a.name,
      'location': a.location,
      if (a.description.isNotEmpty) 'description': a.description,
      'price': a.price.toDouble(),
      'pricePerNight': a.price,
      'pricingPeriod': a.pricePeriod.apiValue,
      'accommodationType': a.accommodationType,
      'type': a.accommodationType,
      'merchantId': _uid,
      'isAvailable': true,
      'capacity': 1,
      'image': img,
      'imageUrl': img,
      'galleryUrls': List<String>.from(a.gallery),
      '_fromApi': true,
    };
  }

  String _merchantPropertyCoverUrl(Map<String, dynamic> room) {
    for (final k in ['imageUrl', 'image', 'photoUrl', 'coverImage']) {
      final v = room[k]?.toString().trim() ?? '';
      if (v.isNotEmpty &&
          (v.startsWith('http://') || v.startsWith('https://'))) {
        return v;
      }
    }
    return '';
  }

  String _formatMerchantPriceWhole(num value) =>
      NumberFormat('#,##0').format(value.round());

  Widget _propertyThumbPlaceholder() {
    return ColoredBox(
      color: Colors.grey.shade200,
      child: Center(
        child: Icon(
          Icons.apartment_rounded,
          color: Colors.grey.shade500,
          size: 40,
        ),
      ),
    );
  }

  Widget _deletePropertyDialogBullet(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.shade100),
            ),
            child: Icon(icon, size: 17, color: Colors.red.shade700),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  color: Colors.grey.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteProperty(Map<String, dynamic> room) async {
    final id = _apiAccommodationId(room);
    if (id == null) {
      _toastErr('Only your listings can be deleted from here.');
      return;
    }
    final name = (room['name'] ?? 'This property').toString();
    final location = (room['location'] ?? '').toString().trim();
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Material(
            color: Colors.white,
            elevation: 24,
            shadowColor: Colors.black.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.red.shade400,
                        Colors.red.shade700,
                      ],
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.delete_forever_rounded,
                          color: Colors.white,
                          size: 34,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Delete this property?',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This cannot be undone.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Listing',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F6FA),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _brandOrange.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.apartment_rounded,
                                color: _brandOrange,
                                size: 22,
                              ),
                            ),
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
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  if (location.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      location,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: Colors.grey.shade600,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'WHAT HAPPENS NEXT',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.7,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _deletePropertyDialogBullet(
                        Icons.travel_explore_outlined,
                        'This property disappears from search and guest listings.',
                      ),
                      _deletePropertyDialogBullet(
                        Icons.event_busy_outlined,
                        'Future availability for this listing is removed.',
                      ),
                      _deletePropertyDialogBullet(
                        Icons.history_toggle_off_rounded,
                        'You will not be able to restore it from the app.',
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _brandNavy,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                          child: const Text(
                            'Keep property',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFD32F2F),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Delete',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
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
    if (ok != true || !mounted) return;
    try {
      await _accommodationApi.deleteAccommodation(id);
      if (!mounted) return;
      setState(() {
        _rooms.removeWhere(
          (r) => _apiAccommodationId(r as Map<String, dynamic>) == id,
        );
      });
      await _calculateAvailableRooms();
      _toastOk('Property deleted');
    } catch (e) {
      final msg = e is ApiException ? e.message : 'Could not delete property';
      if (mounted) _toastErr(msg);
    }
  }

  Future<void> _loadProfileFromAuthAndFirestore() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      String email = (user.email ?? '').trim();
      String phone = (user.phoneNumber ?? '').trim();
      String photo = (user.photoURL ?? '').trim();
      if (email.isEmpty) email = 'No Email';
      if (phone.isEmpty) phone = 'No Phone';

      final doc = await _firestore.collection('users').doc(user.uid).get();
      final data = doc.data();
      String? nameFromUser;
      if (data != null && mounted) {
        final p = (data['phone'] ?? '').toString().trim();
        final e = (data['email'] ?? '').toString().trim();
        final pic = (data['profilePicture'] ?? data['profilepicture'] ?? '')
            .toString()
            .trim();
        if (p.isNotEmpty) phone = p;
        if (e.isNotEmpty) email = e;
        if (pic.isNotEmpty) photo = pic;
        nameFromUser = _businessNameFromFirestoreMap(data);
      }
      if (mounted) {
        var upgradedName = false;
        setState(() {
          _merchantEmail = email;
          _merchantPhone = phone;
          _merchantProfileUrl = photo;
          if (nameFromUser != null &&
              nameFromUser.isNotEmpty &&
              _businessNameIsPlaceholder) {
            _businessName = nameFromUser;
            upgradedName = true;
          }
        });
        if (upgradedName) {
          unawaited(SharedPreferences.getInstance().then(
            (p) => p.setString('business_name', _businessName),
          ));
        }
      }
    } catch (_) {}
  }

  Future<void> _loadServicesOffered() async {
    if (_uid.isEmpty) return;
    try {
      final doc = await _firestore
          .collection('accommodation_merchants')
          .doc(_uid)
          .get();
      final data = doc.data();
      if (data == null || !mounted) return;
      final list = data['servicesOffered'] as List<dynamic>?;
      final resolvedBusinessName = _businessNameFromFirestoreMap(data);
      final upgradeName = resolvedBusinessName != null &&
          resolvedBusinessName.isNotEmpty &&
          _businessNameIsPlaceholder;
      if (list == null && !upgradeName) return;
      if (upgradeName) {
        unawaited(SharedPreferences.getInstance().then(
          (p) => p.setString('business_name', resolvedBusinessName),
        ));
      }
      if (!mounted) return;
      setState(() {
        if (list != null) {
          _servicesOffered = list.map((e) => e.toString()).toList();
        }
        if (upgradeName) {
          _businessName = resolvedBusinessName;
        }
      });
    } catch (_) {}
  }

  Future<void> _saveServicesOffered() async {
    if (_uid.isEmpty) return;
    try {
      await _firestore
          .collection('accommodation_merchants')
          .doc(_uid)
          .set({
        'servicesOffered': _servicesOffered,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) ToastHelper.showCustomToast(context, 'Services saved', isSuccess: true, errorMessage: '');
    } catch (_) {
      if (mounted) ToastHelper.showCustomToast(context, 'Failed to save', isSuccess: false, errorMessage: '');
    }
  }

  /// Resize/compress before multipart upload (faster, smaller files).
  Uint8List _bytesForAccommodationApiImage(Uint8List raw) {
    try {
      final decoded = img.decodeImage(raw);
      if (decoded == null) return raw;
      var im = decoded;
      const maxSide = 1024;
      if (im.width > maxSide || im.height > maxSide) {
        if (im.width >= im.height) {
          im = img.copyResize(
            im,
            width: maxSide,
            interpolation: img.Interpolation.linear,
          );
        } else {
          im = img.copyResize(
            im,
            height: maxSide,
            interpolation: img.Interpolation.linear,
          );
        }
      }
      return Uint8List.fromList(img.encodeJpg(im, quality: 78));
    } catch (_) {
      return raw;
    }
  }

  /// Data URL helper kept for hot-reload / stale isolate compatibility (publish uses upload URLs).
  // ignore: unused_element
  String _propertyImageDataUrl(_PropertyMedia media) {
    final jpegBytes = _bytesForAccommodationApiImage(media.bytes);
    return 'data:image/jpeg;base64,${base64Encode(jpegBytes)}';
  }

  String _jpegUploadName(String filename) {
    final trimmed = filename.trim();
    if (trimmed.isEmpty) return 'accommodation.jpg';
    final dot = trimmed.lastIndexOf('.');
    final base = dot > 0 ? trimmed.substring(0, dot) : trimmed;
    final safe = base.replaceAll(RegExp(r'[^\w\-]+'), '_');
    return '${safe.isEmpty ? 'photo' : safe}.jpg';
  }

  /// Backend expects `image` / gallery entries as short https URLs from `/vero/uploads`.
  Future<String> _uploadPropertyPhotoForApi(_PropertyMedia media) async {
    final bytes = _bytesForAccommodationApiImage(media.bytes);
    return _accommodationApi.uploadListingImage(
      bytes,
      filename: _jpegUploadName(media.filename),
      mimeType: 'image/jpeg',
    );
  }

  InputDecoration _propertyFormDecoration({
    String? label,
    String? hint,
    bool alignLabelWithHint = false,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      alignLabelWithHint: alignLabelWithHint,
      filled: true,
      fillColor: const Color(0xFFF8F9FC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(14),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: _brandOrange, width: 2),
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }

  Widget _addPropertySheetSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _brandOrange.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: _brandOrange),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: Colors.grey.shade900,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ],
    );
  }

  void _showAddPropertySheet() {
    Navigator.push<Map<String, dynamic>?>(
      context,
      MaterialPageRoute<Map<String, dynamic>?>(
        builder: (ctx) => _AddPropertyPage(
          accommodationApi: _accommodationApi,
          onUploadPhoto: _uploadPropertyPhotoForApi,
          showPhotoSourcePicker: _showAccommodationPhotoSourcePicker,
        ),
      ),
    ).then((payload) {
      if (payload == null || !mounted) return;
      final created = payload['created'];
      final name = payload['name'] as String? ?? '';
      final location = payload['location'] as String? ?? '';
      final desc = payload['description'] as String? ?? '';
      final price = (payload['price'] as num?)?.toDouble() ?? 0.0;
      final pricingPeriod =
          (payload['pricingPeriod'] as String?)?.trim().toLowerCase() ??
              'night';
      final selectedType = payload['selectedType'] as String? ?? 'hotel';
      final coverUrl = payload['coverUrl'] as String? ?? '';
      final galleryUrls = (payload['galleryUrls'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          <String>[];
      final newId = (created is Map && created['id'] != null)
          ? created['id'].toString()
          : 'api-${DateTime.now().millisecondsSinceEpoch}';
      final roomMap = <String, dynamic>{
        'id': newId,
        'name': name,
        'location': location,
        if (desc.isNotEmpty) 'description': desc,
        'price': price,
        'pricePerNight': price,
        'pricingPeriod': pricingPeriod,
        'accommodationType': selectedType,
        'type': selectedType,
        'merchantId': _uid,
        'isAvailable': true,
        'capacity': 1,
        'image': coverUrl,
        'imageUrl': coverUrl,
        'galleryUrls': galleryUrls,
      };
      final apiNumeric = created is Map
          ? () {
              final id = created['id'];
              if (id is int) return id;
              if (id is num) return id.toInt();
              return int.tryParse(id?.toString() ?? '');
            }()
          : int.tryParse(newId);
      if (apiNumeric != null && apiNumeric > 0 && _uid.isNotEmpty) {
        unawaited(
          _firestore
              .collection('accommodation_rooms')
              .doc('${_uid}_$apiNumeric')
              .set(
            {
              'merchantId': _uid,
              'apiAccommodationId': apiNumeric,
              'pricingPeriod': pricingPeriod,
            },
            SetOptions(merge: true),
          ),
        );
      }
      setState(() {
        _rooms = [roomMap, ..._rooms];
      });
      _calculateAvailableRooms();
      _accommodationTabs?.animateTo(1);
      ToastHelper.showCustomToast(
        context,
        'Property added successfully',
        isSuccess: true,
        errorMessage: '',
      );
    });
  }

  void _showEditPropertySheet(Map<String, dynamic> room) {
    final apiId = _apiAccommodationId(room);
    if (apiId == null) {
      _toastErr(
        'Only listings created on the server can be edited here. Legacy room records stay in Firestore only.',
      );
      return;
    }

    const accommodationTypes = [
      'hotel',
      'lodge',
      'bnb',
      'house',
      'hostel',
      'apartment',
    ];
    const maxGalleryPhotos = 5;
    final rawType = (room['accommodationType'] ?? room['type'] ?? 'hotel')
        .toString()
        .toLowerCase()
        .trim();
    String selectedType = accommodationTypes.contains(rawType)
        ? rawType
        : accommodationTypes.first;

    final nameController =
        TextEditingController(text: (room['name'] ?? '').toString());
    final locationController =
        TextEditingController(text: (room['location'] ?? '').toString());
    final descriptionController =
        TextEditingController(text: (room['description'] ?? '').toString());
    final priceVal = room['pricePerNight'] ?? room['price'] ?? 0;
    final priceController =
        TextEditingController(text: priceVal.toString());
    var selectedPricePeriod = accommodationPricePeriodFromDynamic(
      room['pricingPeriod'] ?? room['pricePeriod'],
    );

    String existingCoverUrl =
        (room['image'] ?? room['imageUrl'] ?? '').toString().trim();
    _PropertyMedia? newCover;
    final keptGalleryUrls = <String>[];
    final g1 = room['galleryUrls'];
    if (g1 is List) {
      keptGalleryUrls.addAll(
        g1.map((e) => e.toString()).where((s) => s.isNotEmpty),
      );
    }
    final g2 = room['gallery'];
    if (g2 is List && keptGalleryUrls.isEmpty) {
      keptGalleryUrls.addAll(
        g2.map((e) => e.toString()).where((s) => s.isNotEmpty),
      );
    }
    List<_PropertyMedia> newGallery = [];
    bool submitting = false;

    Future<void> pickCover(ImageSource src) async {
      final x = await _picker.pickImage(
        source: src,
        imageQuality: 75,
        maxWidth: 1280,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      final mime = lookupMimeType(x.name, headerBytes: bytes);
      newCover = _PropertyMedia(bytes: bytes, filename: x.name, mime: mime);
    }

    Future<void> pickMorePhotos() async {
      final total = keptGalleryUrls.length + newGallery.length;
      if (total >= maxGalleryPhotos) return;
      final files =
          await _picker.pickMultiImage(imageQuality: 72, maxWidth: 1280);
      if (files.isEmpty) return;
      final remaining = maxGalleryPhotos - total;
      for (final x in files.take(remaining)) {
        final bytes = await x.readAsBytes();
        newGallery.add(_PropertyMedia(
          bytes: bytes,
          filename: x.name,
          mime: lookupMimeType(x.name, headerBytes: bytes),
        ));
      }
    }

    Future<void> pickOneFromCamera() async {
      try {
        final total = keptGalleryUrls.length + newGallery.length;
        if (total >= maxGalleryPhotos) return;
        final x = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 72,
          maxWidth: 1280,
        );
        if (x == null) return;
        final bytes = await x.readAsBytes();
        newGallery.add(_PropertyMedia(
          bytes: bytes,
          filename: x.name,
          mime: lookupMimeType(x.name, headerBytes: bytes),
        ));
      } catch (e) {
        if (mounted) {
          _toastErr('Could not take photo. Please try again.');
        }
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFFF3F4F7),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (_, setLocal) {
          final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
          final galleryCount = keptGalleryUrls.length + newGallery.length;
          return Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Colors.black.withValues(alpha: 0.06)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    _brandNavy,
                                    _brandNavy.withValues(alpha: 0.85),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.home_work_rounded,
                                color: Colors.white,
                                size: 26,
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Text(
                                'Edit property',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.4,
                                ),
                              ),
                            ),
                            Material(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => Navigator.pop(ctx),
                                child: const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: Icon(Icons.close_rounded, size: 22),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        _addPropertySheetSectionHeader(
                          'Photos',
                          Icons.photo_library_rounded,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Cover image *',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: newCover != null
                              ? Stack(
                                  children: [
                                    Image.memory(
                                      newCover!.bytes,
                                      height: 168,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                    ),
                                    Positioned(
                                      top: 10,
                                      right: 10,
                                      child: Material(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(20),
                                        child: InkWell(
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          onTap: () {
                                            newCover = null;
                                            setLocal(() {});
                                          },
                                          child: const Padding(
                                            padding: EdgeInsets.all(8),
                                            child: Icon(
                                              Icons.close_rounded,
                                              color: Colors.white,
                                              size: 18,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : existingCoverUrl.isNotEmpty
                                  ? Stack(
                                      children: [
                                        Image.network(
                                          existingCoverUrl,
                                          height: 168,
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              Container(
                                            height: 168,
                                            color: Colors.grey.shade200,
                                            child: const Icon(Icons.broken_image),
                                          ),
                                        ),
                                        Positioned(
                                          bottom: 10,
                                          right: 10,
                                          child: FilledButton.icon(
                                            style: FilledButton.styleFrom(
                                              backgroundColor: _brandOrange,
                                              foregroundColor: Colors.white,
                                            ),
                                            onPressed: () {
                                              _showAccommodationPhotoSourcePicker(
                                                ctx,
                                                onSource: (src) async {
                                                  await pickCover(src);
                                                  if (ctx.mounted) {
                                                    setLocal(() {});
                                                  }
                                                },
                                              );
                                            },
                                            icon: const Icon(
                                                Icons.swap_horiz_rounded),
                                            label: const Text('Replace'),
                                          ),
                                        ),
                                      ],
                                    )
                                  : Container(
                                      height: 168,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF3F4F7),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                            color: Colors.grey.shade200),
                                      ),
                                      child: Center(
                                        child: FilledButton.icon(
                                          style: FilledButton.styleFrom(
                                            backgroundColor: _brandOrange,
                                            foregroundColor: Colors.white,
                                          ),
                                          onPressed: () {
                                            _showAccommodationPhotoSourcePicker(
                                              ctx,
                                              onSource: (src) async {
                                                await pickCover(src);
                                                if (ctx.mounted) {
                                                  setLocal(() {});
                                                }
                                              },
                                            );
                                          },
                                          icon: const Icon(
                                              Icons.add_photo_alternate_rounded),
                                          label: const Text('Select image'),
                                        ),
                                      ),
                                    ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Gallery',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                            ),
                            Text(
                              '$galleryCount/$maxGalleryPhotos',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                                color: _brandNavy,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (keptGalleryUrls.isNotEmpty) ...[
                          SizedBox(
                            height: 72,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: keptGalleryUrls.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (_, i) {
                                final url = keptGalleryUrls[i];
                                return Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.network(
                                        url,
                                        width: 72,
                                        height: 72,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            Container(
                                          width: 72,
                                          height: 72,
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 2,
                                      right: 2,
                                      child: Material(
                                        color: Colors.black54,
                                        shape: const CircleBorder(),
                                        child: InkWell(
                                          customBorder: const CircleBorder(),
                                          onTap: () {
                                            keptGalleryUrls.removeAt(i);
                                            setLocal(() {});
                                          },
                                          child: const Padding(
                                            padding: EdgeInsets.all(4),
                                            child: Icon(
                                              Icons.close_rounded,
                                              size: 14,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        OutlinedButton.icon(
                          onPressed: galleryCount >= maxGalleryPhotos
                              ? null
                              : () {
                                  _showAccommodationPhotoSourcePicker(
                                    ctx,
                                    onSource: (src) async {
                                      if (src == ImageSource.camera) {
                                        await pickOneFromCamera();
                                      } else {
                                        await pickMorePhotos();
                                      }
                                      if (ctx.mounted) setLocal(() {});
                                    },
                                  );
                                },
                          icon: const Icon(Icons.collections_outlined),
                          label: const Text('Add photos'),
                        ),
                        if (newGallery.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: newGallery.length,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 1,
                            ),
                            itemBuilder: (_, i) {
                              final m = newGallery[i];
                              return Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.memory(
                                      m.bytes,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      height: double.infinity,
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
                                        onTap: () {
                                          newGallery.removeAt(i);
                                          setLocal(() {});
                                        },
                                        child: const Padding(
                                          padding: EdgeInsets.all(4),
                                          child: Icon(
                                            Icons.close_rounded,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Divider(
                            height: 1,
                            color: Colors.grey.shade200,
                          ),
                        ),
                        _addPropertySheetSectionHeader(
                          'Property details',
                          Icons.home_work_outlined,
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          value: selectedType,
                          isExpanded: true,
                          decoration: _propertyFormDecoration(label: 'Type *'),
                          borderRadius: BorderRadius.circular(14),
                          items: accommodationTypes
                              .map(
                                (t) => DropdownMenuItem(
                                  value: t,
                                  child: Text(
                                    t[0].toUpperCase() + t.substring(1),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setLocal(
                            () => selectedType =
                                v ?? accommodationTypes.first,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: nameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: _propertyFormDecoration(
                            label: 'Property name *',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: locationController,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: _propertyFormDecoration(
                            label: 'Location *',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: descriptionController,
                          minLines: 3,
                          maxLines: 5,
                          decoration: _propertyFormDecoration(
                            label: 'Description',
                            alignLabelWithHint: true,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Divider(
                            height: 1,
                            color: Colors.grey.shade200,
                          ),
                        ),
                        _addPropertySheetSectionHeader(
                          'Pricing',
                          Icons.payments_outlined,
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<AccommodationPricePeriod>(
                          value: selectedPricePeriod,
                          isExpanded: true,
                          decoration:
                              _propertyFormDecoration(label: 'Price is charged *'),
                          borderRadius: BorderRadius.circular(14),
                          items: [
                            for (final e in AccommodationPricePeriod.values)
                              DropdownMenuItem(
                                value: e,
                                child: Text(labelForAccommodationPricePeriod(e)),
                              ),
                          ],
                          onChanged: (v) => setLocal(
                            () => selectedPricePeriod =
                                v ?? AccommodationPricePeriod.night,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: priceController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: _propertyFormDecoration(
                            label: 'Amount (MWK) *',
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: submitting
                                ? null
                                : () async {
                                    String coverUrl;
                                    if (newCover != null) {
                                      coverUrl = await _uploadPropertyPhotoForApi(
                                          newCover!);
                                    } else {
                                      coverUrl = existingCoverUrl;
                                    }
                                    if (coverUrl.trim().isEmpty) {
                                      _toastErr('Please add a cover photo');
                                      return;
                                    }
                                    final name = nameController.text.trim();
                                    final location =
                                        locationController.text.trim();
                                    final price = double.tryParse(
                                      priceController.text.trim(),
                                    );
                                    if (name.isEmpty || location.isEmpty) {
                                      _toastErr(
                                          'Name and location are required');
                                      return;
                                    }
                                    if (price == null || price <= 0) {
                                      _toastErr('Enter a valid amount');
                                      return;
                                    }
                                    setLocal(() => submitting = true);
                                    try {
                                      final galleryUrls =
                                          List<String>.from(keptGalleryUrls);
                                      for (final m in newGallery) {
                                        galleryUrls.add(
                                            await _uploadPropertyPhotoForApi(
                                                m));
                                      }
                                      await _accommodationApi
                                          .updateAccommodation(
                                        id: apiId,
                                        name: name,
                                        location: location,
                                        description: descriptionController.text
                                            .trim(),
                                        pricePerNight: price,
                                        pricingPeriod:
                                            selectedPricePeriod.apiValue,
                                        accommodationType: selectedType,
                                        image: coverUrl,
                                        gallery: galleryUrls,
                                      );
                                      if (!ctx.mounted) return;
                                      Navigator.pop(ctx);
                                      if (_uid.isNotEmpty) {
                                        unawaited(
                                          _firestore
                                              .collection('accommodation_rooms')
                                              .doc('${_uid}_$apiId')
                                              .set(
                                            {
                                              'merchantId': _uid,
                                              'apiAccommodationId': apiId,
                                              'pricingPeriod':
                                                  selectedPricePeriod.apiValue,
                                            },
                                            SetOptions(merge: true),
                                          ),
                                        );
                                      }
                                      final updated =
                                          Map<String, dynamic>.from(room);
                                      updated['name'] = name;
                                      updated['location'] = location;
                                      updated['description'] =
                                          descriptionController.text.trim();
                                      updated['price'] = price;
                                      updated['pricePerNight'] = price;
                                      updated['pricingPeriod'] =
                                          selectedPricePeriod.apiValue;
                                      updated['accommodationType'] =
                                          selectedType;
                                      updated['type'] = selectedType;
                                      updated['image'] = coverUrl;
                                      updated['imageUrl'] = coverUrl;
                                      updated['galleryUrls'] = galleryUrls;
                                      if (mounted) {
                                        setState(() {
                                          final idx = _rooms.indexWhere((r) =>
                                              _apiAccommodationId(
                                                  r as Map<String, dynamic>) ==
                                              apiId);
                                          if (idx >= 0) {
                                            _rooms[idx] = updated;
                                          }
                                        });
                                        _calculateAvailableRooms();
                                      }
                                      _toastOk('Property updated');
                                    } catch (e) {
                                      if (ctx.mounted) {
                                        setLocal(() => submitting = false);
                                      }
                                      final msg = e is ApiException
                                          ? e.message
                                          : 'Failed to update property';
                                      _toastErr(msg);
                                    }
                                  },
                            style: FilledButton.styleFrom(
                              backgroundColor: _brandOrange,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: submitting
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'Save changes',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _loadWalletBalance() async {
    try {
      final walletDoc = await _firestore
          .collection('merchant_wallets')
          .doc(_uid)
          .get();
      
      if (walletDoc.exists && mounted) {
        setState(() {
          _walletBalance = (walletDoc.data()?['balance'] ?? 0).toDouble();
        });
      }
    } catch (e) {
      print('Error loading wallet: $e');
    }
  }

  Future<void> _loadReviews() async {
    try {
      final snapshot = await _firestore
          .collection('accommodation_reviews')
          .where('merchantId', isEqualTo: _uid)
          .orderBy('createdAt', descending: true)
          .limit(5)
          .get();
      
      if (mounted) {
        setState(() {
          _reviews = snapshot.docs.map((doc) => doc.data()).toList();
        });
      }
    } catch (e) {
      print('Error loading reviews: $e');
    }
  }

  Future<void> _calculateAvailableRooms() async {
    try {
      final availableRooms = _rooms.where((room) {
        final roomMap = room as Map<String, dynamic>;
        return roomMap['isAvailable'] == true;
      }).length;
      
      if (mounted) {
        setState(() {
          _availableRooms = availableRooms;
        });
      }
    } catch (e) {
      print('Error calculating available rooms: $e');
    }
  }

  Future<void> _updateBookingStatus(String bookingId, String status) async {
    try {
      await _firestore
          .collection('bookings')
          .doc(bookingId)
          .update({
            'status': status,
            'updatedAt': FieldValue.serverTimestamp(),
          });
      
      _loadMerchantData(showLoading: false);
    } catch (e) {
      print('Error updating booking: $e');
    }
  }

  /// Guest stays booked via the Vero API (`GET /vero/bookings/merchant/me`).
  Future<void> _loadVeroMerchantBookings() async {
    try {
      final list = await _myBookingService.getMerchantIncomingBookings();
      list.sort((a, b) {
        final da = a.bookingDate;
        final db = b.bookingDate;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });
      if (mounted) setState(() => _veroMerchantBookings = list);
    } catch (e) {
      if (mounted) setState(() => _veroMerchantBookings = []);
      print('Vero merchant bookings: $e');
    }
  }

  // ----------------- Wallet PIN helpers -----------------
  Random _safeRandom() {
    try {
      return Random.secure();
    } catch (_) {
      return Random();
    }
  }

  String _randomSalt([int len = 16]) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final r = _safeRandom();
    return List.generate(len, (_) => chars[r.nextInt(chars.length)]).join();
  }

  String _hashPin(String pin, String salt) {
    final bytes = utf8.encode('$pin::$salt');
    return sha256.convert(bytes).toString();
  }

  Future<bool> _ensureAppPinExists() async {
    final sp = await SharedPreferences.getInstance();
    final existingHash = sp.getString('app_pin_hash');
    final existingSalt = sp.getString('app_pin_salt');

    if (existingHash != null &&
        existingHash.trim().isNotEmpty &&
        existingSalt != null &&
        existingSalt.trim().isNotEmpty) {
      return true;
    }

    final pin = await _showSetPinDialog();
    if (pin == null) return false;

    final salt = _randomSalt();
    final hash = _hashPin(pin, salt);

    await sp.setString('app_pin_salt', salt);
    await sp.setString('app_pin_hash', hash);

    if (!mounted) return true;
    _toastOk('Wallet password set');
    return true;
  }

  Future<bool> _unlockWalletWithPin() async {
    if (_walletUnlockedNow) return true;

    final okSetup = await _ensureAppPinExists();
    if (!okSetup) return false;

    final sp = await SharedPreferences.getInstance();
    final salt = (sp.getString('app_pin_salt') ?? '').trim();
    final hash = (sp.getString('app_pin_hash') ?? '').trim();
    if (salt.isEmpty || hash.isEmpty) return false;

    final entered = await _showEnterPinDialog();
    if (entered == null) return false;

    final enteredHash = _hashPin(entered, salt);
    final ok = enteredHash == hash;

    if (!ok) {
      if (!mounted) return false;
      _toastErr('Wrong password');
      return false;
    }

    if (!mounted) return true;
    setState(() {
      _walletUnlockedUntil = DateTime.now().add(_walletUnlockDuration);
    });
    return true;
  }

  Future<String?> _showEnterPinDialog() async {
    final controller = TextEditingController();
    String? shortPinHint;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final kb = MediaQuery.viewInsetsOf(ctx).bottom;
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Material(
                color: Colors.white,
                elevation: 18,
                shadowColor: Colors.black.withValues(alpha: 0.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _walletPinDialogHeader(
                      icon: Icons.account_balance_wallet_rounded,
                      title: 'Unlock wallet',
                      subtitle:
                          'Enter your wallet PIN to view balance and manage payouts.',
                    ),
                    Padding(
                      padding: EdgeInsets.only(bottom: kb),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                              child: Text(
                                'PIN',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.grey.shade700,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                              child: TextField(
                                controller: controller,
                                autofocus: true,
                                obscureText: true,
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                                onChanged: (_) {
                                  if (shortPinHint != null) {
                                    setLocal(() => shortPinHint = null);
                                  }
                                },
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2,
                                ),
                                decoration:
                                    _walletPinFieldDecoration('4–6 digits'),
                              ),
                            ),
                            if (shortPinHint != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    20, 0, 20, 12),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: _brandOrange.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _brandOrange
                                          .withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.info_outline_rounded,
                                        color: _brandNavy
                                            .withValues(alpha: 0.9),
                                        size: 22,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          shortPinHint!,
                                          style: TextStyle(
                                            color: Colors.grey.shade900,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1, thickness: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(null),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                side: BorderSide(color: Colors.grey.shade300),
                              ),
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              onPressed: () {
                                final pin = controller.text.trim();
                                if (pin.length < 4) {
                                  setLocal(() => shortPinHint =
                                      'Enter at least 4 digits to unlock.');
                                  return;
                                }
                                Navigator.of(dialogContext).pop(pin);
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: _brandOrange,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                'Unlock',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<String?> _showSetPinDialog() async {
    final p1 = TextEditingController();
    final p2 = TextEditingController();
    String? err;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final kb = MediaQuery.viewInsetsOf(ctx).bottom;
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Material(
                color: Colors.white,
                elevation: 18,
                shadowColor: Colors.black.withValues(alpha: 0.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _walletPinDialogHeader(
                      icon: Icons.pin_rounded,
                      title: 'Set wallet PIN',
                      subtitle:
                          'Choose a 4–6 digit PIN. You’ll need it to unlock your wallet.',
                    ),
                    Padding(
                      padding: EdgeInsets.only(bottom: kb),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 20, 20, 0),
                              child: Text(
                                'New PIN',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.grey.shade700,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                              child: TextField(
                                controller: p1,
                                autofocus: true,
                                obscureText: true,
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                                onChanged: (_) {
                                  if (err != null) {
                                    setLocal(() => err = null);
                                  }
                                },
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2,
                                ),
                                decoration:
                                    _walletPinFieldDecoration('4–6 digits'),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                              child: Text(
                                'Confirm PIN',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.grey.shade700,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                              child: TextField(
                                controller: p2,
                                obscureText: true,
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                                onChanged: (_) {
                                  if (err != null) {
                                    setLocal(() => err = null);
                                  }
                                },
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2,
                                ),
                                decoration:
                                    _walletPinFieldDecoration('Re-enter PIN'),
                              ),
                            ),
                            if (err != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    20, 0, 20, 8),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFEBEE),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xFFEF9A9A)
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.error_outline_rounded,
                                        color: Color(0xFFC62828),
                                        size: 22,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          err!,
                                          style: const TextStyle(
                                            color: Color(0xFFB71C1C),
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1, thickness: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(null),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                side: BorderSide(color: Colors.grey.shade300),
                              ),
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              onPressed: () {
                                final a = p1.text.trim();
                                final b = p2.text.trim();

                                if (a.length < 4) {
                                  setLocal(() =>
                                      err = 'PIN must be at least 4 digits.');
                                  return;
                                }
                                if (a != b) {
                                  setLocal(() => err = 'PINs do not match.');
                                  return;
                                }
                                Navigator.of(dialogContext).pop(a);
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: _brandOrange,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                'Save PIN',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _compactStatTile({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.black54,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F7),
      appBar: _selectedIndex == 4 ? _buildDashboardAppBar() : null,
      body: _getCurrentPage(),
      bottomNavigationBar: _buildMerchantNavBar(),
    );
  }

  AppBar _buildDashboardAppBar() {
    return AppBar(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.hotel_rounded,
            color: Colors.white,
            size: 22,
          ),
          const SizedBox(width: 8),
          Text(
            _initialLoadComplete ? 'Accommodation Dashboard' : 'Loading…',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ],
      ),
      backgroundColor: _brandOrange,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Tooltip(
            message: 'Post story (24h)',
            child: GestureDetector(
              onTap: () {
                final uid = _auth.currentUser?.uid;
                if (uid == null) {
                  _toastErr('Please sign in to post a story');
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute<bool>(
                    builder: (_) => PostStoryPage(
                      merchantId: uid,
                      merchantName: _businessName.isNotEmpty
                          ? _businessName
                          : (_auth.currentUser?.displayName ?? 'Accommodation'),
                      merchantImageUrl: _merchantProfileUrl.isNotEmpty
                          ? _merchantProfileUrl
                          : null,
                      serviceType: 'accommodation',
                    ),
                  ),
                );
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFF58529),
                          Color(0xFFDD2A7B),
                          Color(0xFF8134AF),
                          Color(0xFF515BD4),
                        ],
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: _merchantProfileUrl.isNotEmpty
                          ? NetworkImage(_merchantProfileUrl)
                          : null,
                      child: _merchantProfileUrl.isNotEmpty
                          ? null
                          : const Icon(
                              Icons.person,
                              size: 18,
                              color: Colors.grey,
                            ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Container(
                        margin: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF25D366),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.add,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: 'Settings',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettingsPage(onBackToHomeTab: () {}),
              ),
            );
          },
        ),
      ],
    );
  }

   Widget _getCurrentPage() {
    switch (_selectedIndex) {
      case 0: // Home (First position)
        return Vero360Homepage(email: widget.email);
      case 1: // Marketplace (Second position)
        return MarketPage(cartService: _cartService);
      case 2: // Cart (Third position)
        return CartPage(cartService: _cartService);
      case 3: // Messages (Fourth position)
        return ChatListPage();
      case 4: // Dashboard (Fifth/last position)
        return _buildDashboardContent();
      default:
        return Vero360Homepage(email: widget.email);
    }
  }

  Widget _buildDashboardContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('Loading accommodation dashboard...'),
          ],
        ),
      );
    }

    // Mirror MarketplaceMerchantDashboard: tabs for dashboard / properties / bookings
    if (_accommodationTabs == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _accommodationTabs!,
            labelColor: _brandOrange,
            unselectedLabelColor: Colors.grey,
            indicatorColor: _brandOrange,
            tabs: const [
              Tab(text: 'Dashboard'),
              Tab(text: 'My properties'),
              Tab(text: 'Bookings'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _accommodationTabs!,
            children: [
              // Dashboard tab
              RefreshIndicator(
                onRefresh: () async => _loadMerchantData(showLoading: false),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildWelcomeSection(),
                      const SizedBox(height: 12),
                      _buildStatsSection(),
                      const SizedBox(height: 12),
                      _buildQuickActions(),
                      const SizedBox(height: 12),
                      _buildWalletSummary(),
                      const SizedBox(height: 12),
                      _buildRecentBookings(compact: true),
                    ],
                  ),
                ),
              ),
              // My properties tab
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: _buildRoomsSection(),
              ),
              // Bookings tab (full booking list + reviews summary)
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildRecentBookings(compact: false),
                    const SizedBox(height: 16),
                    _buildRecentReviews(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ----------------- Profile image helpers -----------------
  ImageProvider? _profileImageProvider() {
    final s = _merchantProfileUrl.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('http')) return NetworkImage(s);
    try {
      final bytes = base64Decode(s);
      return MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  /// Marketplace-style row: grey card + colored circle icon.
  Widget _accommodationPhotoSourceOption({
    required VoidCallback onTap,
    required Color circleColor,
    required IconData icon,
    required String label,
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
                  color: circleColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
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
    );
  }

  /// Opens camera / gallery sheet (same UX as [MarketplaceMerchantDashboard]).
  void _showAccommodationPhotoSourcePicker(
    BuildContext anchorContext, {
    required void Function(ImageSource source) onSource,
  }) {
    showModalBottomSheet<void>(
      context: anchorContext,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _accommodationPhotoSourceOption(
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Future<void>.microtask(() => onSource(ImageSource.camera));
                },
                circleColor: _brandOrange,
                icon: Icons.photo_camera_outlined,
                label: 'Take a photo',
              ),
              _accommodationPhotoSourceOption(
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Future<void>.microtask(() => onSource(ImageSource.gallery));
                },
                circleColor: const Color(0xFF1E88E5),
                icon: Icons.photo_library_outlined,
                label: 'Choose from gallery',
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPhotoSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _accommodationPhotoSourceOption(
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUploadProfile(ImageSource.camera);
                },
                circleColor: _brandOrange,
                icon: Icons.photo_camera_outlined,
                label: 'Take a photo',
              ),
              _accommodationPhotoSourceOption(
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUploadProfile(ImageSource.gallery);
                },
                circleColor: const Color(0xFF1E88E5),
                icon: Icons.photo_library_outlined,
                label: 'Choose from gallery',
              ),
              if (_merchantProfileUrl.trim().isNotEmpty)
                _accommodationPhotoSourceOption(
                  onTap: () {
                    Navigator.pop(context);
                    _removeProfilePhoto();
                  },
                  circleColor: Colors.red,
                  icon: Icons.remove_circle_outline,
                  label: 'Remove current photo',
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _viewProfilePhoto() {
    final img = _profileImageProvider();
    if (img == null) return;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Image(image: img, fit: BoxFit.cover),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: Material(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => Navigator.pop(context),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.close, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Future<String?> _getBearerTokenForApi({bool forceRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && forceRefresh) {
      try {
        final idToken = await user.getIdToken(true);
        final t = idToken?.trim();
        if (t != null && t.isNotEmpty) return t;
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    final fromPrefs = prefs.getString('jwt_token') ??
        prefs.getString('token') ??
        prefs.getString('authToken') ??
        prefs.getString('jwt');
    if (fromPrefs != null && fromPrefs.trim().isNotEmpty) {
      return fromPrefs.trim();
    }
    if (user == null) return null;
    try {
      final idToken = await user.getIdToken(forceRefresh);
      final t = idToken?.trim();
      if (t == null || t.isEmpty) return null;
      return t;
    } catch (_) {
      return null;
    }
  }

  Future<String> _uploadProfileViaBackend(XFile file) async {
    String bearer = await _getBearerTokenForApi(forceRefresh: true) ?? '';
    if (bearer.isEmpty) throw Exception('Not authenticated');
    final uri = ApiConfig.endpoint('/users/me/profile-picture');
    final bytes = await file.readAsBytes();
    final mimeType = lookupMimeType(file.name, headerBytes: bytes) ?? 'image/jpeg';
    final parts = mimeType.split('/');
    final contentType = parts.length == 2 ? MediaType(parts[0], parts[1]) : null;
    Future<http.StreamedResponse> sendRequest(String token) async {
      final req = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: file.name.isNotEmpty ? file.name : 'profile.jpg',
          contentType: contentType,
        ));
      return req.send();
    }
    var sent = await sendRequest(bearer);
    var resp = await http.Response.fromStream(sent);
    if (resp.statusCode == 401) {
      bearer = await _getBearerTokenForApi(forceRefresh: true) ?? '';
      if (bearer.isEmpty) throw Exception('Session expired. Please sign in again.');
      sent = await sendRequest(bearer);
      resp = await http.Response.fromStream(sent);
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      if (resp.statusCode == 404) throw Exception('Profile picture endpoint not found');
      if (resp.statusCode == 401) throw Exception('Session expired. Please sign in again.');
      throw Exception('Upload failed (${resp.statusCode}) ${resp.body}');
    }
    final body = jsonDecode(resp.body);
    final data = (body is Map && body['data'] is Map)
        ? body['data'] as Map
        : (body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{});
    final url = (data['profilepicture'] ?? data['profilePicture'] ?? data['url'])?.toString();
    if (url == null || url.isEmpty) throw Exception('No URL in response');
    return url;
  }

  Future<String> _uploadProfileToFirebaseStorage(String uid, XFile file) async {
    final rawExt = file.name.contains('.') ? file.name.split('.').last : 'jpg';
    final ext = rawExt.isEmpty || rawExt.length > 4 ? 'jpg' : rawExt;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = 'profile_photos/${uid}_$timestamp.$ext';
    final ref = FirebaseStorage.instance.ref().child(path);
    final bytes = await file.readAsBytes();
    final mime = lookupMimeType(file.name, headerBytes: bytes) ?? 'image/jpeg';
    await ref.putData(bytes, SettableMetadata(contentType: mime));
    return await ref.getDownloadURL();
  }

  Future<void> _pickAndUploadProfile(ImageSource src) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final file = await _picker.pickImage(
      source: src,
      maxWidth: 1400,
      imageQuality: 85,
    );
    if (file == null) return;
    try {
      setState(() => _profileUploading = true);
      String url;
      try {
        url = await _uploadProfileViaBackend(file);
      } catch (backendErr) {
        debugPrint('Backend profile upload failed: $backendErr');
        try {
          url = await _uploadProfileToFirebaseStorage(user.uid, file);
        } on FirebaseException catch (e) {
          if ((e.code == 'object-not-found' || e.code == 'unknown') && (e.message?.contains('404') == true)) {
            url = await _uploadProfileViaBackend(file);
          } else {
            rethrow;
          }
        }
      }
      await user.updatePhotoURL(url);
      await user.reload();
      await _firestore.collection('users').doc(user.uid).set({
        'profilePicture': url,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profilepicture', url);
      if (!mounted) return;
      setState(() => _merchantProfileUrl = url);
      ToastHelper.showCustomToast(context, 'Profile picture updated', isSuccess: true, errorMessage: '');
    } on FirebaseException catch (e) {
      debugPrint('Profile upload error: ${e.code} ${e.message}');
      if (!mounted) return;
      try {
        final url = await _uploadProfileViaBackend(file);
        if (url.isNotEmpty) {
          final u = _auth.currentUser;
          if (u != null) {
            await u.updatePhotoURL(url);
            await u.reload();
            await _firestore.collection('users').doc(u.uid).set({
              'profilePicture': url,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('profilepicture', url);
            if (mounted) setState(() => _merchantProfileUrl = url);
            ToastHelper.showCustomToast(context, 'Profile picture updated', isSuccess: true, errorMessage: '');
            return;
          }
        }
      } catch (fallbackErr) {
        debugPrint('Backend fallback failed: $fallbackErr');
      }
      if (e.code == 'object-not-found' || (e.message ?? '').contains('404')) {
        ToastHelper.showCustomToast(context, 'Upload failed. Check network or try again later.', isSuccess: false, errorMessage: '');
      } else {
        ToastHelper.showCustomToast(context, 'Failed to upload photo. Please try again.', isSuccess: false, errorMessage: '');
      }
    } catch (e) {
      debugPrint('Profile upload error: $e');
      if (!mounted) return;
      ToastHelper.showCustomToast(context, 'Failed to upload photo. Please try again.', isSuccess: false, errorMessage: '');
    } finally {
      if (mounted) setState(() => _profileUploading = false);
    }
  }

  Future<void> _removeProfilePhoto() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;
      setState(() => _profileUploading = true);
      await user.updatePhotoURL(null);
      await user.reload();
      await _firestore.collection('users').doc(user.uid).set({
        'profilePicture': '',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profilepicture', '');
      if (!mounted) return;
      setState(() => _merchantProfileUrl = '');
      ToastHelper.showCustomToast(context, 'Profile picture removed', isSuccess: true, errorMessage: '');
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(context, 'Failed to remove photo', isSuccess: false, errorMessage: '');
    } finally {
      if (mounted) setState(() => _profileUploading = false);
    }
  }

  Future<void> _showEditEmailDialog() async {
    final controller = TextEditingController(text: _merchantEmail == 'No Email' ? '' : _merchantEmail);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Update Email'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(hintText: 'Email'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && mounted) {
      try {
        await _firestore.collection('users').doc(_uid).set({
          'email': result,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        setState(() => _merchantEmail = result);
        ToastHelper.showCustomToast(context, 'Email updated', isSuccess: true, errorMessage: '');
      } catch (_) {
        ToastHelper.showCustomToast(context, 'Failed to update email', isSuccess: false, errorMessage: '');
      }
    }
  }

  Future<void> _showEditPhoneDialog() async {
    final controller = TextEditingController(text: _merchantPhone == 'No Phone' ? '' : _merchantPhone);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Update Phone'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(hintText: 'Phone number'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && mounted) {
      try {
        await _firestore.collection('users').doc(_uid).set({
          'phone': result,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        setState(() => _merchantPhone = result.isEmpty ? 'No Phone' : result);
        ToastHelper.showCustomToast(context, 'Phone updated', isSuccess: true, errorMessage: '');
      } catch (_) {
        ToastHelper.showCustomToast(context, 'Failed to update phone', isSuccess: false, errorMessage: '');
      }
    }
  }

  Widget _buildWelcomeSection() {
    final st = _status.trim().toLowerCase();
    final statusText = st.isEmpty ? 'PENDING' : st.toUpperCase();

    Color statusBg;
    Color statusFg;
    if (st == 'approved' || st == 'active') {
      statusBg = const Color(0xFFE7F6EC);
      statusFg = Colors.green.shade700;
    } else if (st == 'pending' || st == 'under_review' || st == 'submitted') {
      statusBg = const Color(0xFFFFF3E5);
      statusFg = const Color(0xFFB86E00);
    } else {
      statusBg = const Color(0xFFFFEDEE);
      statusFg = Colors.red.shade700;
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [_brandNavy, _brandNavy.withOpacity(0.86)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            GestureDetector(
              onTap: _profileImageProvider() != null ? _viewProfilePhoto : null,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white.withOpacity(0.15),
                    backgroundImage: _profileImageProvider(),
                    child: _profileImageProvider() == null
                        ? const Icon(Icons.hotel_rounded, color: Colors.white, size: 26)
                        : null,
                  ),
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: GestureDetector(
                      onTap: _showPhotoSheet,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _brandOrange,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: _profileUploading
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.edit, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _businessName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  GestureDetector(
                    onTap: _showEditEmailDialog,
                    child: Row(
                      children: [
                        Icon(Icons.email_outlined, size: 14, color: Colors.white.withOpacity(0.85)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _merchantEmail,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(Icons.edit, size: 12, color: Colors.white.withOpacity(0.6)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  GestureDetector(
                    onTap: _showEditPhoneDialog,
                    child: Row(
                      children: [
                        Icon(Icons.phone_outlined, size: 14, color: Colors.white.withOpacity(0.85)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _merchantPhone,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(Icons.edit, size: 12, color: Colors.white.withOpacity(0.6)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: statusBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          statusText,
                          style: TextStyle(color: statusFg, fontWeight: FontWeight.w900, fontSize: 12),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade100,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star, size: 14),
                            Text(' ${_rating.toStringAsFixed(1)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsSection() {
    final revFmt = NumberFormat('#,##0', 'en');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
       const Text(
          'Business Overview',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 4,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 74,
          ),
          itemBuilder: (_, i) {
            switch (i) {
              case 0:
                return _compactStatTile(
                  title: 'Total Bookings',
                  value: '${_overviewBookingCount}',
                  icon: Icons.book_online,
                  color: _brandOrange,
                );
              case 1:
                return _compactStatTile(
                  title: 'Total Revenue',
                  value: 'MWK ${revFmt.format(_overviewRevenueMwk.round())}',
                  icon: Icons.attach_money,
                  color: Colors.green,
                );
              case 2:
                return _compactStatTile(
                  title: 'Active Guests',
                  value: '${_overviewActiveGuestsCount}',
                  icon: Icons.people,
                  color: _brandNavy,
                );
              default:
                return _compactStatTile(
                  title: 'Available listings',
                  value: '${_availableRooms}',
                  icon: Icons.bed,
                  color: Colors.orange,
                );
            }
          },
        ),
      ],
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Text(
          'Quick Actions',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: 74,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          children: [
            _QuickActionTile(
             title: 'Add Property',
              icon: Icons.add_business_outlined,
              color: _brandOrange,
              onTap: _showAddPropertySheet,
            ),
            _QuickActionTile(
              title: 'My properties',
              icon: Icons.apartment_outlined,
              color: _brandNavy,
              onTap: () => _accommodationTabs?.animateTo(1),
            ),
            _QuickActionTile(
              title: 'Bookings',
              icon: Icons.book_online_outlined,
              color: Colors.green,
              onTap: () => _accommodationTabs?.animateTo(2),
            ),
       
           
            
            _QuickActionTile(
              title: 'Promotions',
              icon: Icons.campaign_outlined,
              color: Colors.orange,
              onTap: () {
                // Promotions for properties
              },
            ),
        
          ],
        ),
      ],
    );
  }

  Widget _buildWalletSummary() {
    final unlocked = _walletUnlockedNow;
    final balanceStr = unlocked
        ? 'MWK ${_walletBalance.toStringAsFixed(2)}'
        : 'MWK ••••';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (unlocked ? Colors.green : Colors.grey).withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              unlocked
                  ? Icons.account_balance_wallet_rounded
                  : Icons.lock_rounded,
              color: unlocked ? Colors.green : Colors.grey,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Wallet Balance',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  balanceStr,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: unlocked ? Colors.green : Colors.black54,
                  ),
                ),
                if (!unlocked)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Locked — tap Open to unlock',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.black54,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _brandOrange,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () async {
              final ok = await _unlockWalletWithPin();
              if (!ok || !mounted) return;

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MerchantWalletPage(
                    merchantId: _uid,
                    merchantName: _businessName,
                    serviceType: 'accommodation',
                  ),
                ),
              );
            },
            child: const Text(
              'Open',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentBookings({required bool compact}) {
    final veroList = compact
        ? _veroMerchantBookings.take(3).toList()
        : _veroMerchantBookings.toList();
    final fireList =
        compact ? _recentBookings.take(3).toList() : _recentBookings.toList();

    final hasVero = veroList.isNotEmpty;
    final hasFirestore = fireList.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              compact ? 'Recent bookings' : 'Bookings',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (compact && _accommodationTabs != null)
              TextButton(
                onPressed: () => _accommodationTabs!.animateTo(2),
                child: const Text('View all'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (!hasVero && !hasFirestore)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('No bookings yet')),
            ),
          ),
        if (!compact && hasVero && hasFirestore) ...[
          Text(
            'Guest bookings (app)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
        ],
        ...veroList.map(_veroGuestBookingCard),
        if (!compact && hasVero && hasFirestore) ...[
          const SizedBox(height: 16),
          Text(
            'Recorded bookings',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (hasFirestore)
          ...fireList.map((booking) {
            final bookingMap = booking as Map<String, dynamic>;
            final bidRaw = bookingMap['bookingId'] ?? bookingMap['id'] ?? 'N/A';
            final bidStr = bidRaw.toString();
            final shortBid =
                bidStr.length > 8 ? bidStr.substring(0, 8) : bidStr;
            final st = bookingMap['status']?.toString() ?? 'pending';
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: Colors.grey.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: _brandOrange.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.hotel, color: _brandOrange),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Booking #$shortBid',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                    color: Color(0xFF1A1D26),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _getBookingStatusColor(st),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    st,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Actions',
                            icon: Icon(Icons.more_vert, color: Colors.grey.shade700),
                            onPressed: () => _showBookingActions(bookingMap),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _veroBookingInfoLine(
                        Icons.person_outline,
                        'Guest',
                        '${bookingMap['guestName'] ?? 'N/A'}',
                      ),
                      _veroBookingInfoLine(
                        Icons.meeting_room_outlined,
                        'Room',
                        '${bookingMap['roomType'] ?? 'N/A'}',
                      ),
                      _veroBookingInfoLine(
                        Icons.date_range_outlined,
                        'Dates',
                        '${bookingMap['checkIn'] ?? ''} – ${bookingMap['checkOut'] ?? ''}',
                      ),
                      _veroBookingInfoLine(
                        Icons.payments_outlined,
                        'Amount',
                        'MWK ${bookingMap['totalAmount'] ?? '0'}',
                        emphasize: true,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _veroGuestBookingCard(BookingItem b) {
    final name = (b.accommodationName ?? 'Property').trim();
    final loc = (b.accommodationLocation ?? '').trim();
    final dateStr = b.bookingDate != null
        ? DateFormat.yMMMd().format(b.bookingDate!)
        : '—';
    final currency = NumberFormat('#,##0', 'en');
    final statusLabel = _veroBookingStatusLabel(b.status);
    final guestName = (b.guestName ?? '').trim();
    final statusBg = _getBookingStatusColor(_veroStatusKeyForColor(b.status));
    final statusFg = _veroBookingStatusForeground(b.status);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: _brandOrange.withValues(alpha: 0.06),
        elevation: 0,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: _brandOrange.withValues(alpha: 0.55),
            width: 1.5,
          ),
        ),
        child: InkWell(
          onTap: () => _showVeroBookingDetailSheet(b),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _brandOrange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.event_available_rounded,
                        color: _brandOrange,
                        size: 26,
                      ),
                    ),
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
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              height: 1.25,
                              color: Color(0xFF1A1D26),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: statusBg,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.black.withValues(alpha: 0.04),
                                  ),
                                ),
                                child: Text(
                                  statusLabel,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: statusFg,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Delete booking',
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: b.id.isEmpty ? Colors.grey : const Color(0xFFDC2626),
                        size: 24,
                      ),
                      onPressed: b.id.isEmpty
                          ? null
                          : () => _confirmDeleteVeroBooking(b),
                    ),
                  ],
                ),
                if (guestName.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _brandOrange.withValues(alpha: 0.22),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'GUEST',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: _brandOrange.withValues(alpha: 0.85),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          guestName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: Color(0xFF1A1D26),
                          ),
                        ),
                        if ((b.guestEmail ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            b.guestEmail!.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        if ((b.guestPhone ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            b.guestPhone!.trim(),
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (loc.isNotEmpty)
                  _veroBookingInfoLine(
                    Icons.place_outlined,
                    'Location',
                    loc,
                    iconColor: _brandOrange,
                  ),
                _veroBookingInfoLine(
                  Icons.calendar_today_outlined,
                  'Booking date',
                  dateStr,
                  iconColor: _brandOrange,
                ),
                _veroBookingInfoLine(
                  Icons.payments_outlined,
                  'Total',
                  'MWK ${currency.format(b.total.round())}',
                  emphasize: true,
                  iconColor: _brandOrange,
                ),
                const SizedBox(height: 6),
                Text(
                  'Ref · ${b.displayBookingRef}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _brandOrange,
                    letterSpacing: 0.15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _veroBookingStatusForeground(BookingStatus s) {
    switch (s) {
      case BookingStatus.pending:
        return const Color(0xFFB45309);
      case BookingStatus.confirmed:
        return const Color(0xFFC2410C);
      case BookingStatus.cancelled:
        return const Color(0xFFB91C1C);
      case BookingStatus.completed:
        return const Color(0xFF15803D);
      case BookingStatus.unknown:
        return const Color(0xFF475569);
    }
  }

  Widget _veroBookingInfoLine(
    IconData icon,
    String label,
    String value, {
    bool emphasize = false,
    Color? iconColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: iconColor ?? Colors.grey.shade600),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: emphasize ? 15 : 14,
                    fontWeight: emphasize ? FontWeight.w900 : FontWeight.w700,
                    color: emphasize
                        ? const Color(0xFF16284C)
                        : const Color(0xFF334155),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _veroBookingStatusLabel(BookingStatus s) {
    switch (s) {
      case BookingStatus.pending:
        return 'Pending';
      case BookingStatus.confirmed:
        return 'Confirmed';
      case BookingStatus.cancelled:
        return 'Cancelled';
      case BookingStatus.completed:
        return 'Paid';
      case BookingStatus.unknown:
        return 'Unknown';
    }
  }

  /// Maps to strings understood by [_getBookingStatusColor].
  String? _veroStatusKeyForColor(BookingStatus s) {
    switch (s) {
      case BookingStatus.pending:
        return 'pending';
      case BookingStatus.confirmed:
        return 'confirmed';
      case BookingStatus.cancelled:
        return 'cancelled';
      case BookingStatus.completed:
        return 'checked_out';
      case BookingStatus.unknown:
        return null;
    }
  }

  Future<void> _confirmDeleteVeroBooking(
    BookingItem b, {
    VoidCallback? onConfirmedBeforeRequest,
  }) async {
    if (b.id.isEmpty) return;
    final ok = await showBookingDeleteConfirmDialog(
      context,
      bookingId: b.id,
      bookingRefLabel: b.displayBookingRef,
      title: 'Delete booking?',
      body:
          'This permanently removes this guest booking from your dashboard. This cannot be undone.',
    );
    if (ok != true || !mounted) return;
    onConfirmedBeforeRequest?.call();
    try {
      await _myBookingService.deleteBooking(b.id);
      if (mounted) _toastOk('Booking deleted');
      await _loadVeroMerchantBookings();
    } catch (e) {
      if (mounted) _toastErr(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _showVeroBookingDetailSheet(BookingItem b) {
    final currency = NumberFormat('#,##0', 'en');
    final dateStr = b.bookingDate != null
        ? DateFormat.yMMMd().format(b.bookingDate!)
        : '—';
    final guestLines = <String>[
      if ((b.guestName ?? '').trim().isNotEmpty) b.guestName!.trim(),
      if ((b.guestEmail ?? '').trim().isNotEmpty) b.guestEmail!.trim(),
      if ((b.guestPhone ?? '').trim().isNotEmpty) b.guestPhone!.trim(),
    ];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 22,
                      decoration: BoxDecoration(
                        color: _brandOrange,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        (b.accommodationName ?? 'Booking').trim(),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: _brandNavy,
                        ),
                      ),
                    ),
                  ],
                ),
                if ((b.accommodationLocation ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    b.accommodationLocation!.trim(),
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
                const Divider(height: 24),
                if (guestLines.isNotEmpty) ...[
                  Text(
                    'Guest / booker',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...guestLines.map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        line,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 24),
                ],
                _veroDetailRow('Status', _veroBookingStatusLabel(b.status)),
                _veroDetailRow('Booking date', dateStr),
                _veroDetailRow(
                  'Price',
                  'MWK ${currency.format(b.price.round())}',
                ),
                _veroDetailRow(
                  'Booking fee',
                  'MWK ${currency.format(b.bookingFee.round())}',
                ),
                _veroDetailRow(
                  'Total',
                  'MWK ${currency.format(b.total.round())}',
                ),
                _veroDetailRow('Reference', b.displayBookingRef,
                    valueColor: _brandOrange),
                if (b.accommodationId != null)
                  _veroDetailRow('Property ID', '${b.accommodationId}'),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: b.id.isEmpty
                      ? null
                      : () => _confirmDeleteVeroBooking(
                            b,
                            onConfirmedBeforeRequest: () =>
                                Navigator.pop(ctx),
                          ),
                  icon: Icon(Icons.delete_outline, color: Colors.red.shade700),
                  label: Text(
                    'Delete booking',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.red.shade700,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade200),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _veroDetailRow(String k, String v, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              k,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade600,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: valueColor ?? const Color(0xFF334155),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'My properties',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: _showAddPropertySheet,
              child: const Text('Add property'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_rooms.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('No properties yet')),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _rooms.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final room = _rooms[index] as Map<String, dynamic>;
              final rawType = (room['accommodationType'] ?? room['type'] ?? '')
                  .toString()
                  .trim();
              final typeKey =
                  rawType.isEmpty ? 'property' : rawType.toLowerCase();
              final typeTitle = typeKey.isEmpty
                  ? 'Property'
                  : (typeKey[0].toUpperCase() +
                      (typeKey.length > 1 ? typeKey.substring(1) : ''));
              final priceRaw = room['pricePerNight'] ?? room['price'] ?? 0;
              final priceNum = priceRaw is num
                  ? priceRaw.toDouble()
                  : double.tryParse(priceRaw.toString()) ?? 0;
              final listPricePeriod = accommodationPricePeriodFromDynamic(
                room['pricingPeriod'] ?? room['pricePeriod'],
              );
              final apiId = _apiAccommodationId(room);
              final canEditApi = apiId != null;
              final coverUrl = _merchantPropertyCoverUrl(room);
              final desc = (room['description'] ?? '').toString().trim();
              final locationStr = (room['location'] ?? '').toString().trim();
              final name = room['name']?.toString().isNotEmpty == true
                  ? room['name'].toString()
                  : 'Property ${index + 1}';
              final cap = room['capacity'];
       

              return Card(
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 112,
                      height: 124,
                      child: coverUrl.isNotEmpty
                          ? Image.network(
                              coverUrl,
                              fit: BoxFit.cover,
                              width: 112,
                              height: 124,
                              errorBuilder: (_, __, ___) =>
                                  _propertyThumbPlaceholder(),
                            )
                          : _propertyThumbPlaceholder(),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                letterSpacing: -0.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (locationStr.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Icon(
                                      Icons.place_outlined,
                                      size: 15,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      locationStr,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade700,
                                        height: 1.25,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Chip(
                                  label: Text(
                                    typeTitle,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  backgroundColor:
                                      _brandOrange.withValues(alpha: 0.12),
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                Chip(
                                  label: Text(
                                    room['isAvailable'] == true
                                        ? 'Available'
                                        : 'Booked',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: room['isAvailable'] == true
                                          ? Colors.green.shade800
                                          : Colors.red.shade800,
                                    ),
                                  ),
                                  backgroundColor: room['isAvailable'] == true
                                      ? Colors.green[50]
                                      : Colors.red[50],
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'MWK ${_formatMerchantPriceWhole(priceNum)}${listPricePeriod.uiSuffix}',
                              style: TextStyle(
                                color: Colors.green.shade800,
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                              ),
                            ),
                            if (desc.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                desc,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                  height: 1.3,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          
                            if (!canEditApi) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Legacy listing (Firestore only)',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade600,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (canEditApi)
                          IconButton(
                            icon: Icon(
                              Icons.edit_outlined,
                              color: Colors.grey.shade800,
                            ),
                            tooltip: 'Edit property',
                            onPressed: () => _showEditPropertySheet(room),
                          ),
                        if (canEditApi)
                          IconButton(
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              color: Colors.red.shade700,
                            ),
                            tooltip: 'Delete property',
                            onPressed: () => _confirmDeleteProperty(room),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildRecentReviews() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Text(
          'Recent Reviews',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        if (_reviews.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('No reviews yet')),
            ),
          )
        else
          ..._reviews.map((review) {
            final reviewMap = review as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  child: Text(
                    reviewMap['guestName']?.toString().substring(0, 1) ?? 'G',
                  ),
                ),
                title: Row(
                  children: [
                    Text(reviewMap['guestName'] ?? 'Anonymous'),
                    const Spacer(),
                    ...List.generate(5, (index) {
                      return Icon(
                        Icons.star,
                        size: 16,
                        color: index < (reviewMap['rating'] ?? 0) 
                            ? Colors.amber 
                            : Colors.grey[300],
                      );
                    }),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(reviewMap['comment'] ?? ''),
                    const SizedBox(height: 4),
                    Text(
                      'Booking: #${reviewMap['bookingId']?.toString().substring(0, 8) ?? 'N/A'}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

 Widget _buildMerchantNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 72,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(Icons.home_rounded, 'Home', 0),
              _buildNavItem(Icons.storefront_rounded, 'Marketplace', 1),
              _buildNavItem(Icons.shopping_cart_rounded, 'Cart', 2),
              _buildNavItem(Icons.message_rounded, 'Messages', 3),
              _buildNavItem(Icons.dashboard_rounded, 'Dashboard', 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    final bool isSelected = _selectedIndex == index;

    return GestureDetector(
      onTap: () => _onItemTapped(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? _brandOrange.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? _brandOrange : Colors.grey[600],
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? _brandOrange : Colors.grey[600],
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getBookingStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'completed':
      case 'checked_out':
        return Colors.green[100]!;
      case 'checked_in':
        return Colors.blue[100]!;
      case 'confirmed':
        return Colors.orange[100]!;
      case 'pending':
        return Colors.yellow[100]!;
      case 'cancelled':
        return Colors.red[100]!;
      default:
        return Colors.grey[100]!;
    }
  }

  void _showBookingActions(Map<String, dynamic> booking) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.visibility),
                title: const Text('View Details'),
                onTap: () {
                  Navigator.pop(context);
                  // View booking details
                },
              ),
              ListTile(
                leading: const Icon(Icons.check_circle),
                title: const Text('Confirm Booking'),
                onTap: () {
                  Navigator.pop(context);
                  _updateBookingStatus(booking['id'], 'confirmed');
                },
              ),
              ListTile(
                leading: const Icon(Icons.login),
                title: const Text('Check In'),
                onTap: () {
                  Navigator.pop(context);
                  _updateBookingStatus(booking['id'], 'checked_in');
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Check Out'),
                onTap: () {
                  Navigator.pop(context);
                  _updateBookingStatus(booking['id'], 'checked_out');
                },
              ),
              ListTile(
                leading: const Icon(Icons.cancel),
                title: const Text('Cancel Booking'),
                onTap: () {
                  Navigator.pop(context);
                  _updateBookingStatus(booking['id'], 'cancelled');
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

// ----------------- Quick action tile (reuse marketplace style) -----------------
class _QuickActionTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const _QuickActionTile({
    required this.title,
    required this.icon,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 0,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black12),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}