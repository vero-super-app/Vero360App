import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:vero360_app/features/car_hire/data/car_hire_api.dart';
import 'package:vero360_app/features/car_hire/data/car_hire_facebook.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_company_models.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_company_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/theme/car_hire_theme.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_policy_models.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_company_widgets.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_listing_policies_editor.dart';
import 'package:vero360_app/utils/formatters.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';

/// Three quiet steps for putting a car on the road: identify it, attach the
/// paperwork, then add photos and publish. The backend pairs a GPS tracker on
/// save, so there is no hardware screen to fake.
class CarHireCompanyAddVehiclePage extends ConsumerStatefulWidget {
  const CarHireCompanyAddVehiclePage({super.key, required this.access});

  final CompanyAccess access;

  @override
  ConsumerState<CarHireCompanyAddVehiclePage> createState() =>
      _CarHireCompanyAddVehiclePageState();
}

class _CarHireCompanyAddVehiclePageState
    extends ConsumerState<CarHireCompanyAddVehiclePage> {
  static const _maxPhotos = 6;

  static const _bodyTypes = <(String, String)>[
    ('SEDAN', 'Sedan'),
    ('SUV', 'SUV'),
    ('HATCHBACK', 'Hatchback'),
    ('EXECUTIVE', 'Executive'),
    ('PICKUP', 'Pickup'),
    ('VAN', 'Van'),
  ];

  static const _transmissions = <(String, String)>[
    ('AUTOMATIC', 'Automatic'),
    ('MANUAL', 'Manual'),
  ];

  static const _fuels = <(String, String)>[
    ('PETROL', 'Petrol'),
    ('DIESEL', 'Diesel'),
    ('HYBRID', 'Hybrid'),
    ('ELECTRIC', 'Electric'),
  ];

  static const _stepTitles = <String>[
    'Vehicle & rates',
    'Insurance',
    'Photos & publish',
  ];

  final _formKey = GlobalKey<FormState>();
  final _plate = TextEditingController();
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _color = TextEditingController();
  final _year = TextEditingController(text: '${DateTime.now().year}');
  final _seats = TextEditingController(text: '5');
  final _rate = TextEditingController();
  final _deposit = TextEditingController();
  final _minDays = TextEditingController(text: '1');
  final _maxDays = TextEditingController();
  final _trackerId = TextEditingController();
  final _trackerPhone = TextEditingController();
  final _insuranceRef = TextEditingController();

  final _picker = ImagePicker();

  int _step = 0;
  String _bodyType = 'SEDAN';
  String _transmission = 'AUTOMATIC';
  String _fuelType = 'PETROL';
  String? _branchId;
  DateTime? _insuranceExpiry;
  final List<String> _photos = <String>[];
  bool _uploadingPhoto = false;
  bool _saving = false;
  bool _postToFacebook = true;
  String? _saveError;
  CarHireListingPolicies _listingPolicies = const CarHireListingPolicies();

  String get _operatorId => widget.access.usable.first.operatorId;

  @override
  void dispose() {
    _plate.dispose();
    _make.dispose();
    _model.dispose();
    _color.dispose();
    _year.dispose();
    _seats.dispose();
    _rate.dispose();
    _deposit.dispose();
    _minDays.dispose();
    _maxDays.dispose();
    _trackerId.dispose();
    _trackerPhone.dispose();
    _insuranceRef.dispose();
    super.dispose();
  }

  String? _validateStep() {
    if (_step == 0) {
      if (_plate.text.trim().length < 2) {
        return 'Enter the registration plate.';
      }
      if (_make.text.trim().isEmpty) return 'Enter the make.';
      if (_model.text.trim().isEmpty) return 'Enter the model.';
      final year = int.tryParse(_year.text.trim());
      final now = DateTime.now().year;
      if (year == null || year < 1980 || year > now + 1) {
        return 'Enter a year between 1980 and ${now + 1}.';
      }
      final seats = int.tryParse(_seats.text.trim());
      if (seats == null || seats < 1 || seats > 30) {
        return 'Seats must be between 1 and 30.';
      }
      final rate = parseMwkInput(_rate.text);
      if (rate == null || rate <= 0) return 'Enter a daily rate.';
      final days = int.tryParse(_minDays.text.trim());
      if (days == null || days < 1) return 'Minimum days must be at least 1.';
      final maxDays = _maxDays.text.trim().isEmpty
          ? null
          : int.tryParse(_maxDays.text.trim());
      if (maxDays != null && maxDays < days) {
        return 'Maximum days cannot be shorter than the minimum.';
      }
      return null;
    }
    if (_step == 1) {
      final expiry = _insuranceExpiry;
      if (expiry != null && expiry.isBefore(DateTime.now())) {
        return 'The insurance expiry date is in the past.';
      }
      return null;
    }
    if (_photos.isEmpty) {
      return 'Add at least one photo to publish. Use “Save as draft” to '
          'publish later.';
    }
    return null;
  }

  void _next() {
    final problem = _validateStep();
    if (problem != null) {
      setState(() => _saveError = problem);
      return;
    }
    setState(() {
      _saveError = null;
      _step = (_step + 1).clamp(0, 2);
    });
  }

  void _back() {
    if (_step == 0) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _saveError = null;
      _step -= 1;
    });
  }

  Future<void> _pickPhotos() async {
    if (_uploadingPhoto) return;
    final remaining = _maxPhotos - _photos.length;
    if (remaining <= 0) return;
    try {
      final chosen = await _picker.pickMultiImage(
        imageQuality: 72,
        maxWidth: 1600,
      );
      if (chosen.isEmpty) return;
      setState(() => _uploadingPhoto = true);
      final api = ref.read(carHireApiProvider);
      for (final file in chosen.take(remaining)) {
        final bytes = await file.readAsBytes();
        final url = await api.uploadPhoto(
          bytes,
          filename: file.name.trim().isEmpty ? 'vehicle.jpg' : file.name,
        );
        if (!mounted) return;
        setState(() => _photos.add(url));
      }
    } catch (error) {
      if (!mounted) return;
      showCompanySnack(
        context,
        error is CarHireApiException
            ? error.message
            : 'The photo could not be added.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _pickInsuranceExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 10),
      initialDate: _insuranceExpiry ?? now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _insuranceExpiry = picked);
  }

  Future<void> _save({required bool publish}) async {
    if (_saving || _uploadingPhoto) return;
    if (publish) {
      final problem = _validateStep();
      if (problem != null) {
        setState(() => _saveError = problem);
        return;
      }
    } else {
      if (_plate.text.trim().length < 2 ||
          _make.text.trim().isEmpty ||
          _model.text.trim().isEmpty) {
        setState(() {
          _step = 0;
          _saveError = 'A draft still needs a plate, make and model.';
        });
        return;
      }
    }

    setState(() {
      _saving = true;
      _saveError = null;
    });

    final year = int.tryParse(_year.text.trim()) ?? DateTime.now().year;
    final seats = int.tryParse(_seats.text.trim());
    final rate = parseMwkInput(_rate.text) ?? 0;
    final deposit = parseMwkInput(_deposit.text);
    final minDays = int.tryParse(_minDays.text.trim());
    final maxDays = int.tryParse(_maxDays.text.trim());

    final payload = <String, dynamic>{
      'make': _make.text.trim(),
      'model': _model.text.trim(),
      'year': year,
      'licensePlate': _plate.text.trim().toUpperCase(),
      'color': _color.text.trim().isEmpty ? 'Unspecified' : _color.text.trim(),
      'dailyRate': rate,
      'seats': seats ?? 5,
      'transmission': _transmission,
      'fuelType': _fuelType,
      'bodyType': _bodyType,
      'currency': 'MWK',
      'operatorId': _operatorId,
      'isAvailable': publish,
      'listingStatus': publish ? 'PUBLISHED' : 'DRAFT',
      'images': _photos,
      if (_photos.isNotEmpty) 'imageUrl': _photos.first,
      'depositAmount': ?deposit,
      'minRentalDays': ?minDays,
      'maxRentalDays': ?maxDays,
      if (_branchId != null) 'locationId': _branchId,
      if (_trackerId.text.trim().isNotEmpty)
        'trackerUniqueId': _trackerId.text.trim(),
      if (_trackerPhone.text.trim().isNotEmpty)
        'trackerPhone': _trackerPhone.text.trim(),
      'listingPolicies': _listingPolicies.toPayload(),
    };

    try {
      final api = ref.read(carHireApiProvider);
      final created = await api.createCompanyCar(payload);
      if (created == null) {
        throw const CarHireApiException(
          message: 'The vehicle was saved but the server returned no record.',
        );
      }

      // Documents need a car id, so they are attached right after creation.
      final documentFailures = <String>[];
      final reference = _insuranceRef.text.trim();
      if (reference.isNotEmpty || _insuranceExpiry != null) {
        try {
          await api.addCarDocument(
            created.id,
            type: 'INSURANCE',
            fileReference: reference.isEmpty ? 'pending-upload' : reference,
            referenceNumber: reference.isEmpty ? null : reference,
            expiresAt: _insuranceExpiry,
          );
        } catch (_) {
          documentFailures.add('insurance document');
        }
      }

      await CarHireFacebookQueue.syncListing(
        unit: created,
        operatorId: created.operatorId ?? _operatorId,
        companyName: widget.access.usable.first.companyName,
        postToFacebook: _postToFacebook,
      );

      ref.invalidate(companyFleetProvider);
      ref.invalidate(companyAnalyticsProvider);
      ref.invalidate(companyComplianceProvider);
      if (!mounted) return;

      showCompanySnack(
        context,
        documentFailures.isEmpty
            ? '${created.car.title} is ${publish ? 'live' : 'saved as a draft'}.'
            : '${created.car.title} saved. Could not attach the '
                  '${documentFailures.join(', ')}.',
        error: documentFailures.isNotEmpty,
      );
      Navigator.of(context).pop(created);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = error is CarHireApiException
            ? error.message
            : 'The vehicle could not be saved. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CarHirePalette.background,
      appBar: carHireAppBar(title: 'Add vehicle'),
      body: Column(
        children: [
          _StepHeader(
            step: _step,
            titles: _stepTitles,
            companyName: widget.access.usable.first.companyName,
          ),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  ...switch (_step) {
                    0 => _stepVehicle(),
                    1 => _stepInsurance(),
                    _ => _stepPhotos(),
                  },
                  if (_saveError != null) ...[
                    const SizedBox(height: 12),
                    _ErrorNote(message: _saveError!),
                  ],
                ],
              ),
            ),
          ),
          _StepFooter(
            step: _step,
            saving: _saving,
            uploading: _uploadingPhoto,
            onBack: _back,
            onNext: _next,
            onPublish: () => _save(publish: true),
            onDraft: () => _save(publish: false),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Step 1
  // -------------------------------------------------------------------------

  List<Widget> _stepVehicle() {
    return [
      _FormCard(
        icon: Icons.electric_car_outlined,
        title: 'Identify the car',
        trailing: 'Plate is never public',
        children: [
          _LabeledField(
            label: 'Registration plate',
            child: TextFormField(
              controller: _plate,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'\n')),
                LengthLimitingTextInputFormatter(16),
              ],
              decoration: carHireInputDecoration(
                hint: 'e.g. MW 1234',
                helper: 'Only your company sees the registration.',
              ),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                fontSize: 15,
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _LabeledField(
                  label: 'Make',
                  child: TextFormField(
                    controller: _make,
                    textCapitalization: TextCapitalization.words,
                    decoration: carHireInputDecoration(hint: 'Toyota'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _LabeledField(
                  label: 'Model',
                  child: TextFormField(
                    controller: _model,
                    textCapitalization: TextCapitalization.words,
                    decoration: carHireInputDecoration(hint: 'Corolla'),
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _LabeledField(
                  label: 'Year',
                  child: TextFormField(
                    controller: _year,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    decoration: carHireInputDecoration(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _LabeledField(
                  label: 'Colour',
                  child: TextFormField(
                    controller: _color,
                    textCapitalization: TextCapitalization.words,
                    decoration: carHireInputDecoration(hint: 'Pearl white'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      const SizedBox(height: 12),
      _FormCard(
        icon: Icons.tune_rounded,
        title: 'Specs',
        children: [
          _ChipSelector(
            label: 'Category',
            options: _bodyTypes,
            value: _bodyType,
            onChanged: (value) => setState(() => _bodyType = value),
          ),
          _ChipSelector(
            label: 'Transmission',
            options: _transmissions,
            value: _transmission,
            onChanged: (value) => setState(() => _transmission = value),
          ),
          _ChipSelector(
            label: 'Fuel',
            options: _fuels,
            value: _fuelType,
            onChanged: (value) => setState(() => _fuelType = value),
          ),
          _LabeledField(
            label: 'Seats',
            child: TextFormField(
              controller: _seats,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              decoration: carHireInputDecoration(),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _FormCard(
        icon: Icons.payments_outlined,
        title: 'Rates',
        trailing: 'Renter sees this',
        children: [
          Row(
            children: [
              Expanded(
                child: _LabeledField(
                  label: 'Daily rate',
                  child: TextFormField(
                    controller: _rate,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: carHireInputDecoration(
                      hint: '85000',
                      helper: 'Whole MWK per day',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _LabeledField(
                  label: 'Deposit',
                  child: TextFormField(
                    controller: _deposit,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: carHireInputDecoration(hint: 'Optional'),
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _LabeledField(
                  label: 'Min days',
                  child: TextFormField(
                    controller: _minDays,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: carHireInputDecoration(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _LabeledField(
                  label: 'Max days',
                  child: TextFormField(
                    controller: _maxDays,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: carHireInputDecoration(hint: 'No limit'),
                  ),
                ),
              ),
            ],
          ),
          _BranchPicker(
            operatorId: _operatorId,
            value: _branchId,
            onChanged: (value) => setState(() => _branchId = value),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _FormCard(
        icon: Icons.rule_folder_outlined,
        title: 'Rental rules',
        trailing: 'Vero + yours',
        children: [
          CarHireListingPoliciesEditor(
            value: _listingPolicies,
            onChanged: (next) => setState(() => _listingPolicies = next),
          ),
        ],
      ),
    ];
  }

  // -------------------------------------------------------------------------
  // Step 2
  // -------------------------------------------------------------------------

  List<Widget> _stepInsurance() {
    return [
      _FormCard(
        icon: Icons.verified_user_outlined,
        title: 'Insurance cover',
        trailing: 'Optional now',
        children: [
          const Text(
            'Attached to this vehicle for review. You can add the '
            'registration and roadworthiness documents later from the '
            'vehicle page.',
            style: CarHireType.bodySmall,
          ),
          const SizedBox(height: 12),
          _LabeledField(
            label: 'Policy / cover reference',
            child: TextFormField(
              controller: _insuranceRef,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                LengthLimitingTextInputFormatter(120),
                FilteringTextInputFormatter.deny(RegExp(r'\n')),
              ],
              decoration: carHireInputDecoration(hint: 'e.g. AZ-4471902'),
            ),
          ),
          _LabeledField(
            label: 'Cover expires',
            child: _DateField(
              value: _insuranceExpiry,
              placeholder: 'No expiry set',
              onTap: _pickInsuranceExpiry,
              onClear: _insuranceExpiry == null
                  ? null
                  : () => setState(() => _insuranceExpiry = null),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: CarHirePalette.surfaceLow,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 14,
                  color: CarHirePalette.muted,
                ),
                SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Documents are private: renters only ever see that the '
                    'car is approved.',
                    style: CarHireType.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      const _QuietHint(
        icon: Icons.schedule_rounded,
        text:
            'A car can be published while a document is still under '
            'review. Renters see the approval state, never the paperwork.',
      ),
    ];
  }

  // -------------------------------------------------------------------------
  // Step 3
  // -------------------------------------------------------------------------

  List<Widget> _stepPhotos() {
    return [
      _FormCard(
        icon: Icons.photo_library_outlined,
        title: 'Photos',
        trailing: '${_photos.length}/$_maxPhotos',
        children: [
          const Text(
            'Front three-quarter and cabin shots help renters decide. '
            'At least one is required to publish.',
            style: CarHireType.bodySmall,
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.15,
            children: [
              for (var i = 0; i < _photos.length; i++)
                _PhotoTile(
                  url: _photos[i],
                  label: i == 0 ? 'Cover' : 'Photo ${i + 1}',
                  onRemove: () => setState(() => _photos.removeAt(i)),
                ),
              if (_photos.length < _maxPhotos)
                _AddPhotoTile(busy: _uploadingPhoto, onTap: _pickPhotos),
            ],
          ),
        ],
      ),
      const SizedBox(height: 12),
      _FormCard(
        icon: Icons.sensors_rounded,
        title: 'GPS & key pairing',
        trailing: 'Automatic',
        children: [
          const Text(
            'A tracker is created and linked when you save. Add the hardware '
            'serial only if you already have a device to pair.',
            style: CarHireType.bodySmall,
          ),
          const SizedBox(height: 12),
          _LabeledField(
            label: 'Tracker serial (optional)',
            child: TextFormField(
              controller: _trackerId,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                LengthLimitingTextInputFormatter(64),
                FilteringTextInputFormatter.deny(RegExp(r'\n')),
              ],
              decoration: carHireInputDecoration(hint: 'e.g. OBD-8820'),
            ),
          ),
          _LabeledField(
            label: 'Tracker SIM phone (optional)',
            child: TextFormField(
              controller: _trackerPhone,
              keyboardType: TextInputType.phone,
              decoration: carHireInputDecoration(hint: '+265 …'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _FormCard(
        icon: Icons.public_rounded,
        title: 'Share',
        trailing: 'Vero360 Page',
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _postToFacebook,
            activeThumbColor: CarHirePalette.accent,
            secondary: const FacebookLogoMark(size: 22),
            title: const Text(
              'Also post on Facebook',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            subtitle: Text(
              'Share on the Vero360 Facebook Page once this car is live.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            onChanged: _saving
                ? null
                : (v) => setState(() => _postToFacebook = v),
          ),
          if (_postToFacebook) ...[
            const SizedBox(height: 4),
            const FacebookShareHint(
              message:
                  'When you publish, we also share this car on the Vero360 Facebook Page so more renters can find it.',
            ),
          ],
        ],
      ),
      const SizedBox(height: 12),
      _ReviewCard(
        plate: _plate.text,
        title: [
          _make.text,
          _model.text,
        ].where((part) => part.trim().isNotEmpty).join(' '),
        rate: parseMwkInput(_rate.text) ?? 0,
        photos: _photos.length,
      ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Step chrome
// ---------------------------------------------------------------------------

class _StepHeader extends StatelessWidget {
  const _StepHeader({
    required this.step,
    required this.titles,
    required this.companyName,
  });

  final int step;
  final List<String> titles;
  final String companyName;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: CarHirePalette.surfaceLow,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'STEP ${step + 1} OF ${titles.length}',
                      style: CarHireType.overline.copyWith(
                        color: CarHirePalette.accent,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text('Add vehicle to fleet', style: CarHireType.title),
                  ],
                ),
              ),
              CarHirePill(
                label: companyName,
                background: CarHirePalette.accentSoft,
                foreground: CarHirePalette.onAccentSoft,
                fontSize: 10,
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < titles.length; i++) ...[
                Expanded(
                  child: AnimatedContainer(
                    duration: CarHireShape.fast,
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= step
                          ? CarHirePalette.accent
                          : CarHirePalette.surfaceHigh,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                if (i != titles.length - 1) const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              for (var i = 0; i < titles.length; i++)
                Expanded(
                  child: Text(
                    '${i + 1}. ${titles[i]}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: i == 0
                        ? TextAlign.start
                        : i == titles.length - 1
                        ? TextAlign.end
                        : TextAlign.center,
                    style: CarHireType.labelSmall.copyWith(
                      fontSize: 10,
                      color: i == step
                          ? CarHirePalette.onSurface
                          : CarHirePalette.muted,
                      fontWeight: i == step ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepFooter extends StatelessWidget {
  const _StepFooter({
    required this.step,
    required this.saving,
    required this.uploading,
    required this.onBack,
    required this.onNext,
    required this.onPublish,
    required this.onDraft,
  });

  final int step;
  final bool saving;
  final bool uploading;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onPublish;
  final VoidCallback onDraft;

  @override
  Widget build(BuildContext context) {
    final busy = saving || uploading;
    return Container(
      decoration: const BoxDecoration(
        color: CarHirePalette.surface,
        border: Border(top: BorderSide(color: CarHirePalette.hairline)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.paddingOf(context).bottom + 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (step < 2)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: busy ? null : onNext,
                style: carHirePrimaryButton(),
                child: const Text('Continue'),
              ),
            )
          else ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : onPublish,
                style: carHirePrimaryButton(),
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.arrow_forward_rounded, size: 18),
                label: Text(
                  uploading
                      ? 'Uploading photos…'
                      : saving
                      ? 'Saving…'
                      : 'Save & publish to fleet',
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: busy ? null : onDraft,
                style: carHireGhostButton(),
                icon: const Icon(Icons.save_outlined, size: 17),
                label: const Text('Save as draft / in prep'),
              ),
            ),
          ],
          if (step > 0) ...[
            const SizedBox(height: 4),
            TextButton(
              onPressed: busy ? null : onBack,
              style: TextButton.styleFrom(
                foregroundColor: CarHirePalette.muted,
                minimumSize: const Size.fromHeight(36),
              ),
              child: const Text(
                'Back',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small building blocks
// ---------------------------------------------------------------------------

class _FormCard extends StatelessWidget {
  const _FormCard({
    required this.icon,
    required this.title,
    required this.children,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return CarHireSurface(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      radius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: CarHirePalette.accent),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  style: CarHireType.title.copyWith(fontSize: 14),
                ),
              ),
              if (trailing != null)
                Text(
                  trailing!,
                  style: CarHireType.labelSmall.copyWith(fontSize: 10),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 5),
            child: Text(label, style: CarHireType.label),
          ),
          child,
        ],
      ),
    );
  }
}

class _ChipSelector extends StatelessWidget {
  const _ChipSelector({
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<(String, String)> options;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Text(label, style: CarHireType.label),
          ),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final (wire, text) in options)
                _ChoiceChip(
                  label: text,
                  selected: value == wire,
                  onTap: () => onChanged(wire),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: CarHireShape.fast,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? CarHirePalette.primary : CarHirePalette.surfaceLow,
          borderRadius: BorderRadius.circular(CarHireShape.pillRadius),
          border: Border.all(
            color: selected ? CarHirePalette.primary : CarHirePalette.hairline,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? Colors.white : CarHirePalette.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _BranchPicker extends ConsumerWidget {
  const _BranchPicker({
    required this.operatorId,
    required this.value,
    required this.onChanged,
  });

  final String operatorId;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branches = ref.watch(companyBranchesProvider(operatorId));

    Widget content;
    final rows =
        branches.value
            ?.where((branch) => branch.isActive)
            .toList(growable: false) ??
        const <CompanyBranch>[];
    if (branches.isLoading && !branches.hasValue) {
      content = const Text('Loading branches…', style: CarHireType.bodySmall);
    } else if (branches.hasError && !branches.hasValue) {
      content = Text(
        'Branches could not be loaded. Add the car and set the branch later.',
        style: CarHireType.bodySmall.copyWith(color: CarHirePalette.error),
      );
    } else if (rows.isEmpty) {
      content = const Text(
        'No branches yet. Add one on the web workspace to group cars by hub.',
        style: CarHireType.bodySmall,
      );
    } else {
      content = Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [
          _ChoiceChip(
            label: 'No branch',
            selected: value == null,
            onTap: () => onChanged(null),
          ),
          for (final branch in rows)
            _ChoiceChip(
              label: branch.name,
              selected: value == branch.id,
              onTap: () => onChanged(branch.id),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 2, bottom: 6),
          child: Text('Pickup branch', style: CarHireType.label),
        ),
        content,
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.value,
    required this.placeholder,
    required this.onTap,
    this.onClear,
  });

  final DateTime? value;
  final String placeholder;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CarHirePalette.surfaceLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: CarHirePalette.hairline),
          ),
          child: Row(
            children: [
              Icon(
                Icons.event_outlined,
                size: 16,
                color: value == null
                    ? CarHirePalette.muted
                    : CarHirePalette.accent,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  value == null
                      ? placeholder
                      : CarHireFormatters.formatDate(value!),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: value == null
                        ? FontWeight.w500
                        : FontWeight.w700,
                    color: value == null
                        ? CarHirePalette.muted
                        : CarHirePalette.onSurface,
                  ),
                ),
              ),
              if (onClear != null)
                GestureDetector(
                  onTap: onClear,
                  child: const Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: CarHirePalette.muted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.url,
    required this.label,
    required this.onRemove,
  });

  final String url;
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ResilientCachedNetworkImage(
            url: url,
            fit: BoxFit.cover,
            memCacheWidth: 400,
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: CarHirePalette.primary.withValues(alpha: 0.55),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: CarHirePalette.primary.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 13,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CarHirePalette.surfaceLow,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: CarHirePalette.accent,
                ),
              )
            else
              const Icon(
                Icons.add_a_photo_outlined,
                size: 21,
                color: CarHirePalette.accent,
              ),
            const SizedBox(height: 5),
            Text(
              busy ? 'Uploading' : 'Add photo',
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: CarHirePalette.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.plate,
    required this.title,
    required this.rate,
    required this.photos,
  });

  final String plate;
  final String title;
  final double rate;
  final int photos;

  @override
  Widget build(BuildContext context) {
    final car = title.trim().isEmpty ? 'New vehicle' : title.trim();
    return CarHireSurface(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      radius: 16,
      color: CarHirePalette.accentPale,
      borderColor: CarHirePalette.accentSoft,
      child: Row(
        children: [
          const Icon(
            Icons.fact_check_outlined,
            size: 18,
            color: CarHirePalette.onAccentSoft,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  car,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CarHireType.subtitle.copyWith(fontSize: 13.5),
                ),
                Text(
                  [
                    if (plate.trim().isNotEmpty) plate.trim().toUpperCase(),
                    if (rate > 0) '${companyMoney(rate)} / day',
                    photos == 1 ? '1 photo' : '$photos photos',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CarHireType.bodySmall.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuietHint extends StatelessWidget {
  const _QuietHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: CarHirePalette.surfaceLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: CarHirePalette.muted),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: CarHireType.bodySmall)),
        ],
      ),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: CarHirePalette.errorSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 16,
            color: CarHirePalette.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: CarHireType.bodySmall.copyWith(
                color: CarHirePalette.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
