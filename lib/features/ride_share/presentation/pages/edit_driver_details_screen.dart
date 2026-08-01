import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:vero360_app/GernalServices/driver_service.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/driver_provider.dart';
import 'package:vero360_app/utils/toasthelper.dart';

class EditDriverDetailsScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> driver;

  const EditDriverDetailsScreen({super.key, required this.driver});

  @override
  ConsumerState<EditDriverDetailsScreen> createState() =>
      _EditDriverDetailsScreenState();
}

class _EditDriverDetailsScreenState
    extends ConsumerState<EditDriverDetailsScreen> {
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandNavy = Color(0xFF16284C);

  final _formKey = GlobalKey<FormState>();
  final _driverService = DriverService();
  bool _saving = false;

  late final TextEditingController _bioController;
  late final TextEditingController _licenseController;
  late final TextEditingController _bankNameController;
  late final TextEditingController _bankNumberController;
  late final TextEditingController _bankCodeController;
  DateTime? _licenseExpiry;

  @override
  void initState() {
    super.initState();
    final d = widget.driver;
    _bioController = TextEditingController(text: (d['bio'] ?? '').toString());
    _licenseController =
        TextEditingController(text: (d['licenseNumber'] ?? '').toString());
    _bankNameController =
        TextEditingController(text: (d['bankAccountName'] ?? '').toString());
    _bankNumberController =
        TextEditingController(text: (d['bankAccountNumber'] ?? '').toString());
    _bankCodeController =
        TextEditingController(text: (d['bankCode'] ?? '').toString());

    final expiry = d['licenseExpiry'];
    if (expiry is String && expiry.isNotEmpty) {
      _licenseExpiry = DateTime.tryParse(expiry);
    }
  }

  @override
  void dispose() {
    _bioController.dispose();
    _licenseController.dispose();
    _bankNameController.dispose();
    _bankNumberController.dispose();
    _bankCodeController.dispose();
    super.dispose();
  }

  Future<void> _pickLicenseExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _licenseExpiry ?? now.add(const Duration(days: 365)),
      firstDate: now,
      lastDate: DateTime(now.year + 20),
    );
    if (picked != null) {
      setState(() => _licenseExpiry = picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final driverId = widget.driver['id'];
    if (driverId == null) return;

    setState(() => _saving = true);
    try {
      final payload = <String, dynamic>{
        'bio': _bioController.text.trim(),
        'licenseNumber': _licenseController.text.trim(),
        if (_licenseExpiry != null)
          'licenseExpiry': DateFormat('yyyy-MM-dd').format(_licenseExpiry!),
        'bankAccountName': _bankNameController.text.trim(),
        'bankAccountNumber': _bankNumberController.text.trim(),
        'bankCode': _bankCodeController.text.trim(),
      };

      await _driverService.updateDriver(
        int.parse(driverId.toString()),
        payload,
      );

      ref.invalidate(myDriverProfileProvider);

      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Driver details updated',
        isSuccess: true,
        errorMessage: '',
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Could not save driver details',
        isSuccess: false,
        errorMessage: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FB),
      appBar: AppBar(
        title: const Text('Edit Driver Details'),
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _sectionTitle('About you'),
            _fieldCard(
              child: TextFormField(
                controller: _bioController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Bio',
                  hintText: 'Tell passengers a little about yourself',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _sectionTitle('License'),
            _fieldCard(
              child: Column(
                children: [
                  TextFormField(
                    controller: _licenseController,
                    decoration: const InputDecoration(
                      labelText: 'License number',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: _pickLicenseExpiry,
                    borderRadius: BorderRadius.circular(8),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'License expiry',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                      child: Text(
                        _licenseExpiry != null
                            ? DateFormat.yMMMd().format(_licenseExpiry!)
                            : 'Select date',
                        style: TextStyle(
                          color: _licenseExpiry != null
                              ? _brandNavy
                              : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _sectionTitle('Payout bank details'),
            _fieldCard(
              child: Column(
                children: [
                  TextFormField(
                    controller: _bankNameController,
                    decoration: const InputDecoration(
                      labelText: 'Account name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _bankNumberController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Account number',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _bankCodeController,
                    decoration: const InputDecoration(
                      labelText: 'Bank code',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: _brandOrange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Save changes',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 15,
          color: _brandNavy,
        ),
      ),
    );
  }

  Widget _fieldCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E6EF)),
      ),
      child: child,
    );
  }
}
