// lib/Pages/service_provider_crud_page.dart
import 'dart:typed_data';
import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:vero360_app/models/serviceprovider_model.dart';
import 'package:vero360_app/services/api_config.dart';
import 'package:vero360_app/services/serviceprovider_service.dart';

import 'package:vero360_app/toasthelper.dart';

class ServiceProviderCrudPage extends StatefulWidget {
  const ServiceProviderCrudPage({super.key});
  @override
  State<ServiceProviderCrudPage> createState() => _ServiceProviderCrudPageState();
}

class _ServiceProviderCrudPageState extends State<ServiceProviderCrudPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _status = TextEditingController(text: 'open');

  TimeOfDay? _openTime;
  TimeOfDay? _closeTime;

  final _picker = ImagePicker();
  XFile? _picked;
  Uint8List? _pickedBytes;

  ServiceProvider? _myService; // only one allowed
  bool _loading = true;
  bool _saving = false;
  bool _deleting = false;

  // --- Brand (match Airport/Vero Courier) ---
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandSoft   = Color(0xFFFFE8CC);
  static const Color kActionGreen = Color(0xFF11A661); // kept (not used) to avoid logic churn

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
    _desc.dispose();
    _status.dispose();
    super.dispose();
  }

  Future<void> _loadMine() async {
    setState(() => _loading = true);
    try {
      final mine = await ServiceProviderServicess.fetchMine();
      _myService = mine;
      if (mine != null) {
        _name.text = mine.businessName;
        _desc.text = mine.businessDescription ?? '';
        _status.text = (mine.status ?? '').isNotEmpty ? mine.status! : 'open';

        final s = mine.openingHours ?? '';
        final parts = s.split('–');
        if (parts.length == 2) {
          TimeOfDay? parse(String x) {
            final t = x.trim().split(':');
            if (t.length != 2) return null;
            final h = int.tryParse(t[0]);
            final m = int.tryParse(t[1]);
            if (h == null || m == null) return null;
            return TimeOfDay(hour: h, minute: m);
          }
          _openTime = parse(parts[0]);
          _closeTime = parse(parts[1]);
        }
      }
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(context, 'Load failed: $e', isSuccess: false, errorMessage: 'Load failed');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------- image pick ----------
  Future<void> _pickFromGallery() async {
    final x = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 90, maxWidth: 2048);
    if (x != null) {
      _picked = x;
      _pickedBytes = kIsWeb ? await x.readAsBytes() : null;
      setState(() {});
    }
  }

  Future<void> _pickFromCamera() async {
    final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 90, maxWidth: 2048);
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

  String _formatTime(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _pickOpenTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _openTime ?? const TimeOfDay(hour: 8, minute: 0),
    );
    if (t != null) setState(() => _openTime = t);
  }

  Future<void> _pickCloseTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _closeTime ?? const TimeOfDay(hour: 22, minute: 0),
    );
    if (t != null) setState(() => _closeTime = t);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;

    final openingHours = (_openTime != null && _closeTime != null)
        ? '${_formatTime(_openTime!)}–${_formatTime(_closeTime!)}'
        : '';

    setState(() => _saving = true);
    try {
      if (_myService == null) {
        if (_picked == null) {
          ToastHelper.showCustomToast(context, 'Please add a logo photo', isSuccess: false, errorMessage: 'Logo required');
          setState(() => _saving = false);
          return;
        }
        final created = await ServiceProviderServicess.create(
          businessName: _name.text.trim(),
          businessDescription: _desc.text.trim(),
          status: _status.text.trim(),
          openingHours: openingHours,
          logoPath: kIsWeb ? null : _picked!.path,
          logoBytes: kIsWeb ? _pickedBytes : null,
          logoFileName: _picked?.name,
        );
        _myService = created;
        if (mounted) {
          ToastHelper.showCustomToast(context, 'Shop created', isSuccess: true, errorMessage: 'Created');
        }
        _tabs.animateTo(1);
      } else {
        final updated = await ServiceProviderServicess.update(
          _myService!.id!,
          businessName: _name.text.trim(),
          businessDescription: _desc.text.trim(),
          status: _status.text.trim(),
          openingHours: openingHours,
          // logo optional on update
          logoPath: (_picked != null && !kIsWeb) ? _picked!.path : null,
          logoBytes: (_picked != null && kIsWeb) ? _pickedBytes : null,
          logoFileName: _picked?.name,
        );
        _myService = updated;
        if (mounted) {
          ToastHelper.showCustomToast(context, 'Shop updated', isSuccess: true, errorMessage: 'Updated');
        }
      }
      _clearPicked();
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(context, 'Save failed: $e', isSuccess: false, errorMessage: 'Save failed');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (_myService == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete your shop?'),
        content: const Text('This will remove your service. You can create it again later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _deleting = true);
    try {
      await ServiceProviderServicess.deleteById(_myService!.id!);
      _myService = null;
      if (mounted) {
        ToastHelper.showCustomToast(context, 'Shop deleted', isSuccess: true, errorMessage: 'Deleted');
      }
      _tabs.animateTo(0);
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(context, 'Delete failed: $e', isSuccess: false, errorMessage: 'Delete failed');
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  // ---- UI helpers (keep logic unchanged) ----
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
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final canSave = !_saving && (_myService == null ? _picked != null : true);
    final isUpdate = _myService != null;

    return Theme(
      data: Theme.of(context).copyWith(outlinedButtonTheme: _outlinedTheme),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Shop'),
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
              Tab(text: 'Shop Details'),
              Tab(text: 'Manage Shop'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: [
            _buildDetailsTab(canSave: canSave, isUpdate: isUpdate),
            _buildManageTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsTab({required bool canSave, required bool isUpdate}) {
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
                    'Add a clear logo and accurate opening hours so customers can trust your shop.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 14),

                Text(isUpdate ? 'Update Shop' : 'Open Shop Now',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),

                _FullBleedPicker(
                  picked: _picked,
                  pickedBytes: _pickedBytes,
                  onPickGallery: _pickFromGallery,
                  onPickCamera: _pickFromCamera,
                  onClearPicked: _clearPicked,
                  filledBtnStyle: _filledBtnStyle(),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _name,
                  decoration: _inputDecoration(label: 'Business name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _desc,
                  minLines: 2,
                  maxLines: 4,
                  decoration: _inputDecoration(label: 'Business description'),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _status,
                  decoration: _inputDecoration(label: 'Status (open / closed / busy)'),
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickOpenTime,
                        icon: const Icon(Icons.access_time),
                        label: Text(_openTime != null ? 'Open: ${_formatTime(_openTime!)}' : 'Pick Open Time'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickCloseTime,
                        icon: const Icon(Icons.access_time_outlined),
                        label: Text(_closeTime != null ? 'Close: ${_formatTime(_closeTime!)}' : 'Pick Close Time'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                FilledButton.icon(
                  style: _filledBtnStyle(),
                  onPressed: canSave ? _save : null,
                  icon: _saving
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save),
                  label: Text(isUpdate ? 'Save Changes' : 'Open Shop Now'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildManageTab() {
    if (_myService == null) {
      return RefreshIndicator(
        onRefresh: _loadMine,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Center(child: Text('No shop yet. Create yours in the Shop Details tab.', style: TextStyle(color: Colors.red))),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMine,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 420,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.82,
        ),
        itemCount: 1,
        itemBuilder: (context, i) {
          final sp = _myService!;
          return _ServiceCard(
            sp: sp,
            onEdit: () => _tabs.animateTo(0),
            onDelete: _deleting ? null : _delete,
            deleting: _deleting,
          );
        },
      ),
    );
  }
}

/* ---------------- helper widgets ---------------- */

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
    Widget inner;

    if (has) {
      if (kIsWeb && pickedBytes != null) {
        inner = Image.memory(pickedBytes!, height: 220, width: double.infinity, fit: BoxFit.cover);
      } else {
        inner = Image.file(File(picked!.path), height: 220, width: double.infinity, fit: BoxFit.cover);
      }
    } else {
      inner = Container(
        height: 220,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: const Center(child: Icon(Icons.image, size: 64, color: Colors.black38)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          elevation: 8,
          shadowColor: Colors.black12,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: inner,
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

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.sp,
    required this.onEdit,
    required this.onDelete,
    required this.deleting,
  });

  final ServiceProvider sp;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;
  final bool deleting;

  @override
  Widget build(BuildContext context) {
    final imgUrl = ApiConfig.prod; // kept as-is (logic unchanged)
    final hasImage = imgUrl.isNotEmpty;

    return Card(
      elevation: 6,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 160,
            child: Stack(
              children: [
                Positioned.fill(
                  child: hasImage
                      ? Image.network(
                          imgUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _imgFallback(),
                        )
                      : _imgFallback(),
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: [
                        _overlayBtn(
                          icon: Icons.edit_outlined,
                          label: 'Edit',
                          onPressed: onEdit,
                        ),
                        _overlayBtn(
                          icon: Icons.delete_outline,
                          label: 'Delete',
                          onPressed: deleting ? null : onDelete,
                          busy: deleting,
                          danger: true,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Text(
              sp.businessName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sp.businessDescription ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Text(
                  'Status: ${sp.status ?? 'open'} • Hours: ${sp.openingHours ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 6),
                if (sp.serviceProviderId != null)
                  Text('ServiceProviderID: ${sp.serviceProviderId}', style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _overlayBtn({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool busy = false,
    bool danger = false,
  }) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white.withOpacity(0.92),
        foregroundColor: danger ? Colors.red.shade700 : Colors.blueGrey.shade700,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: busy
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _imgFallback() => Container(
        color: Colors.grey.shade200,
        child: const Center(
          child: Icon(Icons.storefront_outlined, color: Colors.black38),
        ),
      );
}
