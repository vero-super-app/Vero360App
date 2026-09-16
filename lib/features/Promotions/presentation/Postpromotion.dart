// lib/Pages/promotions_crud_page.dart
import 'dart:async';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:vero360_app/GernalServices/engagement_notification_service.dart';
import 'package:vero360_app/features/Promotions/promotion_service.dart';
import 'package:vero360_app/utils/formatters.dart';
import 'package:vero360_app/utils/description_contact_mask.dart';
import 'package:vero360_app/utils/user_facing_error.dart';
import '../../../utils/toasthelper.dart';

class PromotionsCrudPage extends StatefulWidget {
  const PromotionsCrudPage({super.key});
  @override
  State<PromotionsCrudPage> createState() => _PromotionsCrudPageState();
}

class _PromotionsCrudPageState extends State<PromotionsCrudPage>
    with SingleTickerProviderStateMixin {
  final svc = PromoService();
  late final TabController _tabs;

  // form
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _price = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  bool _submitting = false;
  /// Share to Vero360 Facebook Page after create (Cloud Function).
  bool _postToFacebook = true;

  // images (up to 4 photos per promotion)
  static const int _maxPromoPhotos = 4;
  final _picker = ImagePicker();
  final List<_PickedPromoImage> _pickedImages = [];

  // list
  List<PromoModel> _items = [];
  bool _loading = true;
  bool _busyRow = false;

  // --- Brand (match Airport/Vero Courier) ---
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandSoft   = Color(0xFFFFE8CC);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadMine();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _title.dispose();
    _desc.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _loadMine() async {
    setState(() => _loading = true);
    try {
      final data = await svc.fetchMyPromos();
      if (!mounted) return;
      setState(() => _items = data);
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        UserFacingError.from(e, fallback: 'Failed to load promos'),
        isSuccess: false,
        errorMessage: 'Load failed',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Cloud Function posts this to the Facebook Page.
  Future<void> _queueFacebookPromo(
    PromoModel p, {
    required String reason,
    List<String> uploadedUrls = const [],
  }) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
      final resolved = <String>[
        ...uploadedUrls.map((e) => e.trim()).where((e) => e.isNotEmpty),
        ...(p.resolvedImageUrls),
      ];
      final seen = <String>{};
      final gallery = <String>[];
      for (final u in resolved) {
        if (seen.add(u)) gallery.add(u);
      }
      final image = gallery.isNotEmpty ? gallery.first : '';
      await FirebaseFirestore.instance.collection('merchant_promotions').add({
        'promoId': p.id,
        'title': p.title.trim(),
        'name': p.title.trim(),
        'description': (p.description ?? '').trim(),
        'price': p.price,
        if (image.isNotEmpty) ...{
          'imageUrl': image,
          'image': image,
        },
        if (gallery.length > 1) 'gallery': gallery.sublist(1),
        if (gallery.isNotEmpty) 'galleryUrls': gallery,
        if (p.startsAt != null) 'startsAt': p.startsAt!.toIso8601String(),
        if (p.endsAt != null) 'endsAt': p.endsAt!.toIso8601String(),
        if (uid.isNotEmpty) 'merchantId': uid,
        'postToFacebook': true,
        'source': reason,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[Promo] Facebook queue failed: $e');
    }
  }

  Future<void> _pickFromGallery() async {
    if (_pickedImages.length >= _maxPromoPhotos) {
      ToastHelper.showCustomToast(
        context,
        'You can add up to $_maxPromoPhotos photos per promotion.',
        isSuccess: false,
        errorMessage: 'Photo limit',
      );
      return;
    }
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: 2048,
    );
    if (x != null) await _addPicked(x);
  }

  Future<void> _pickFromCamera() async {
    if (_pickedImages.length >= _maxPromoPhotos) {
      ToastHelper.showCustomToast(
        context,
        'You can add up to $_maxPromoPhotos photos per promotion.',
        isSuccess: false,
        errorMessage: 'Photo limit',
      );
      return;
    }
    final x = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
      maxWidth: 2048,
    );
    if (x != null) await _addPicked(x);
  }

  Future<void> _addPicked(XFile x) async {
    final bytes = await x.readAsBytes();
    if (!mounted) return;
    setState(() {
      _pickedImages.add(_PickedPromoImage(file: x, bytes: bytes));
    });
  }

  void _removePickedAt(int index) {
    if (index < 0 || index >= _pickedImages.length) return;
    setState(() => _pickedImages.removeAt(index));
  }

  void _clearPicked() {
    setState(() => _pickedImages.clear());
  }

  String _formatPickedDateTime(DateTime? dt) {
    if (dt == null) return 'Tap to select';
    return PromoDateFormat.dayMonthYearTime(dt);
  }

  Future<void> _pickDateTime({
    required bool isStart,
  }) async {
    final now = DateTime.now();
    final initial = isStart
        ? (_startDate ?? now)
        : (_endDate ??
            (_startDate != null
                ? DateTime(
                    _startDate!.year,
                    _startDate!.month,
                    _startDate!.day,
                    23,
                    59,
                  )
                : now));

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: _brandOrange),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;

    // Same-day promotions: default end time to 23:59 when end date matches start day.
    final sameDayAsStart = !isStart &&
        _startDate != null &&
        date.year == _startDate!.year &&
        date.month == _startDate!.month &&
        date.day == _startDate!.day;
    final initialTime = sameDayAsStart
        ? const TimeOfDay(hour: 23, minute: 59)
        : TimeOfDay.fromDateTime(initial);

    final time = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: _brandOrange),
        ),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;

    var picked = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    setState(() {
      if (isStart) {
        _startDate = picked;
        // Keep a valid single-day window if end was same day / earlier.
        if (_endDate != null && !_endDate!.isAfter(_startDate!)) {
          _endDate = DateTime(
            _startDate!.year,
            _startDate!.month,
            _startDate!.day,
            23,
            59,
          );
          if (!_endDate!.isAfter(_startDate!)) {
            _endDate = _startDate!.add(const Duration(minutes: 30));
          }
        }
      } else {
        if (_startDate != null && !picked.isAfter(_startDate!)) {
          // Allow one-day promos: bump to end of selected day when needed.
          picked = DateTime(date.year, date.month, date.day, 23, 59);
          if (!picked.isAfter(_startDate!)) {
            picked = _startDate!.add(const Duration(minutes: 30));
          }
        }
        _endDate = picked;
      }
    });
  }

  Future<void> _create() async {
    if (!_form.currentState!.validate()) return;
    if (_startDate == null || _endDate == null) {
      ToastHelper.showCustomToast(
        context,
        'Please set promotion start and end dates.',
        isSuccess: false,
        errorMessage: 'Dates required',
      );
      return;
    }
    if (_endDate!.isBefore(_startDate!)) {
      ToastHelper.showCustomToast(
        context,
        'End date must be on or after the start date.',
        isSuccess: false,
        errorMessage: 'Invalid dates',
      );
      return;
    }
    // Same-day / same-moment: keep a valid window ending later the same day.
    if (!_endDate!.isAfter(_startDate!)) {
      _endDate = DateTime(
        _startDate!.year,
        _startDate!.month,
        _startDate!.day,
        23,
        59,
      );
      if (!_endDate!.isAfter(_startDate!)) {
        _endDate = _startDate!.add(const Duration(minutes: 30));
      }
    }

    setState(() => _submitting = true);
    try {
      final uploadedUrls = <String>[];
      for (final pick in _pickedImages) {
        final filename =
            pick.file.name.isNotEmpty ? pick.file.name : 'promo.jpg';
        final url = await svc.uploadImageBytes(
          pick.bytes,
          filename: filename,
        );
        if (url.trim().isNotEmpty) uploadedUrls.add(url.trim());
      }

      final price = parseMwkInput(_price.text);
      if (price == null || price <= 0) {
        ToastHelper.showCustomToast(
          context,
          'Enter a valid price (MWK).',
          isSuccess: false,
          errorMessage: 'Price required',
        );
        setState(() => _submitting = false);
        return;
      }

      final created = await svc.createPromo(PromoModel(
        id: 0,
        merchantId: 0,
        serviceProviderId: null,
        title: _title.text.trim(),
        description: _desc.text.trim().isEmpty
            ? null
            : DescriptionContactMask.mask(_desc.text.trim()),
        price: price,
        image: uploadedUrls.isNotEmpty ? uploadedUrls.first : null,
        gallery: uploadedUrls.length > 1 ? uploadedUrls.sublist(1) : const [],
        isActive: true,
        startsAt: _startDate,
        endsAt: _endDate,
        createdAt: DateTime.now(),
      ));

      final postedTitle = created.title.trim().isNotEmpty
          ? created.title.trim()
          : _title.text.trim();
      unawaited(
        EngagementNotificationService.instance.notifyNewPromotion(
          postedTitle,
          promoId: created.id > 0 ? created.id : null,
        ),
      );
      if (_postToFacebook) {
        // Prefer freshly uploaded URLs so the CF always has a photo to share.
        final forFacebook = PromoModel(
          id: created.id,
          merchantId: created.merchantId,
          serviceProviderId: created.serviceProviderId,
          title: postedTitle,
          description: created.description ??
              (_desc.text.trim().isEmpty ? null : _desc.text.trim()),
          price: created.price ?? price,
          image: uploadedUrls.isNotEmpty
              ? uploadedUrls.first
              : created.image,
          gallery: uploadedUrls.length > 1
              ? uploadedUrls.sublist(1)
              : created.gallery,
          isActive: true,
          startsAt: created.startsAt ?? _startDate,
          endsAt: created.endsAt ?? _endDate,
          createdAt: created.createdAt,
        );
        unawaited(
          _queueFacebookPromo(
            forFacebook,
            reason: 'create',
            uploadedUrls: uploadedUrls,
          ),
        );
      }

      ToastHelper.showCustomToast(
        context,
        _postToFacebook
            ? 'Promotion posted (also sharing to Facebook)'
            : 'Promotion posted',
        isSuccess: true,
        errorMessage: 'Created',
      );

      _form.currentState!.reset();
      _title.clear();
      _desc.clear();
      _price.clear();
      _startDate = null;
      _endDate = null;
      _pickedImages.clear();
      _postToFacebook = true;
      setState(() {});
      await _loadMine();
      _tabs.animateTo(1);
    } catch (e) {
      ToastHelper.showCustomToast(
        context,
        UserFacingError.from(e, fallback: 'Create failed'),
        isSuccess: false,
        errorMessage: 'Create failed',
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _deactivate(PromoModel p) async {
    setState(() => _busyRow = true);
    try {
      await svc.deactivate(p.id);
      ToastHelper.showCustomToast(
          context, 'Deactivated', isSuccess: true, errorMessage: 'Deactivated');
      await _loadMine();
    } catch (e) {
      ToastHelper.showCustomToast(
          context,
          UserFacingError.from(e, fallback: 'Deactivate failed'),
          isSuccess: false,
          errorMessage: 'Deactivate failed');
    } finally {
      if (mounted) setState(() => _busyRow = false);
    }
  }

  Future<void> _activate(PromoModel p) async {
    setState(() => _busyRow = true);
    try {
      await svc.activate(p.id, endsAt: p.endsAt, startsAt: p.startsAt);
      unawaited(_queueFacebookPromo(p, reason: 'activate'));
      ToastHelper.showCustomToast(
          context, 'Activated', isSuccess: true, errorMessage: 'Activated');
      await _loadMine();
    } catch (e) {
      ToastHelper.showCustomToast(
          context,
          UserFacingError.from(e, fallback: 'Activate failed'),
          isSuccess: false,
          errorMessage: 'Activate failed');
    } finally {
      if (mounted) setState(() => _busyRow = false);
    }
  }

  Future<void> _delete(PromoModel p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete promotion'),
        content: Text('Delete “${p.title}”?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child:
                  const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busyRow = true);
    try {
      await svc.deletePromo(p.id);
      ToastHelper.showCustomToast(
          context, 'Deleted', isSuccess: true, errorMessage: 'Deleted');
      _items.removeWhere((e) => e.id == p.id);
      setState(() {});
    } catch (e) {
      ToastHelper.showCustomToast(
          context,
          UserFacingError.from(e, fallback: 'Delete failed'),
          isSuccess: false,
          errorMessage: 'Delete failed');
    } finally {
      if (mounted) setState(() => _busyRow = false);
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
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: _brandOrange, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  ButtonStyle _filledBtnStyle({double padV = 14}) => FilledButton.styleFrom(
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: EdgeInsets.symmetric(vertical: padV, horizontal: 14),
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
          title: const Text('Promotions'),
          backgroundColor: _brandOrange,
          foregroundColor: Colors.white,
          elevation: 0,
          bottom: TabBar(
            controller: _tabs,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: const [
              Tab(text: 'New Promotion'),
              Tab(text: 'Manage My Promotions'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: [
            _buildCreateTab(),
            _buildManageTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Card(
        elevation: 8,
        shadowColor: Colors.black12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Mini banner for consistency
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: _brandSoft,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _brandOrange.withValues(alpha: 0.35)),
                  ),
                  child: const Text(
                    'Clear image, catchy title and correct price drive more clicks.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 14),

                const Text('Post Promotion',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),

                _MultiPromoImagePicker(
                  images: _pickedImages,
                  maxPhotos: _maxPromoPhotos,
                  onPickGallery: _pickFromGallery,
                  onPickCamera: _pickFromCamera,
                  onRemoveAt: _removePickedAt,
                  onClearAll: _clearPicked,
                  filledBtnStyle: _filledBtnStyle(padV: 12),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _title,
                  decoration: _inputDecoration(label: 'Title'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Title is required' : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _desc,
                  minLines: 2,
                  maxLines: 4,
                  decoration: _inputDecoration(label: 'Description (optional)'),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _price,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: false),
                  inputFormatters: [ThousandsSeparatorInputFormatter()],
                  decoration: _inputDecoration(
                    label: 'Price (MWK)',
                    hint: 'e.g. 12,000',
                  ),
                  validator: (v) {
                    final pv = parseMwkInput(v);
                    if (pv == null || pv <= 0) {
                      return 'Enter a valid price';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                const Text(
                  'Promotion period',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  'Same-day promotions are allowed (end defaults to 11:59 PM).',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                _DateTimePickerTile(
                  label: 'Start date & time',
                  value: _formatPickedDateTime(_startDate),
                  onTap: () => _pickDateTime(isStart: true),
                ),
                const SizedBox(height: 8),
                _DateTimePickerTile(
                  label: 'End date & time',
                  value: _formatPickedDateTime(_endDate),
                  onTap: () => _pickDateTime(isStart: false),
                ),
                const SizedBox(height: 14),

                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _postToFacebook,
                  activeThumbColor: _brandOrange,
                  secondary: const FacebookLogoMark(size: 22),
                  title: const Text(
                    'Also post on Facebook',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  subtitle: Text(
                    'Share this promotion on the Vero360 Facebook Page.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  onChanged: _submitting
                      ? null
                      : (v) => setState(() => _postToFacebook = v),
                ),
                if (_postToFacebook) ...[
                  const SizedBox(height: 8),
                  const FacebookShareHint(
                    message:
                        'We’ll also share this promotion on the Vero360 Facebook Page to help grow your customers.',
                  ),
                ],
                const SizedBox(height: 16),

                FilledButton.icon(
                  style: _filledBtnStyle(),
                  onPressed: _submitting ? null : _create,
                  icon: _submitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.campaign),
                  label: Text(
                    _postToFacebook
                        ? 'Post Promotion + Facebook'
                        : 'Post Promotion',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildManageTab() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadMine,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Center(
              child: Text(
                'No promotions yet. Post one!',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMine,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final p = _items[i];
          return Card(
            elevation: 6,
            shadowColor: Colors.black12,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Full-bleed cover with consistent ratio
                if ((p.image ?? '').isNotEmpty)
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(14),
                      topRight: Radius.circular(14),
                    ),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: _NetworkCover(url: p.image!),
                    ),
                  )
                else
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(14),
                      topRight: Radius.circular(14),
                    ),
                    child: const AspectRatio(
                      aspectRatio: 16 / 9,
                      child: _PlaceholderCover(),
                    ),
                  ),

                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.local_offer, size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                child: Text(
                                  p.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              _StatusChip(active: p.isActive),
                            ]),
                            const SizedBox(height: 6),
                            if ((p.description ?? '').isNotEmpty)
                              Text(
                                p.description!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            const SizedBox(height: 6),

                            // Orange price pill (consistent with other screens)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: _brandSoft,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: _brandOrange, width: 1),
                              ),
                              child: Text(
                                p.formattedPrice,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),

                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF7F8FA),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.black12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.formattedPromoPeriodRange,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Starts on ${p.formattedPromoStart}',
                                    style: const TextStyle(
                                      color: Colors.black54,
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (p.promoEnd != null)
                                    Text(
                                      'Ends on ${p.formattedPromoEnd}',
                                      style: const TextStyle(
                                        color: Colors.black54,
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 10),

                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (p.isActive)
                                  OutlinedButton.icon(
                                    onPressed: _busyRow
                                        ? null
                                        : () => _deactivate(p),
                                    icon: const Icon(
                                        Icons.pause_circle_outline),
                                    label: const Text('Deactivate'),
                                  )
                                else
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: _brandOrange,
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed:
                                        _busyRow ? null : () => _activate(p),
                                    icon: const Icon(
                                        Icons.play_circle_outline),
                                    label: const Text('Activate'),
                                  ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    side: const BorderSide(color: Colors.red),
                                  ),
                                  onPressed:
                                      _busyRow ? null : () => _delete(p),
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('Delete'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/* ---------- helper widgets: full-bleed, no empty space ---------- */

class _PickedPromoImage {
  final XFile file;
  final Uint8List bytes;
  const _PickedPromoImage({required this.file, required this.bytes});
}

class _MultiPromoImagePicker extends StatelessWidget {
  const _MultiPromoImagePicker({
    required this.images,
    required this.maxPhotos,
    required this.onPickGallery,
    required this.onPickCamera,
    required this.onRemoveAt,
    required this.onClearAll,
    required this.filledBtnStyle,
  });

  final List<_PickedPromoImage> images;
  final int maxPhotos;
  final VoidCallback onPickGallery;
  final VoidCallback onPickCamera;
  final void Function(int index) onRemoveAt;
  final VoidCallback onClearAll;
  final ButtonStyle filledBtnStyle;

  @override
  Widget build(BuildContext context) {
    final canAdd = images.length < maxPhotos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (images.isEmpty)
          Card(
            elevation: 8,
            shadowColor: Colors.black12,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: const AspectRatio(
              aspectRatio: 16 / 9,
              child: _PlaceholderCover(),
            ),
          )
        else
          SizedBox(
            height: 168,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final pick = images[index];
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        width: 220,
                        height: 168,
                        child: Image.memory(
                          pick.bytes,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Material(
                        color: Colors.black54,
                        shape: const CircleBorder(),
                        child: InkWell(
                          onTap: () => onRemoveAt(index),
                          customBorder: const CircleBorder(),
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(Icons.close, color: Colors.white, size: 18),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        const SizedBox(height: 8),
        Text(
          '${images.length}/$maxPhotos photos',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            FilledButton.tonalIcon(
              style: filledBtnStyle,
              onPressed: canAdd ? onPickGallery : null,
              icon: const Icon(Icons.photo_library),
              label: const Text('Gallery'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: canAdd ? onPickCamera : null,
              icon: const Icon(Icons.photo_camera),
              label: const Text('Camera'),
            ),
            const Spacer(),
            if (images.isNotEmpty)
              TextButton.icon(
                onPressed: onClearAll,
                icon: const Icon(Icons.close),
                label: const Text('Clear all'),
              ),
          ],
        ),
      ],
    );
  }
}

class _DateTimePickerTile extends StatelessWidget {
  const _DateTimePickerTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black),
          ),
          child: Row(
            children: [
              const Icon(Icons.event_rounded, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: value == 'Tap to select'
                            ? Colors.black38
                            : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.black45),
            ],
          ),
        ),
      ),
    );
  }
}

class _FullBleedPicker extends StatelessWidget {
  const _FullBleedPicker({
    required this.picked,
    required this.pickedBytes,
    required this.onPickGallery,
    required this.onPickCamera,
    required this.onClearPicked,
    required this.filledBtnStyle,
  });

  final XFile? picked;
  final Uint8List? pickedBytes;
  final VoidCallback onPickGallery;
  final VoidCallback onPickCamera;
  final VoidCallback onClearPicked;
  final ButtonStyle filledBtnStyle;

  @override
  Widget build(BuildContext context) {
    final has = picked != null;

    Widget content;
    if (has) {
      // Always cover into a fixed aspect, no letterboxing
      if (pickedBytes != null) {
        content = Image.memory(
          pickedBytes!,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        );
      } else if (!kIsWeb) {
        content = Image.file(
          File(picked!.path),
          fit: BoxFit.cover,
          gaplessPlayback: true,
        );
      } else {
        content = const _PlaceholderCover();
      }
    } else {
      content = const _PlaceholderCover();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          elevation: 8,
          shadowColor: Colors.black12,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: AspectRatio(
            aspectRatio: 16 / 9, // consistent, modern card ratio
            child: content,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            FilledButton.tonalIcon(
              style: filledBtnStyle,
              onPressed: onPickGallery,
              icon: const Icon(Icons.photo_library),
              label: const Text('Gallery'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onPickCamera,
              icon: const Icon(Icons.photo_camera),
              label: const Text('Camera'),
            ),
            const Spacer(),
            if (has)
              TextButton.icon(
                onPressed: onClearPicked,
                icon: const Icon(Icons.close),
                label: const Text('Clear'),
              ),
          ],
        ),
      ],
    );
  }
}

class _NetworkCover extends StatelessWidget {
  const _NetworkCover({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    // Stacks a background color to avoid white flash, then the image
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: Colors.grey.shade200),
        Image.network(
          url,
          fit: BoxFit.cover, // crop if needed
          loadingBuilder: (ctx, child, progress) {
            if (progress == null) return child;
            return const _ShimmerishLoader();
          },
          errorBuilder: (_, __, ___) => const _PlaceholderCover(),
        ),
      ],
    );
  }
}

class _PlaceholderCover extends StatelessWidget {
  const _PlaceholderCover();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEDEDED),
      child: const Center(
        child: Icon(Icons.image_not_supported_outlined, color: Colors.black38),
      ),
    );
  }
}

class _ShimmerishLoader extends StatelessWidget {
  const _ShimmerishLoader();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.shade200,
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFE7F6EC) : const Color(0xFFFFF3E5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        active ? 'ACTIVE' : 'INACTIVE',
        style: TextStyle(
          color: active ? Colors.green.shade700 : const Color(0xFFB86E00),
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
