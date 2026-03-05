import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/GernalServices/driver_service.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/features/car_rental/utils/car_rental_colors.dart';

class EditTaxiScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> taxi;

  const EditTaxiScreen({
    required this.taxi,
    super.key,
  });

  @override
  ConsumerState<EditTaxiScreen> createState() => _EditTaxiScreenState();
}

class _EditTaxiScreenState extends ConsumerState<EditTaxiScreen> {
  final _formKey = GlobalKey<FormState>();
  final _driverService = DriverService();
  bool _isLoading = false;
  bool _isVerified = false;
  String? _verificationStatus;

  // Form fields
  late String _selectedTaxiClass;
  late final _makeController = TextEditingController(text: widget.taxi['make']);
  late final _modelController =
      TextEditingController(text: widget.taxi['model']);
  late final _yearController =
      TextEditingController(text: '${widget.taxi['year']}');
  late final _licensePlateController =
      TextEditingController(text: widget.taxi['licensePlate']);
  late final _colorController =
      TextEditingController(text: widget.taxi['color'] ?? '');
  late final _seatsController =
      TextEditingController(text: '${widget.taxi['seats']}');
  late final _registrationNumberController =
      TextEditingController(text: widget.taxi['registrationNumber'] ?? '');
  late final _registrationExpiryController = TextEditingController(
      text: widget.taxi['registrationExpiry'] != null
          ? (widget.taxi['registrationExpiry'] as String).split('T')[0]
          : '');
  late final List<String> _selectedFeatures;

  final List<String> _availableFeatures = [
    'AC',
    'WiFi',
    'Phone Charger',
    'USB Ports',
    'Water',
    'Tissues',
  ];

  @override
  void initState() {
    super.initState();
    _selectedTaxiClass = widget.taxi['taxiClass'] ?? 'STANDARD';

    // Parse existing features
    final existingFeatures = widget.taxi['features'];
    if (existingFeatures is List) {
      _selectedFeatures = List<String>.from(existingFeatures);
    } else if (existingFeatures is String) {
      try {
        // Try parsing as JSON if it's a string
        _selectedFeatures = existingFeatures.isEmpty ? [] : [existingFeatures];
      } catch (_) {
        _selectedFeatures = [];
      }
    } else {
      _selectedFeatures = [];
    }

    _validateAndAutoVerify();
  }

  @override
  void dispose() {
    _makeController.dispose();
    _modelController.dispose();
    _yearController.dispose();
    _licensePlateController.dispose();
    _colorController.dispose();
    _seatsController.dispose();
    _registrationNumberController.dispose();
    _registrationExpiryController.dispose();
    super.dispose();
  }

  void _validateAndAutoVerify() {
    if (!_formKey.currentState!.validate()) {
      setState(() => _isVerified = false);
      return;
    }

    // Auto-verification checks
    final checks = <String, bool>{};

    // Make and Model validation
    checks['has_make'] = _makeController.text.isNotEmpty;
    checks['has_model'] = _modelController.text.isNotEmpty;

    // Year validation (must be recent)
    final year = int.tryParse(_yearController.text) ?? 0;
    final currentYear = DateTime.now().year;
    checks['valid_year'] = year >= (currentYear - 25) && year <= currentYear;

    // License plate format validation
    checks['valid_license_plate'] = _licensePlateController.text.length >= 5;

    // Seats validation
    final seats = int.tryParse(_seatsController.text) ?? 0;
    checks['valid_seats'] = seats >= 1 && seats <= 8;

    // Color validation
    checks['has_color'] = _colorController.text.isNotEmpty;

    // Registration number (optional but good to have)
    checks['has_registration'] = _registrationNumberController.text.isNotEmpty;

    // Features (good to have at least 2)
    checks['has_features'] = _selectedFeatures.isNotEmpty;

    // Calculate score
    final passedChecks = checks.values.where((v) => v).length;
    final totalChecks = checks.length;
    final score = (passedChecks / totalChecks) * 100;

    // Auto-verify if score >= 80%
    final isVerified = score >= 80;

    setState(() {
      _isVerified = isVerified;
      _verificationStatus = isVerified
          ? 'All checks passed - Taxi details complete'
          : 'Complete more fields for verification';
    });
  }

  Future<void> _submitTaxi() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final updateData = {
        'taxiClass': _selectedTaxiClass,
        'make': _makeController.text.trim(),
        'model': _modelController.text.trim(),
        'color': _colorController.text.trim(),
        'registrationNumber': _registrationNumberController.text.trim(),
        'features': _selectedFeatures,
      };

      await _driverService.updateTaxi(widget.taxi['id'], updateData);

