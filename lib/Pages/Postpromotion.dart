// lib/Pages/promotions_crud_page.dart
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:vero360_app/services/promotion_service.dart';
import '../toasthelper.dart';

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
      _pickedBytes = kIsWeb ? await x.readAsBytes() : null;
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
      _pickedBytes = kIsWeb ? await x.readAsBytes() : null;
      setState(() {});
    }
  }

  void _clearPicked() {
    _picked = null;
    _pickedBytes = null;
    setState(() {});
  }

  Future<void> _create() async {
    if (!_form.currentState!.validate()) return;

    setState(() => _submitting = true);
    try {
      String? imageUrl;
      if (_picked != null && !kIsWeb) {
        imageUrl = await svc.uploadImageFile(File(_picked!.path));
      } else if (_picked != null && kIsWeb) {
        // Optional: implement web upload with MultipartFile.fromBytes
        ToastHelper.showCustomToast(
          context,
          'Web upload not implemented in this snippet',
          isSuccess: false,
          errorMessage: '',
        );
      }

      final price = double.tryParse(_price.text.trim()) ?? 0;

      await svc.createPromo(PromoModel(
        id: 0,
        merchantId: 0, // server stamps from JWT
        serviceProviderId: null, // mapped internally on server
        title: _title.text.trim(),
        description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        price: price,
        image: imageUrl,
        isActive: true,
        freeTrialEndsAt: null,
        subscribedAt: null,
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
                    border: Border.all(color: _brandOrange.withOpacity(0.35)),
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
                      const TextInputType.numberWithOptions(decimal: false),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _inputDecoration(label: 'Price (MK)'),
                  validator: (v) {
                    final pv = double.tryParse(v?.trim() ?? '');
                    if (pv == null || pv < 0) return 'Enter a valid price';
                    return null;
                  },
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
                                'MWK ${((p.price ?? 0).toStringAsFixed(0))}',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),

                            if (p.freeTrialEndsAt != null)
                              Text(
                                'Trial ends: ${p.freeTrialEndsAt}',
                                style: const TextStyle(color: Colors.black54, fontSize: 12),
                              ),
                            if (p.subscribedAt != null)
                              Text(
                                'Subscribed: ${p.subscribedAt}',
                                style: const TextStyle(color: Colors.black54, fontSize: 12),
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
      if (kIsWeb && pickedBytes != null) {
        content = Image.memory(
          pickedBytes!,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        );
      } else {
        content = Image.file(
          File(picked!.path),
          fit: BoxFit.cover,
          gaplessPlayback: true,
        );
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
