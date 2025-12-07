// lib/Pages/address.dart
import 'package:flutter/material.dart';

import 'package:vero360_app/models/address_model.dart';
import 'package:vero360_app/services/address_service.dart';
import 'package:vero360_app/toasthelper.dart';

class AddressPage extends StatefulWidget {
  const AddressPage({Key? key}) : super(key: key);

  @override
  State<AddressPage> createState() => _AddressPageState();
}

class _AddressPageState extends State<AddressPage> {
  final _svc = AddressService();
  final Color _brand = const Color(0xFFFF8A00); // Vero orange

  List<Address> _cache = [];
  Future<List<Address>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _loadAddresses();
  }

  Future<List<Address>> _loadAddresses() async {
    final list = await _svc.getMyAddresses();
    _cache = list;
    return list;
  }

  Future<void> _reload() async {
    setState(() => _future = _loadAddresses());
    await _future;
  }

  Future<void> _openCreate() async {
    final created = await showModalBottomSheet<Address>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GlassSheet(
        child: AddressFormSheet(
          title: 'Add new address',
          accent: _brand,
          onSubmit: (payload) => _svc.createAddress(payload),
        ),
      ),
    );
    if (created != null) {
      setState(() {
        _cache = [created, ..._cache];
        if (created.isDefault) {
          _cache = _cache
              .map((a) => a.copyWith(isDefault: a.id == created.id))
              .toList();
        }
        _future = Future.value(_cache);
      });
      ToastHelper.showCustomToast(
        context,
        'Address created',
        isSuccess: true,
        errorMessage: '',
      );
      await _reload();
    }
  }

  Future<void> _openEdit(Address addr) async {
    final updated = await showModalBottomSheet<Address>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GlassSheet(
        child: AddressFormSheet(
          title: 'Edit address',
          accent: _brand,
          initial: AddressPayload(
            addressType: addr.addressType,
            city: addr.city,
            description: addr.description,
            isGoogle: addr.isGoogle,
            formattedAddress:
                addr.formattedAddress.isEmpty ? null : addr.formattedAddress,
            placeId: addr.placeId.isEmpty ? null : addr.placeId,
            lat: addr.lat,
            lng: addr.lng,
          ),
          onSubmit: (payload) => _svc.updateAddress(addr.id, payload),
        ),
      ),
    );
    if (updated != null) {
      setState(() {
        _cache = _cache.map((a) => a.id == updated.id ? updated : a).toList();
        _future = Future.value(_cache);
      });
      ToastHelper.showCustomToast(
        context,
        'Address updated',
        isSuccess: true,
        errorMessage: '',
      );
      await _reload();
    }
  }

  Future<void> _confirmDelete(Address addr) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Address'),
        content: Text('Delete "${addr.displayLine}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _brand),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _svc.deleteAddress(addr.id);
      setState(() {
        _cache = _cache.where((a) => a.id != addr.id).toList();
        _future = Future.value(_cache);
      });
      ToastHelper.showCustomToast(
        context,
        'Address deleted',
        isSuccess: true,
        errorMessage: '',
      );
      await _reload();
    }
  }

  /// ✅ This is the important part:
  /// - Backend call must succeed, otherwise show error.
  /// - If backend ok, we flip `isDefault` in `_cache`.
  /// - The radio reads directly from `address.isDefault`.
  Future<void> _setDefault(Address a) async {
    // 1. Backend call
    try {
      await _svc.setDefaultAddress(a.id);
    } catch (e) {
      ToastHelper.showCustomToast(
        context,
        'Failed to set default',
        isSuccess: false,
        errorMessage: e.toString(),
      );
      return;
    }

    // 2. Optimistic local update — only one address with isDefault = true
    setState(() {
      _cache = _cache
          .map((x) => x.copyWith(isDefault: x.id == a.id))
          .toList();
      _future = Future.value(_cache);
    });

    // 3. Success toast
    ToastHelper.showCustomToast(
      context,
      'Default address set',
      isSuccess: true,
      errorMessage: '',
    );

    // 4. Best-effort reload (don’t break UI if this fails)
    try {
      await _reload();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: const Color(0xFF222222),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF222222),
        title: const Text('Select address'),
        centerTitle: true,
      ),
     floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _brand,
        onPressed: _openCreate,
        icon: const Icon(Icons.add_location_alt),
        label: const Text('Add address'),
      ),
      body: Column(
        children: [
          _HeaderCard(brand: _brand, titleStyle: titleStyle),
          Expanded(
            child: RefreshIndicator(
              color: _brand,
              onRefresh: _reload,
              child: FutureBuilder<List<Address>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return ListView(
                      children: [
                        const SizedBox(height: 40),
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'Error: ${snap.error}',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  final items = _cache;
                  if (items.isEmpty) {
                    return ListView(
                      children: [
                        const SizedBox(height: 80),
                        _EmptyCard(brand: _brand, onAdd: _openCreate),
                        const SizedBox(height: 120),
                      ],
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final a = items[i];
                      return _AddressCard(
                        brand: _brand,
                        address: a,
                        onSetDefault: () => _setDefault(a),
                        onEdit: () => _openEdit(a),
                        onDelete: () => _confirmDelete(a),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* --------------------------- STYLED SUBWIDGETS --------------------------- */

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.brand, this.titleStyle});
  final Color brand;
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            blurRadius: 22,
            spreadRadius: -8,
            offset: Offset(0, 14),
            color: Color(0x1A000000),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [brand.withOpacity(.15), Colors.white],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.location_city_rounded,
              size: 40,
              color: Color(0xFF6B778C),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Select address', style: titleStyle),
                const SizedBox(height: 6),
                Text(
                  'Choose your default delivery / pickup location',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: const Color(0xFF6B778C)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.brand, required this.onAdd});
  final Color brand;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            blurRadius: 22,
            spreadRadius: -8,
            offset: Offset(0, 14),
            color: Color(0x1A000000),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: brand.withOpacity(.15),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.add_location_alt_outlined,
              size: 40,
              color: Color(0xFF6B778C),
            ),
          ),
          const SizedBox(height: 12),
          const Text('No addresses yet'),
          const SizedBox(height: 4),
          Text(
            'Add your first address to make checkout faster.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: const Color(0xFF6B778C)),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: brand,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: onAdd,
              child: const Text('Add new address'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({
    required this.brand,
    required this.address,
    required this.onSetDefault,
    required this.onEdit,
    required this.onDelete,
  });

  final Color brand;
  final Address address;
  final VoidCallback onSetDefault;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final subtitle = address.description.isEmpty ? '—' : address.description;
    final isDefault = address.isDefault;

    return Material(
      elevation: 0,
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDefault
                ? brand.withOpacity(.35)
                : const Color(0x11000000),
          ),
          boxShadow: const [
            BoxShadow(
              blurRadius: 18,
              spreadRadius: -10,
              offset: Offset(0, 12),
              color: Color(0x14000000),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: brand.withOpacity(.12),
                child: Icon(
                  _iconForType(address.addressType),
                  color: brand,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        Text(
                          _labelForType(address.addressType),
                          style: t.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (address.isGoogle)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(.1),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'Google',
                              style: t.textTheme.labelSmall?.copyWith(
                                color: Colors.blue,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (isDefault)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: brand.withOpacity(.15),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'Default',
                              style: t.textTheme.labelSmall?.copyWith(
                                color: brand,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(address.displayLine, style: t.textTheme.bodyMedium),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: t.textTheme.bodySmall
                          ?.copyWith(color: const Color(0xFF6B778C)),
                    ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ✅ Radio now directly bound to `address.isDefault`
                  Radio<bool>(
                    value: address.isDefault,
                    groupValue: true,
                    activeColor: brand,
                    onChanged: (_) => onSetDefault(),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Edit',
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconForType(AddressType t) {
    switch (t) {
      case AddressType.home:
        return Icons.home_outlined;
      case AddressType.work:
        return Icons.work_outline;
      case AddressType.business:
        return Icons.apartment_outlined;
      case AddressType.other:
        return Icons.place_outlined;
    }
  }

  static String _labelForType(AddressType t) {
    switch (t) {
      case AddressType.home:
        return 'Home';
      case AddressType.work:
        return 'Office';
      case AddressType.business:
        return 'Business';
      case AddressType.other:
        return 'Other';
    }
  }
}

/* ------------------------------ FORM SHEET ------------------------------ */

class _GlassSheet extends StatelessWidget {
  const _GlassSheet({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: child,
      ),
    );
  }
}

class AddressFormSheet extends StatefulWidget {
  const AddressFormSheet({
    Key? key,
    required this.title,
    required this.onSubmit,
    required this.accent,
    this.initial,
  }) : super(key: key);

  final String title;
  final AddressPayload? initial;
  final Future<Address> Function(AddressPayload payload) onSubmit;
  final Color accent;

  @override
  State<AddressFormSheet> createState() => _AddressFormSheetState();
}

class _AddressFormSheetState extends State<AddressFormSheet> {
  final _formKey = GlobalKey<FormState>();

  // Manual fields
  late AddressType _type;
  final _cityCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  // Google flow
  bool _useGoogle = false;
  final _googleSearchCtrl = TextEditingController();
  List<Map<String, dynamic>> _predictions = [];
  Map<String, dynamic>? _selectedPlace;
  String? _sessionToken; // optional grouping token

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _type = widget.initial?.addressType ?? AddressType.home;
    _cityCtrl.text = widget.initial?.city ?? '';
    _descCtrl.text = widget.initial?.description ?? '';

    if (widget.initial?.isGoogle == true ||
        (widget.initial?.placeId?.isNotEmpty ?? false) ||
        (widget.initial?.formattedAddress?.isNotEmpty ?? false)) {
      _useGoogle = true;
      _googleSearchCtrl.text =
          widget.initial?.formattedAddress ?? widget.initial?.city ?? '';
    }
  }

  @override
  void dispose() {
    _cityCtrl.dispose();
    _descCtrl.dispose();
    _googleSearchCtrl.dispose();
    super.dispose();
  }

  // ----------------- Google proxy -----------------
  Future<void> _onQueryChanged(String q) async {
    if (q.trim().length < 2) {
      setState(() => _predictions = []);
      return;
    }
    try {
      final svc = AddressService();
      final preds =
          await svc.placesAutocomplete(q, sessionToken: _sessionToken);
      if (!mounted) return;
      setState(() => _predictions = preds);
    } catch (_) {}
  }

  Future<void> _selectPrediction(Map<String, dynamic> p) async {
    final placeId = (p['place_id'] ?? p['placeId'] ?? '').toString();
    if (placeId.isEmpty) return;
    final svc = AddressService();
    final det = await svc.placeDetails(placeId, sessionToken: _sessionToken);
    if (!mounted) return;
    setState(() => _selectedPlace = det);
  }

  // ----------------- Submissions -----------------
  Future<void> _submitManual() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final payload = AddressPayload(
        addressType: _type,
        city: _cityCtrl.text.trim(),
        description: _descCtrl.text.trim(),
      );
      final result = await widget.onSubmit(payload);
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Failed',
        isSuccess: false,
        errorMessage: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _submitGoogle() async {
    if (_selectedPlace == null) {
      ToastHelper.showCustomToast(
        context,
        'Select an address from suggestions',
        isSuccess: false,
        errorMessage: '',
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final res = _selectedPlace!['result'] ?? _selectedPlace!;
      final fa = (res['formatted_address'] ?? '').toString();
      final pid = (res['place_id'] ?? '').toString();
      final loc = res['geometry']?['location'];
      final lat = (loc?['lat'] as num?)?.toDouble();
      final lng = (loc?['lng'] as num?)?.toDouble();

      final payload = AddressPayload(
        addressType: _type,
        city: _cityCtrl.text.isNotEmpty ? _cityCtrl.text.trim() : fa,
        description: _descCtrl.text.trim(),
        isGoogle: true,
        formattedAddress: fa,
        placeId: pid,
        lat: lat,
        lng: lng,
      );
      final result = await widget.onSubmit(payload);
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Failed',
        isSuccess: false,
        errorMessage: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ----------------- UI -----------------
  @override
  Widget build(BuildContext context) {
    final brand = widget.accent;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 140,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [brand.withOpacity(.15), Colors.white],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(
                  child: Icon(
                    Icons.location_city_rounded,
                    size: 72,
                    color: Color(0xFF98A2B3),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 12),

              // Toggle Manual / Google
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('Manual'),
                    selected: !_useGoogle,
                    onSelected: (v) => setState(() => _useGoogle = !v),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Google'),
                    selected: _useGoogle,
                    onSelected: (v) => setState(() => _useGoogle = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (!_useGoogle)
                _manualForm(brand)
              else
                _googleForm(brand),
            ],
          ),
        ),
      ),
    );
  }

  Widget _manualForm(Color brand) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          DropdownButtonFormField<AddressType>(
            value: _type,
            decoration: const InputDecoration(
              labelText: 'Type',
              border: OutlineInputBorder(),
            ),
            items: AddressType.values
                .map(
                  (t) => DropdownMenuItem(
                    value: t,
                    child: Text(_label(t)),
                  ),
                )
                .toList(),
            onChanged: (v) =>
                setState(() => _type = v ?? AddressType.home),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _cityCtrl,
            decoration: const InputDecoration(
              labelText: 'City / Label',
              hintText: 'e.g. Lilongwe',
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'City is required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _descCtrl,
            decoration: const InputDecoration(
              labelText: 'Description',
              hintText: 'e.g. Area 17, Street riverside, House No 23.',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black87,
                    side: BorderSide(
                      color: Colors.black12.withOpacity(.4),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed:
                      _saving ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: brand,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding:
                        const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _saving ? null : _submitManual,
                  child: Text(_saving ? 'Saving…' : 'Save address'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _googleForm(Color brand) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<AddressType>(
          value: _type,
          decoration: const InputDecoration(
            labelText: 'Type',
            border: OutlineInputBorder(),
          ),
          items: AddressType.values
              .map(
                (t) => DropdownMenuItem(
                  value: t,
                  child: Text(_label(t)),
                ),
              )
              .toList(),
          onChanged: (v) =>
              setState(() => _type = v ?? AddressType.home),
        ),
        const SizedBox(height: 12),

        TextField(
          controller: _cityCtrl,
          decoration: const InputDecoration(
            labelText: 'Label (optional)',
            hintText: 'e.g. Home, Office, Area 12',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _descCtrl,
          decoration: const InputDecoration(
            labelText: 'Delivery notes (optional)',
            hintText: 'Gate color, flat number, etc.',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 12),

        TextField(
          controller: _googleSearchCtrl,
          decoration: const InputDecoration(
            labelText: 'Search address (Google)',
            hintText: 'Start typing…',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: _onQueryChanged,
        ),
        const SizedBox(height: 8),

        if (_predictions.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: ListView.separated(
              itemCount: _predictions.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final p = _predictions[i];
                final main = p['structured_formatting']?['main_text'] ??
                    p['description'] ??
                    '';
                final sec =
                    p['structured_formatting']?['secondary_text'] ?? '';
                return ListTile(
                  leading: const Icon(Icons.place_outlined),
                  title: Text(
                    main.toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: sec.toString().isNotEmpty
                      ? Text(
                          sec.toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                  onTap: () => _selectPrediction(p),
                );
              },
            ),
          ),

        if (_selectedPlace != null) ...[
          const SizedBox(height: 8),
          _placePreviewCard(_selectedPlace!, brand),
        ],

        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: brand,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _saving ? null : _submitGoogle,
            child: Text(_saving ? 'Saving…' : 'Save address'),
          ),
        ),
      ],
    );
  }

  Widget _placePreviewCard(Map<String, dynamic> det, Color brand) {
    final res = det['result'] ?? det;
    final fa = (res['formatted_address'] ?? '').toString();
    final loc = res['geometry']?['location'];
    final lat = loc?['lat']?.toString();
    final lng = loc?['lng']?.toString();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: brand.withOpacity(.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.place, color: Colors.black54),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              fa,
              maxLines: 3,
            ),
          ),
          if (lat != null && lng != null)
            Text(
              '($lat,$lng)',
              style: const TextStyle(color: Colors.black54),
            ),
        ],
      ),
    );
  }

  static String _label(AddressType t) {
    switch (t) {
      case AddressType.home:
        return 'Home';
      case AddressType.work:
        return 'Office';
      case AddressType.business:
        return 'Business';
      case AddressType.other:
        return 'Other';
    }
  }
}