      // Verify taxi details after update
      if (mounted) {
        try {
          final verificationResult =
              await _driverService.verifyTaxiDetails(widget.taxi['id']);
          final isVerified = verificationResult['verified'] as bool? ?? false;

          if (mounted) {
            final successMessage = isVerified
                ? 'Taxi updated and verified successfully'
                : 'Taxi updated. Some details need attention for verification.';
            ToastHelper.showCustomToast(
              context,
              successMessage,
              isSuccess: true,
              errorMessage: '',
            );
            Navigator.pop(context, true);
          }
        } catch (e) {
          if (mounted) {
            ToastHelper.showCustomToast(
              context,
              'Taxi updated but verification check failed',
              isSuccess: true,
              errorMessage: '',
            );
            Navigator.pop(context, true);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ToastHelper.showCustomToast(
          context,
          'Error updating taxi: $e',
          isSuccess: false,
          errorMessage: '',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _registrationExpiryController.text.isNotEmpty
          ? DateTime.parse(_registrationExpiryController.text)
          : DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) {
      _registrationExpiryController.text = picked.toString().split(' ')[0];
      _validateAndAutoVerify();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CarRentalColors.background,
      appBar: AppBar(
        backgroundColor: CarRentalColors.brandOrange,
        title: const Text('Edit Taxi'),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          onChanged: _validateAndAutoVerify,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Verification status card
              if (_verificationStatus != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _isVerified
                        ? CarRentalColors.successLight
                        : CarRentalColors.warningLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _isVerified
                          ? CarRentalColors.success
                          : CarRentalColors.warning,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isVerified ? Icons.check_circle : Icons.info,
                        color: _isVerified
                            ? CarRentalColors.success
                            : CarRentalColors.warning,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _verificationStatus!,
                          style: TextStyle(
                            fontSize: 13,
                            color: _isVerified
                                ? CarRentalColors.success
                                : CarRentalColors.warning,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),

              // Vehicle Information Section
              Text(
                'Vehicle Information',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: CarRentalColors.title,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 12),

              // Taxi Class
              DropdownButtonFormField<String>(
                initialValue: _selectedTaxiClass,
                decoration: InputDecoration(
                  labelText: 'Taxi Class',
                  hintText: 'Select taxi class',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 'BIKE', child: Text('Bike')),
                  DropdownMenuItem(value: 'STANDARD', child: Text('Standard')),
                  DropdownMenuItem(
                      value: 'EXECUTIVE', child: Text('Executive')),
                ]
                    .map((e) => DropdownMenuItem(
                          value: e.value,
                          child: e.child,
                        ))
                    .toList(),
                onChanged: (value) {
                  setState(() => _selectedTaxiClass = value ?? 'STANDARD');
                  _validateAndAutoVerify();
                },
              ),
              const SizedBox(height: 16),

              // Make and Model Row
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _makeController,
                      decoration: InputDecoration(
                        labelText: 'Make*',
                        hintText: 'e.g., Toyota',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Color(0xFFE0E0E0)),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Required';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _modelController,
                      decoration: InputDecoration(
                        labelText: 'Model*',
                        hintText: 'e.g., Corolla',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Color(0xFFE0E0E0)),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Required';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Color
              TextFormField(
                controller: _colorController,
                decoration: InputDecoration(
                  labelText: 'Color*',
                  hintText: 'e.g., White',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Read-only Information Section
              Text(
                'Fixed Information',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: CarRentalColors.title,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 12),

              // Year (read-only)
              TextFormField(
                initialValue: '${widget.taxi['year']}',
                decoration: InputDecoration(
                  labelText: 'Year',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                ),
                readOnly: true,
              ),
              const SizedBox(height: 16),

              // Seats (read-only)
              TextFormField(
                initialValue: '${widget.taxi['seats']}',
                decoration: InputDecoration(
                  labelText: 'Seats',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                ),
                readOnly: true,
              ),
              const SizedBox(height: 16),

              // License Plate (read-only)
              TextFormField(
                initialValue: widget.taxi['licensePlate'],
                decoration: InputDecoration(
                  labelText: 'License Plate',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                ),
                readOnly: true,
              ),
              const SizedBox(height: 20),

              // Registration Information Section
              Text(
                'Registration Details',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: CarRentalColors.title,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 12),

              // Registration Number
              TextFormField(
                controller: _registrationNumberController,
                decoration: InputDecoration(
                  labelText: 'Registration Number',
                  hintText: 'Optional',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Registration Expiry
              TextFormField(
                controller: _registrationExpiryController,
                decoration: InputDecoration(
                  labelText: 'Registration Expiry',
                  hintText: 'YYYY-MM-DD',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.calendar_today),
                    onPressed: () => _selectDate(context),
                  ),
                ),
                readOnly: true,
              ),
              const SizedBox(height: 20),

              // Features Section
              Text(
                'Vehicle Features',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: CarRentalColors.title,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableFeatures.map((feature) {
                  final isSelected = _selectedFeatures.contains(feature);
                  return FilterChip(
                    label: Text(feature),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedFeatures.add(feature);
                        } else {
                          _selectedFeatures.remove(feature);
                        }
                      });
                      _validateAndAutoVerify();
                    },
                    backgroundColor: CarRentalColors.chip,
                    selectedColor: CarRentalColors.brandOrangeSoft,
                    labelStyle: TextStyle(
                      color: isSelected
                          ? CarRentalColors.brandOrange
                          : CarRentalColors.body,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                    side: BorderSide(
                      color: isSelected
                          ? CarRentalColors.brandOrange
                          : Colors.transparent,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // Submit Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitTaxi,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CarRentalColors.brandOrange,
                    disabledBackgroundColor: Colors.grey[400],
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Save Changes',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
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
}
