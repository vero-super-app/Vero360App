import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:vero360_app/GernalServices/driver_service.dart';
import 'package:vero360_app/features/ride_share/core/fleet_image_compressor.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_share_ui_constants.dart';

enum _OnboardingPhase { driver, vehicle, status }

/// Dual-gate driver verification wizard (identity docs → vehicle docs → status).
class BecomeDriverPage extends StatefulWidget {
  const BecomeDriverPage({super.key});

  @override
  State<BecomeDriverPage> createState() => _BecomeDriverPageState();
}

class _BecomeDriverPageState extends State<BecomeDriverPage> {
  final _driverService = DriverService();
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  final _licenseNumber = TextEditingController();
  final _nationalId = TextEditingController();
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _plate = TextEditingController();
  final _color = TextEditingController();
  final _seats = TextEditingController(text: '4');

  DateTime? _dateOfBirth;
  DateTime? _licenseExpiry;
  DateTime? _insuranceExpiry;
  DateTime? _cofExpiry;
  int? _year;

  String? _licenseImagePath;
  String? _nationalIdImagePath;
  String? _vehicleImagePath;
  String? _registrationImagePath;
  String? _insuranceImagePath;
  String? _cofImagePath;

  Map<String, dynamic>? _profile;
  _OnboardingPhase _phase = _OnboardingPhase.driver;
  bool _loading = true;
  bool _submitting = false;
  bool _compressing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _licenseNumber.dispose();
    _nationalId.dispose();
    _make.dispose();
    _model.dispose();
    _plate.dispose();
    _color.dispose();
    _seats.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await _driverService.getMyDriverProfile();
      _applyLoadedProfile(profile);
    } catch (e) {
      // Empty / missing profile is fine for first apply
      setState(() {
        _profile = null;
        _phase = _OnboardingPhase.driver;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyLoadedProfile(Map<String, dynamic> profile) {
    _profile = profile;
    final status = profile['status']?.toString() ?? '';
    final isVerified = profile['isVerified'] == true;
    final license = (profile['licenseNumber']?.toString() ?? '').trim();
    final hasLicenseImage =
        (profile['licenseImageUrl']?.toString() ?? '').trim().isNotEmpty;
    final taxis = (profile['taxis'] is List)
        ? List<Map<String, dynamic>>.from(
            (profile['taxis'] as List).whereType<Map>().map(
                  (e) => Map<String, dynamic>.from(e),
                ),
          )
        : <Map<String, dynamic>>[];
    final taxi = taxis.isNotEmpty ? taxis.first : null;
    final taxiStatus = taxi?['status']?.toString() ?? '';

    if (license.isNotEmpty) _licenseNumber.text = license;
    final nid = (profile['nationalId']?.toString() ?? '').trim();
    if (nid.isNotEmpty) _nationalId.text = nid;
    final dob = DateTime.tryParse(profile['dateOfBirth']?.toString() ?? '');
    if (dob != null) _dateOfBirth = dob;
    final lex = DateTime.tryParse(profile['licenseExpiry']?.toString() ?? '');
    if (lex != null) _licenseExpiry = lex;

    if (taxi != null) {
      _make.text = taxi['make']?.toString() ?? '';
      _model.text = taxi['model']?.toString() ?? '';
      _plate.text = taxi['licensePlate']?.toString() ?? '';
      _color.text = taxi['color']?.toString() ?? '';
      _seats.text = '${taxi['seats'] ?? 4}';
      _year = (taxi['year'] as num?)?.toInt();
      _insuranceExpiry =
          DateTime.tryParse(taxi['insuranceExpiry']?.toString() ?? '');
      _cofExpiry = DateTime.tryParse(taxi['cofExpiry']?.toString() ?? '');
    }

    _OnboardingPhase next;
    if (status == 'REJECTED') {
      next = _OnboardingPhase.driver;
    } else if (!hasLicenseImage) {
      next = _OnboardingPhase.driver;
    } else if (taxi == null || taxiStatus == 'INACTIVE') {
      next = _OnboardingPhase.vehicle;
    } else if (isVerified && taxiStatus == 'ACTIVE') {
      next = _OnboardingPhase.status;
    } else if (status == 'PENDING_VERIFICATION' && taxiStatus != 'PENDING_REVIEW') {
      next = _OnboardingPhase.vehicle;
    } else {
      next = _OnboardingPhase.status;
    }

    setState(() => _phase = next);
  }

  Future<void> _pickDoc(
    String type,
    void Function(String path) onPicked,
  ) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 2000,
    );
    if (picked == null) return;

    setState(() => _compressing = true);
    try {
      final path = await FleetImageCompressor.compressForUpload(picked.path);
      onPicked(path);
    } finally {
      if (mounted) setState(() => _compressing = false);
    }
  }

  Future<void> _submitDriverStep() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dateOfBirth == null || _licenseExpiry == null) {
      setState(() => _error = 'Date of birth and license expiry are required.');
      return;
    }
    final age = DateTime.now().difference(_dateOfBirth!).inDays / 365.25;
    if (age < 18) {
      setState(() => _error = 'You must be at least 18 years old.');
      return;
    }
    final existingLicenseUrl =
        (_profile?['licenseImageUrl']?.toString() ?? '').trim();
    if (_licenseImagePath == null && existingLicenseUrl.isEmpty) {
      setState(() => _error = 'Upload a clear photo of your driving license.');
      return;
    }
    final existingNidUrl =
        (_profile?['nationalIdImageUrl']?.toString() ?? '').trim();
    if (_nationalIdImagePath == null && existingNidUrl.isEmpty) {
      setState(() => _error = 'Upload a clear photo of your national ID.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      String licenseUrl = existingLicenseUrl;
      if (_licenseImagePath != null) {
        licenseUrl = await _driverService.uploadDriverDocument(
          _licenseImagePath!,
          'license',
        );
      }
      String? nidUrl = existingNidUrl.isEmpty ? null : existingNidUrl;
      if (_nationalIdImagePath != null) {
        nidUrl = await _driverService.uploadDriverDocument(
          _nationalIdImagePath!,
          'national_id',
        );
      }

      final payload = <String, dynamic>{
        'licenseNumber': _licenseNumber.text.trim(),
        'licenseImageUrl': licenseUrl,
        'licenseExpiry': _licenseExpiry!.toIso8601String(),
        'dateOfBirth': _dateOfBirth!.toIso8601String(),
        'nationalId': _nationalId.text.trim(),
        if (nidUrl != null) 'nationalIdImageUrl': nidUrl,
      };

      Map<String, dynamic> profile;
      final wasVerified = _profile?['isVerified'] == true;
      if (wasVerified) {
        profile = await _driverService.updateMyDriver(payload);
      } else {
        profile = await _driverService.applyAsDriver(payload);
      }

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _licenseImagePath = null;
        _nationalIdImagePath = null;
        _phase = _OnboardingPhase.vehicle;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Driver documents submitted for review.'),
          backgroundColor: RideShareColors.primaryDeep,
        ),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitVehicleStep() async {
    if (_make.text.trim().isEmpty ||
        _model.text.trim().isEmpty ||
        _plate.text.trim().isEmpty) {
      setState(() => _error = 'Make, model, and license plate are required.');
      return;
    }
    if (_year == null) {
      setState(() => _error = 'Select the vehicle year.');
      return;
    }
    if (_insuranceExpiry == null || _cofExpiry == null) {
      setState(() => _error = 'Insurance and COF expiry dates are required.');
      return;
    }

    final taxis = (_profile?['taxis'] is List)
        ? List<Map<String, dynamic>>.from(
            (_profile!['taxis'] as List).whereType<Map>().map(
                  (e) => Map<String, dynamic>.from(e),
                ),
          )
        : <Map<String, dynamic>>[];
    final taxi = taxis.isNotEmpty ? taxis.first : null;
    final existingVehicleUrl = (taxi?['imageUrl']?.toString() ?? '').trim();
    final existingRegUrl =
        (taxi?['registrationImageUrl']?.toString() ?? '').trim();
    final existingInsUrl =
        (taxi?['insuranceImageUrl']?.toString() ?? '').trim();
    final existingCofUrl = (taxi?['cofImageUrl']?.toString() ?? '').trim();

    if (_vehicleImagePath == null && existingVehicleUrl.isEmpty) {
      setState(() => _error = 'Upload a photo of your vehicle.');
      return;
    }
    if (_registrationImagePath == null && existingRegUrl.isEmpty) {
      setState(() => _error = 'Upload your vehicle registration (logbook).');
      return;
    }
    if (_insuranceImagePath == null && existingInsUrl.isEmpty) {
      setState(() => _error = 'Upload your vehicle insurance document.');
      return;
    }
    if (_cofImagePath == null && existingCofUrl.isEmpty) {
      setState(() => _error = 'Upload your Certificate of Fitness (COF).');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      var vehicleUrl = existingVehicleUrl;
      var regUrl = existingRegUrl;
      var insUrl = existingInsUrl;
      var cofUrl = existingCofUrl;

      if (_vehicleImagePath != null) {
        vehicleUrl = await _driverService.uploadDriverDocument(
          _vehicleImagePath!,
          'vehicle',
        );
      }
      if (_registrationImagePath != null) {
        regUrl = await _driverService.uploadDriverDocument(
          _registrationImagePath!,
          'registration',
        );
      }
      if (_insuranceImagePath != null) {
        insUrl = await _driverService.uploadDriverDocument(
          _insuranceImagePath!,
          'insurance',
        );
      }
      if (_cofImagePath != null) {
        cofUrl = await _driverService.uploadDriverDocument(
          _cofImagePath!,
          'cof',
        );
      }

      final payload = <String, dynamic>{
        'taxiClass': 'STANDARD',
        'make': _make.text.trim(),
        'model': _model.text.trim(),
        'year': _year,
        'licensePlate': _plate.text.trim().toUpperCase(),
        'color': _color.text.trim().isEmpty ? 'Unknown' : _color.text.trim(),
        'seats': int.tryParse(_seats.text.trim()) ?? 4,
        'registrationNumber': _plate.text.trim().toUpperCase(),
        'imageUrl': vehicleUrl,
        'registrationImageUrl': regUrl,
        'insuranceImageUrl': insUrl,
        'insuranceExpiry': _insuranceExpiry!.toIso8601String(),
        'cofImageUrl': cofUrl,
        'cofExpiry': _cofExpiry!.toIso8601String(),
        'features': ['AC'],
      };

      final taxiStatus = taxi?['status']?.toString() ?? '';
      if (taxi != null &&
          taxi['id'] != null &&
          taxiStatus == 'ACTIVE') {
        await _driverService.updateTaxi(
          (taxi['id'] as num).toInt(),
          payload,
        );
      } else {
        await _driverService.submitVehicleProposal(payload);
      }

      final refreshed = await _driverService.getMyDriverProfile();
      if (!mounted) return;
      setState(() {
        _profile = refreshed;
        _vehicleImagePath = null;
        _registrationImagePath = null;
        _insuranceImagePath = null;
        _cofImagePath = null;
        _phase = _OnboardingPhase.status;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vehicle documents submitted for review.'),
          backgroundColor: RideShareColors.primaryDeep,
        ),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _pickDate({
    required DateTime? current,
    required DateTime firstDate,
    required DateTime lastDate,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? lastDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (picked != null) onPicked(picked);
  }

  String _fmt(DateTime? d) =>
      d == null ? 'Select date' : DateFormat('dd MMM yyyy').format(d);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RideShareColors.background,
      appBar: AppBar(
        backgroundColor: RideShareColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Driver verification'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: RideShareColors.primary),
            )
          : Column(
              children: [
                _phaseStrip(),
                if (_compressing)
                  const LinearProgressIndicator(
                    color: RideShareColors.primary,
                    minHeight: 3,
                  ),
                if (_error != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFB91C1C)),
                    ),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: switch (_phase) {
                      _OnboardingPhase.driver => _driverForm(),
                      _OnboardingPhase.vehicle => _vehicleForm(),
                      _OnboardingPhase.status => _statusView(),
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _phaseStrip() {
    Widget chip(String label, _OnboardingPhase phase, bool enabled) {
      final active = _phase == phase;
      return Expanded(
        child: InkWell(
          onTap: enabled ? () => setState(() => _phase = phase) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: active
                  ? RideShareColors.primarySoft
                  : Colors.transparent,
              border: Border(
                bottom: BorderSide(
                  color: active
                      ? RideShareColors.primary
                      : RideShareColors.outline,
                  width: active ? 2.5 : 1,
                ),
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: enabled
                    ? RideShareColors.titleText
                    : RideShareColors.bodyText,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
    }

    final driverDone =
        ((_profile?['licenseImageUrl']?.toString() ?? '').trim().isNotEmpty);
    return Row(
      children: [
        chip('1. Driver', _OnboardingPhase.driver, true),
        chip('2. Vehicle', _OnboardingPhase.vehicle, driverDone),
        chip(
          '3. Status',
          _OnboardingPhase.status,
          driverDone,
        ),
      ],
    );
  }

  Widget _card({required String title, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E6EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: RideShareColors.primaryDeep,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFF7F7F9),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E6EF)),
        ),
      );

  Widget _dateTile({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        _fmt(value),
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: RideShareColors.titleText,
        ),
      ),
      trailing: const Icon(Icons.calendar_today_outlined, size: 18),
      onTap: onTap,
    );
  }

  Widget _docTile({
    required String label,
    required String? localPath,
    required String? existingUrl,
    required VoidCallback onPick,
  }) {
    final hasRemote = (existingUrl ?? '').trim().isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (localPath != null || hasRemote)
              ? RideShareColors.primary
              : const Color(0xFFE2E6EF),
          style: BorderStyle.solid,
        ),
        color: RideShareColors.primarySoft.withValues(alpha: 0.35),
      ),
      child: Row(
        children: [
          if (localPath != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(localPath),
                width: 56,
                height: 56,
                fit: BoxFit.cover,
              ),
            )
          else
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                hasRemote ? Icons.check_circle : Icons.add_a_photo_outlined,
                color: hasRemote
                    ? Colors.green
                    : RideShareColors.primaryDeep,
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  localPath != null
                      ? 'New photo selected'
                      : hasRemote
                          ? 'On file — tap to replace'
                          : 'Required — tap to add',
                  style: TextStyle(
                    fontSize: 12,
                    color: RideShareColors.bodyText,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onPick, child: Text(hasRemote || localPath != null ? 'Replace' : 'Add')),
        ],
      ),
    );
  }

  Widget _driverForm() {
    final now = DateTime.now();
    return Form(
      key: _formKey,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: RideShareColors.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Upload your license and national ID. An operator will review them before you can go online.',
              style: TextStyle(color: RideShareColors.onSecondaryContainer),
            ),
          ),
          const SizedBox(height: 14),
          _card(
            title: 'Identity',
            children: [
              TextFormField(
                controller: _licenseNumber,
                decoration: _fieldDecoration('License number'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _nationalId,
                decoration: _fieldDecoration('National ID number'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              _dateTile(
                label: 'Date of birth',
                value: _dateOfBirth,
                onTap: () => _pickDate(
                  current: _dateOfBirth,
                  firstDate: DateTime(now.year - 80),
                  lastDate: DateTime(now.year - 18, now.month, now.day),
                  onPicked: (d) => setState(() => _dateOfBirth = d),
                ),
              ),
              _dateTile(
                label: 'License expiry',
                value: _licenseExpiry,
                onTap: () => _pickDate(
                  current: _licenseExpiry,
                  firstDate: now,
                  lastDate: DateTime(now.year + 20),
                  onPicked: (d) => setState(() => _licenseExpiry = d),
                ),
              ),
              _docTile(
                label: 'License photo',
                localPath: _licenseImagePath,
                existingUrl: _profile?['licenseImageUrl']?.toString(),
                onPick: () => _pickDoc(
                  'license',
                  (p) => setState(() => _licenseImagePath = p),
                ),
              ),
              _docTile(
                label: 'National ID photo',
                localPath: _nationalIdImagePath,
                existingUrl: _profile?['nationalIdImageUrl']?.toString(),
                onPick: () => _pickDoc(
                  'national_id',
                  (p) => setState(() => _nationalIdImagePath = p),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: RideShareColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _submitting ? null : _submitDriverStep,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Submit for review'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vehicleForm() {
    final now = DateTime.now();
    final years = List.generate(30, (i) => now.year - i);
    final taxis = (_profile?['taxis'] is List)
        ? List<Map<String, dynamic>>.from(
            (_profile!['taxis'] as List).whereType<Map>().map(
                  (e) => Map<String, dynamic>.from(e),
                ),
          )
        : <Map<String, dynamic>>[];
    final taxi = taxis.isNotEmpty ? taxis.first : null;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: RideShareColors.primarySoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'Add your vehicle details and compliance documents (registration, insurance, COF).',
            style: TextStyle(color: RideShareColors.onSecondaryContainer),
          ),
        ),
        const SizedBox(height: 14),
        _card(
          title: 'Vehicle details',
          children: [
            TextField(
              controller: _make,
              decoration: _fieldDecoration('Make'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _model,
              decoration: _fieldDecoration('Model'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              // ignore: deprecated_member_use
              value: _year,
              decoration: _fieldDecoration('Year'),
              items: years
                  .map(
                    (y) => DropdownMenuItem(value: y, child: Text('$y')),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _year = v),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _plate,
              decoration: _fieldDecoration('License plate'),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _color,
              decoration: _fieldDecoration('Color'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _seats,
              decoration: _fieldDecoration('Seats'),
              keyboardType: TextInputType.number,
            ),
            _dateTile(
              label: 'Insurance expiry',
              value: _insuranceExpiry,
              onTap: () => _pickDate(
                current: _insuranceExpiry,
                firstDate: now,
                lastDate: DateTime(now.year + 10),
                onPicked: (d) => setState(() => _insuranceExpiry = d),
              ),
            ),
            _dateTile(
              label: 'COF expiry',
              value: _cofExpiry,
              onTap: () => _pickDate(
                current: _cofExpiry,
                firstDate: now,
                lastDate: DateTime(now.year + 10),
                onPicked: (d) => setState(() => _cofExpiry = d),
              ),
            ),
            _docTile(
              label: 'Vehicle photo',
              localPath: _vehicleImagePath,
              existingUrl: taxi?['imageUrl']?.toString(),
              onPick: () => _pickDoc(
                'vehicle',
                (p) => setState(() => _vehicleImagePath = p),
              ),
            ),
            _docTile(
              label: 'Registration (logbook)',
              localPath: _registrationImagePath,
              existingUrl: taxi?['registrationImageUrl']?.toString(),
              onPick: () => _pickDoc(
                'registration',
                (p) => setState(() => _registrationImagePath = p),
              ),
            ),
            _docTile(
              label: 'Insurance document',
              localPath: _insuranceImagePath,
              existingUrl: taxi?['insuranceImageUrl']?.toString(),
              onPick: () => _pickDoc(
                'insurance',
                (p) => setState(() => _insuranceImagePath = p),
              ),
            ),
            _docTile(
              label: 'Certificate of Fitness (COF)',
              localPath: _cofImagePath,
              existingUrl: taxi?['cofImageUrl']?.toString(),
              onPick: () => _pickDoc(
                'cof',
                (p) => setState(() => _cofImagePath = p),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: RideShareColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _submitting ? null : _submitVehicleStep,
            child: _submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Submit vehicle for review'),
          ),
        ),
      ],
    );
  }

  Widget _statusView() {
    final status = _profile?['status']?.toString() ?? 'PENDING_VERIFICATION';
    final isVerified = _profile?['isVerified'] == true;
    final reason = (_profile?['rejectionReason']?.toString() ?? '').trim();
    final taxis = (_profile?['taxis'] is List)
        ? List<Map<String, dynamic>>.from(
            (_profile!['taxis'] as List).whereType<Map>().map(
                  (e) => Map<String, dynamic>.from(e),
                ),
          )
        : <Map<String, dynamic>>[];
    final taxi = taxis.isNotEmpty ? taxis.first : null;
    final taxiStatus = taxi?['status']?.toString() ?? '—';

    String headline;
    String body;
    Color tone;
    if (status == 'REJECTED') {
      headline = 'Application rejected';
      body = reason.isEmpty
          ? 'Please update your documents and resubmit.'
          : reason;
      tone = const Color(0xFFB91C1C);
    } else if (isVerified && taxiStatus == 'ACTIVE') {
      headline = 'You are ready to drive';
      body =
          'Both gates are approved. Return to the driver dashboard and go online.';
      tone = const Color(0xFF047857);
    } else if (isVerified && taxiStatus == 'PENDING_REVIEW') {
      headline = 'Driver approved — vehicle under review';
      body =
          'Your identity documents are verified. Wait for an operator to approve your vehicle.';
      tone = RideShareColors.primaryDeep;
    } else if (status == 'PENDING_VERIFICATION') {
      headline = 'Documents under review';
      body =
          'An operator will verify your driver documents. You can also submit vehicle docs while you wait.';
      tone = RideShareColors.primaryDeep;
    } else {
      headline = 'Verification in progress';
      body = 'Driver: $status · Vehicle: $taxiStatus';
      tone = RideShareColors.primaryDeep;
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E6EF)),
          ),
          child: Column(
            children: [
              Icon(Icons.verified_user_outlined, size: 48, color: tone),
              const SizedBox(height: 12),
              Text(
                headline,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: tone,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(color: RideShareColors.bodyText),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (status == 'REJECTED' ||
            !( (_profile?['licenseImageUrl']?.toString() ?? '').isNotEmpty))
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () =>
                  setState(() => _phase = _OnboardingPhase.driver),
              child: const Text('Update driver documents'),
            ),
          ),
        if (taxi == null ||
            taxiStatus == 'INACTIVE' ||
            taxiStatus == 'PENDING_REVIEW')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () =>
                    setState(() => _phase = _OnboardingPhase.vehicle),
                child: Text(
                  taxiStatus == 'PENDING_REVIEW'
                      ? 'Update vehicle submission'
                      : 'Submit vehicle documents',
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: RideShareColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: _load,
            child: const Text('Refresh status'),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Back to driver home'),
        ),
      ],
    );
  }
}
