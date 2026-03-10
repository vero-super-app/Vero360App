import 'package:flutter/material.dart';
import 'package:vero360_app/GernalServices/driver_service.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/features/car_rental/utils/car_rental_colors.dart';

class CreateTaxiScreen extends StatefulWidget {
  const CreateTaxiScreen({super.key});

  @override
  State<CreateTaxiScreen> createState() => _CreateTaxiScreenState();
}

class _CreateTaxiScreenState extends State<CreateTaxiScreen> {
  final _formKey = GlobalKey<FormState>();
  final _driverService = DriverService();
  bool _isLoading = false;
  bool _isAutoVerified = false;
  String? _verificationStatus;

  // Form fields
  String? _selectedTaxiClass = 'STANDARD';
  final _makeController = TextEditingController();
  final _modelController = TextEditingController();
  final _yearController = TextEditingController();
  final _licensePlateController = TextEditingController();
  final _colorController = TextEditingController();
  final _seatsController = TextEditingController(text: '4');
  final _registrationNumberController = TextEditingController();
  final _registrationExpiryController = TextEditingController();
  final List<String> _selectedFeatures = [];

  final List<String> _availableFeatures = [
    'AC',
    'WiFi',
    'Phone Charger',
    'USB Ports',
    'Water',
    'Tissues',
  ];

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
      setState(() => _isAutoVerified = false);
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
      _isAutoVerified = isVerified;
      _verificationStatus = isVerified
          ? 'All checks passed - Ready for creation'
          : 'Complete more fields for auto-verification';
    });
  }

  Future<void> _submitTaxi() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final taxiData = {
        'taxiClass': _selectedTaxiClass,
        'make': _makeController.text.trim(),
        'model': _modelController.text.trim(),
        'year': int.parse(_yearController.text),
        'licensePlate': _licensePlateController.text.trim().toUpperCase(),
        'color': _colorController.text.trim(),
        'seats': int.parse(_seatsController.text),
        'registrationNumber': _registrationNumberController.text.trim(),
        'registrationExpiry': _registrationExpiryController.text.isNotEmpty
            ? _registrationExpiryController.text
            : null,
        'features': _selectedFeatures,
      };

      final createdTaxi = await _driverService.createTaxi(taxiData);
      final taxiId = createdTaxi['id'] as int?;

      // Auto-verify taxi details if creation was successful
      if (taxiId != null && mounted) {
        try {
          final verificationResult =
              await _driverService.verifyTaxiDetails(taxiId);
          final isVerified = verificationResult['verified'] as bool? ?? false;

          if (mounted) {
            final successMessage = isVerified
                ? 'Taxi created and verified successfully'
                : 'Taxi created. Some details need attention for verification.';
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
              'Taxi created but verification check failed: $e',
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
          'Error creating taxi: $e',
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
      initialDate: DateTime.now().add(const Duration(days: 365)),
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
        title: const Text('Add New Taxi'),
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
              // Auto-verification status card
              if (_verificationStatus != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _isAutoVerified
                        ? CarRentalColors.successLight
                        : CarRentalColors.warningLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _isAutoVerified
                          ? CarRentalColors.success
                          : CarRentalColors.warning,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isAutoVerified ? Icons.check_circle : Icons.info,
                        color: _isAutoVerified
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
                            color: _isAutoVerified
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
                  setState(() => _selectedTaxiClass = value);
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

              // Year and Seats Row
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _yearController,
                      decoration: InputDecoration(
                        labelText: 'Year*',
                        hintText: '2024',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Color(0xFFE0E0E0)),
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Required';
                        }
                        final year = int.tryParse(value);
                        if (year == null ||
                            year < 1990 ||
                            year > DateTime.now().year) {
                          return 'Invalid year';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _seatsController,
                      decoration: InputDecoration(
                        labelText: 'Seats*',
                        hintText: '4',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Color(0xFFE0E0E0)),
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Required';
                        }
                        final seats = int.tryParse(value);
                        if (seats == null || seats < 1 || seats > 8) {
                          return 'Invalid';
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

              // Registration Information Section
              Text(
                'Registration Details',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: CarRentalColors.title,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 12),

              // License Plate
              TextFormField(
                controller: _licensePlateController,
                decoration: InputDecoration(
                  labelText: 'License Plate*',
                  hintText: 'e.g., ABC123DEF',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                ),
                textCapitalization: TextCapitalization.characters,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Required';
                  }
                  if (value.length < 5) {
                    return 'Invalid format';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

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
                      : Text(
                          _isAutoVerified ? 'Create Taxi' : 'Create Taxi',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),

              // Helper text
              Center(
                child: Text(
                  'Complete all marked (*) fields to create your taxi',
                  style: TextStyle(
                    fontSize: 12,
                    color: CarRentalColors.body,
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
