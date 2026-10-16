
import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vero360_app/GernalServices/engagement_notification_service.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/Latest_model.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/MarkeplaceMerchantServices/postlatestArrivalservices.dart';
import 'package:vero360_app/utils/formatters.dart';

import '../../../../utils/toasthelper.dart';
import 'package:vero360_app/widgets/merchant_commission_guide.dart';

class LatestArrivalsCrudPage extends StatefulWidget {
  const LatestArrivalsCrudPage({super.key});
  @override
  State<LatestArrivalsCrudPage> createState() => _LatestArrivalsCrudPageState();
}

class _LatestArrivalsCrudPageState extends State<LatestArrivalsCrudPage>
    with SingleTickerProviderStateMixin {
  final svc = LatestArrivalsServicess();
  late final TabController _tabs;

  // form
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _quantity = TextEditingController();
  bool _submitting = false;
  /// Share to Vero360 Facebook Page after create (default on).
  bool _postToFacebook = true;

  // image
  final _picker = ImagePicker();
  XFile? _picked;
  Uint8List? _pickedBytes;

  // list
  List<LatestArrivalModel> _items = [];
  bool _loading = true;
  bool _busyRow = false;

  // --- Brand (match Airport/Vero Courier) ---
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandSoft = Color(0xFFFFE8CC);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadMine();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _name.dispose();
    _price.dispose();
    _quantity.dispose();
    super.dispose();
  }

  String _shortErr(Object e) {
    final s = e.toString();
    if (s.length <= 200) return s;
    return '${s.substring(0, 200)}...';
  }

  /// Cloud Function [onLatestArrivalFacebookPost] posts this to the Facebook Page.
  Future<void> _queueFacebookLatestArrival({
    required String name,
    required double price,
    required String imageUrl,
    required int quantity,
    int? arrivalId,
  }) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
      await FirebaseFirestore.instance.collection('latest_arrivals').add({
        'name': name.trim(),
        'title': name.trim(),
        'price': price,
        'quantity': quantity,
        'imageUrl': imageUrl.trim(),
        'image': imageUrl.trim(),
        if (arrivalId != null && arrivalId > 0) 'arrivalId': arrivalId,
        if (uid.isNotEmpty) 'merchantId': uid,
        'postToFacebook': true,
        'source': 'merchant_latest_arrival',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LatestArrival] Facebook queue failed: $e');
      }
    }
  }

  Future<void> _loadMine() async {
    setState(() => _loading = true);
    try {
      final data = await svc.fetchMine();
      if (!mounted) return;
      setState(() => _items = data);
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Failed to load: ${_shortErr(e)}',
        isSuccess: false,
        errorMessage: 'Load failed',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // pickers
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

  Future<void> _create() async {
    if (!_form.currentState!.validate()) return;

    if (_pickedBytes == null || _picked == null) {
      ToastHelper.showCustomToast(
        context,
        'Please pick a photo',
        isSuccess: false,
        errorMessage: 'Photo required',
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final filename = _picked!.name.isNotEmpty ? _picked!.name : 'latest.jpg';

      // ✅ Upload image first (NOW hits /vero/uploads)
      final imageUrl = await svc.uploadImageBytes(
        _pickedBytes!,
        filename: filename,
      );

      final priceVal = parseMwkInput(_price.text) ?? 0;
      final qtyVal = int.tryParse(_quantity.text.trim()) ?? 1;

      // ✅ Create latest arrival (NOW hits /vero/latestarrivals)
      final postedName = _name.text.trim();
      final created = await svc.create(
        LatestArrivalModel(
          id: 0,
          image: imageUrl,
          name: postedName,
          price: priceVal,
          createdAt: DateTime.now(),
          quantity: qtyVal,
        ),
      );

      unawaited(
        EngagementNotificationService.instance.notifyNewArrival(
          postedName,
          arrivalId: created.id > 0 ? '${created.id}' : null,
        ),
      );

      // Mirror to Firestore so Cloud Function posts to the Facebook Page.
      if (_postToFacebook) {
        unawaited(_queueFacebookLatestArrival(
          name: postedName,
          price: priceVal,
          imageUrl: imageUrl,
          quantity: qtyVal,
          arrivalId: created.id > 0 ? created.id : null,
        ));
      }

      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        _postToFacebook
            ? 'Latest arrival posted (also sharing to Facebook)'
            : 'Latest arrival posted',
        isSuccess: true,
        errorMessage: 'Created',
        showFacebook: _postToFacebook,
        facebookMessage: _postToFacebook
            ? 'We’ll also share this on the Vero360 Facebook Page.'
            : null,
      );

      _form.currentState!.reset();
      _name.clear();
      _price.clear();
      _quantity.clear();
      _clearPicked();
      _postToFacebook = true;

      await _loadMine();
      if (mounted) _tabs.animateTo(1);
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Create failed: ${_shortErr(e)}',
        isSuccess: false,
        errorMessage: 'Create failed',
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _edit(LatestArrivalModel it) async {
    final nameCtrl = TextEditingController(text: it.name);
    final priceCtrl =
        TextEditingController(text: formatMwkInput(it.price));
    final qtyCtrl = TextEditingController(
      text: it.quantity != null ? '${it.quantity}' : '',
    );
    XFile? picked;
    Uint8List? pickedBytes;
    var saving = false;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            final bottomInset = MediaQuery.of(sheetCtx).viewInsets.bottom;

            Future<void> pick(ImageSource src) async {
              final x = await _picker.pickImage(
                source: src,
                imageQuality: 90,
                maxWidth: 2048,
              );
              if (x == null) return;
              final bytes = await x.readAsBytes();
              setSheet(() {
                picked = x;
                pickedBytes = bytes;
              });
            }

            Future<void> save() async {
              if (saving) return;
              final n = nameCtrl.text.trim();
              final p = parseMwkInput(priceCtrl.text) ?? 0;
              final q = int.tryParse(qtyCtrl.text.trim()) ?? 0;
              if (n.isEmpty || p <= 0 || q <= 0) {
                ToastHelper.showCustomToast(
                  context,
                  'Enter a name, valid price and quantity',
                  isSuccess: false,
                  errorMessage: 'Invalid',
                );
                return;
              }

              setSheet(() => saving = true);
              try {
                final patch = <String, dynamic>{
                  'name': n,
                  'price': p,
                  'quantity': q,
                };
                if (pickedBytes != null && picked != null) {
                  final filename =
                      picked!.name.isNotEmpty ? picked!.name : 'latest.jpg';
                  final imageUrl = await svc.uploadImageBytes(
                    pickedBytes!,
                    filename: filename,
                  );
                  patch['image'] = imageUrl;
                }

                await svc.update(it.id, patch);
                if (sheetCtx.mounted) Navigator.of(sheetCtx).pop(true);
              } catch (e) {
                if (!mounted) return;
                ToastHelper.showCustomToast(
                  context,
                  'Update failed: ${_shortErr(e)}',
                  isSuccess: false,
                  errorMessage: 'Update failed',
                );
                setSheet(() => saving = false);
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 14,
                bottom: 16 + bottomInset,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Edit Latest Arrival',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(sheetCtx).pop(false),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: pickedBytes != null
                            ? Image.memory(pickedBytes!, fit: BoxFit.cover)
                            : _NetworkCover(url: it.image),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: saving
                              ? null
                              : () => pick(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library),
                          label: const Text('Gallery'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed:
                              saving ? null : () => pick(ImageSource.camera),
                          icon: const Icon(Icons.photo_camera),
                          label: const Text('Camera'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      enabled: !saving,
                      decoration: _inputDecoration(label: 'Name'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: priceCtrl,
                      enabled: !saving,
                      keyboardType: TextInputType.number,
                      inputFormatters: [ThousandsSeparatorInputFormatter()],
                      decoration: _inputDecoration(
                        label: 'Price (MWK)',
                        hint: 'e.g. 12,000',
                      ).copyWith(
                        suffixIcon: MerchantCommissionGuide.infoButton(
                          context,
                          priceText: priceCtrl.text,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: qtyCtrl,
                      enabled: !saving,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: _inputDecoration(
                        label: 'Quantity available',
                        hint: 'e.g. 5',
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      style: _filledBtnStyle(),
                      onPressed: saving ? null : save,
                      icon: saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(saving ? 'Saving...' : 'Save changes'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    nameCtrl.dispose();
    priceCtrl.dispose();
    qtyCtrl.dispose();

    if (saved == true && mounted) {
      ToastHelper.showCustomToast(
        context,
        'Latest arrival updated',
        isSuccess: true,
        errorMessage: 'Updated',
      );
      await _loadMine();
    }
  }

  Future<void> _delete(LatestArrivalModel it) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete latest arrival'),
        content: Text('Delete “${it.name}”?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child:
                const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busyRow = true);
    try {
      await svc.delete(it.id);

      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Deleted',
        isSuccess: true,
        errorMessage: 'Deleted',
      );

      _items.removeWhere((e) => e.id == it.id);
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Delete failed: ${_shortErr(e)}',
        isSuccess: false,
        errorMessage: 'Delete failed',
      );
    } finally {
      if (mounted) setState(() => _busyRow = false);
    }
  }

  // ---- UI helpers ----
  InputDecoration _inputDecoration({String? label, String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.black, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: _brandOrange, width: 2),
        borderRadius: BorderRadius.all(Radius.circular(12)),
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          title: const Text('Latest Arrivals'),
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
              Tab(text: 'New Arrival'),
              Tab(text: 'Manage My Arrivals'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: [_buildCreateTab(), _buildManageTab()],
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
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: _brandSoft,
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: _brandOrange.withValues(alpha: 0.35)),
                  ),
                  child: const Text(
                    'Upload a clear product photo and correct price so customers trust your post,Latest arrivals will be available for 24 hours.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Post Latest Arrival',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                _FullBleedPicker(
                  pickedBytes: _pickedBytes,
                  onPickGallery: _pickFromGallery,
                  onPickCamera: _pickFromCamera,
                  onClearPicked: _clearPicked,
                  filledBtnStyle: _filledBtnStyle(padV: 12),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _name,
                  decoration: _inputDecoration(label: 'Name'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Name is required'
                      : null,
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
                  ).copyWith(
                    suffixIcon: MerchantCommissionGuide.infoButton(
                      context,
                      priceText: _price.text,
                    ),
                  ),
                  validator: (v) {
                    final pv = parseMwkInput(v);
                    if (pv == null || pv <= 0) return 'Enter a valid price';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _quantity,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _inputDecoration(
                    label: 'Quantity available',
                    hint: 'How many units you have, e.g. 5',
                  ),
                  validator: (v) {
                    final q = int.tryParse((v ?? '').trim());
                    if (q == null || q <= 0) return 'Enter how many you have';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
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
                    'Share this arrival on the Vero360 Facebook Page.',
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
                        'We’ll also share this latest arrival on the Vero360 Facebook Page to help grow your customers.',
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: _filledBtnStyle(),
                  onPressed: _submitting ? null : _create,
                  icon: _submitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.add),
                  label: Text(
                    _submitting
                        ? 'Posting...'
                        : (_postToFacebook
                            ? 'Post Arrival + Facebook'
                            : 'Post Arrival'),
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
                'No items yet. Post one!',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMine,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final cols = w >= 1200 ? 4 : w >= 800 ? 3 : 2;
          final ratio = w >= 1200 ? 0.92 : w >= 800 ? 0.85 : 0.78;

          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: ratio,
            ),
            itemCount: _items.length,
            itemBuilder: (_, i) {
              final it = _items[i];
              return Card(
                elevation: 6,
                shadowColor: Colors.black12,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _NetworkCover(url: it.image)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                      child: Text(
                        it.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (it.quantity != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                        child: Text(
                          '${it.quantity} available',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 4, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: _brandSoft,
                                borderRadius: BorderRadius.circular(20),
                                border:
                                    Border.all(color: _brandOrange, width: 1),
                              ),
                              child: Text(
                                'MWK ${formatMwkInput(it.price)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 40,
                            ),
                            icon: const Icon(Icons.edit_outlined,
                                color: _brandOrange),
                            onPressed: _busyRow ? null : () => _edit(it),
                            tooltip: 'Edit',
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 40,
                            ),
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red),
                            onPressed: _busyRow ? null : () => _delete(it),
                            tooltip: 'Delete',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/* ---------- picker (full-bleed, bytes preview, web-safe) ---------- */

class _FullBleedPicker extends StatelessWidget {
  const _FullBleedPicker({
    required this.pickedBytes,
    required this.onPickGallery,
    required this.onPickCamera,
    required this.onClearPicked,
    required this.filledBtnStyle,
  });

  final Uint8List? pickedBytes;
  final VoidCallback onPickGallery;
  final VoidCallback onPickCamera;
  final VoidCallback onClearPicked;
  final ButtonStyle filledBtnStyle;

  @override
  Widget build(BuildContext context) {
    final has = pickedBytes != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          elevation: 8,
          shadowColor: Colors.black12,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: has
                ? Image.memory(
                    pickedBytes!,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  )
                : const _PlaceholderCover(),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            FilledButton.icon(
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
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: Colors.grey.shade200),
        Image.network(
          url,
          fit: BoxFit.cover,
          loadingBuilder: (ctx, child, progress) => progress == null
              ? child
              : const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
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
