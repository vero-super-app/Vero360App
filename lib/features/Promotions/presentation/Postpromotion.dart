// lib/Pages/promotions_crud_page.dart
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:vero360_app/features/Promotions/promotion_service.dart';
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

  // image
  final _picker = ImagePicker();
  XFile? _picked;
  Uint8List? _pickedBytes;

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
        'Failed to load promos: $e',
        isSuccess: false,
        errorMessage: 'Load failed',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // image pickers
  Future<void> _pickFromGallery() async {
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: 2048,
    );
    if (x != null) {
      _picked = x;
      _pickedBytes = await x.readAsBytes();
      setState(() {});
    }
  }

  Future<void> _pickFromCamera() async {
    final x = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
      maxWidth: 2048,
    );
    if (x != null) {
      _picked = x;
      _pickedBytes = await x.readAsBytes();
      setState(() {});
    }
  }

  void _clearPicked() {
    _picked = null;
    _pickedBytes = null;
    setState(() {});
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
        : (_endDate ?? _startDate?.add(const Duration(days: 7)) ?? now);

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

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: _brandOrange),
        ),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;

    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && !_endDate!.isAfter(_startDate!)) {
          _endDate = _startDate!.add(const Duration(hours: 1));
        }
      } else {
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
    if (!_endDate!.isAfter(_startDate!)) {
      ToastHelper.showCustomToast(
        context,
        'End date must be after the start date.',
        isSuccess: false,
        errorMessage: 'Invalid dates',
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      String? imageUrl;
      if (_pickedBytes != null && _picked != null) {
        final filename =
            _picked!.name.isNotEmpty ? _picked!.name : 'promo.jpg';
        imageUrl = await svc.uploadImageBytes(
          _pickedBytes!,
          filename: filename,
        );
      }

      final priceRaw = _price.text.trim();
      final price = double.tryParse(priceRaw);
      if (price == null || price <= 0) {
        ToastHelper.showCustomToast(
          context,
          'Enter a valid promotion price greater than zero.',
          isSuccess: false,
          errorMessage: 'Price required',
        );
        setState(() => _submitting = false);
        return;
      }

      await svc.createPromo(PromoModel(
        id: 0,
        merchantId: 0,
        serviceProviderId: null,
        title: _title.text.trim(),
        description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        price: price,
        image: imageUrl,
        isActive: true,
        startsAt: _startDate,
        endsAt: _endDate,
        createdAt: DateTime.now(),
      ));

      ToastHelper.showCustomToast(
        context,
        'Promotion posted',
        isSuccess: true,
        errorMessage: 'Created',
      );

      _form.currentState!.reset();
      _title.clear();
      _desc.clear();
      _price.clear();
      _startDate = null;
      _endDate = null;
      _picked = null;
      _pickedBytes = null;
      setState(() {});
      await _loadMine();
      _tabs.animateTo(1);
    } catch (e) {
      ToastHelper.showCustomToast(
        context,
        'Create failed: $e',
        isSuccess: false,
        errorMessage: 'Create failed',
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _subscribe(PromoModel p) async {
    final controller =
        TextEditingController(text: (p.price ?? 0).toStringAsFixed(0));
    final amount = await showDialog<double?>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Subscribe / Extend'),
        content: TextField(
          controller: controller,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: false),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Amount (MWK)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(context, double.tryParse(controller.text)),
              child: const Text('Pay')),
        ],
      ),
    );
    if (amount == null) return;

    setState(() => _busyRow = true);
    try {
      await svc.subscribe(p.id, amount);
      ToastHelper.showCustomToast(
          context, 'Subscribed', isSuccess: true, errorMessage: 'Subscribed');
      await _loadMine();
    } catch (e) {
      ToastHelper.showCustomToast(
          context, 'Subscribe failed: $e', isSuccess: false, errorMessage: 'Subscribe failed');
    } finally {
      if (mounted) setState(() => _busyRow = false);
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
          context, 'Deactivate failed: $e', isSuccess: false, errorMessage: 'Deactivate failed');
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
          context, 'Delete failed: $e', isSuccess: false, errorMessage: 'Delete failed');
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

                _FullBleedPicker(
                  picked: _picked,
                  pickedBytes: _pickedBytes,
                  onPickGallery: _pickFromGallery,
                  onPickCamera: _pickFromCamera,
                  onClearPicked: _clearPicked,
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
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}'),
                    ),
                  ],
                  decoration: _inputDecoration(
                    label: 'Price (MWK) *',
                    hint: 'e.g. 100000 or 19.99',
                  ),
                  validator: (v) {
                    final raw = v?.trim() ?? '';
                    if (raw.isEmpty) return 'Price is required';
                    final pv = double.tryParse(raw);
                    if (pv == null || pv <= 0) {
                      return 'Enter price';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                const Text(
                  'Promotion period',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
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
                  label: const Text('Post Promotion'),
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

                            if (p.subscribedAt != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  'Subscribed: ${PromoDateFormat.dayMonthYearTime(p.subscribedAt!)}',
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 10),

                            Wrap(
                              spacing: 8,
                              children: [
                                FilledButton.tonalIcon(
                                  onPressed: _busyRow ? null : () => _subscribe(p),
                                  icon: const Icon(Icons.payment),
                                  label: const Text('Subscribe'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _busyRow ? null : () => _deactivate(p),
                                  icon: const Icon(Icons.pause_circle_outline),
                                  label: const Text('Deactivate'),
                                ),
                                TextButton.icon(
                                  onPressed: _busyRow ? null : () => _delete(p),
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  label: const Text('Delete', style: TextStyle(color: Colors.red)),
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
