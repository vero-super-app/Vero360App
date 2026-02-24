import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/GeneralModels/car_model.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/car_hire_provider.dart';
import 'package:vero360_app/dto/update_car_dto.dart';
import 'package:vero360_app/utils/validators.dart';
import 'package:vero360_app/utils/error_handler.dart';

class EditCarPage extends ConsumerStatefulWidget {
  final int carId;
  final CarModel initialCar;

  const EditCarPage({
    super.key,
    required this.carId,
    required this.initialCar,
  });

  @override
  ConsumerState<EditCarPage> createState() => _EditCarPageState();
}

class _EditCarPageState extends ConsumerState<EditCarPage> {
  late GlobalKey<FormState> _formKey;
  late TextEditingController _makeController;
  late TextEditingController _modelController;
  late TextEditingController _colorController;
  late TextEditingController _dailyRateController;
  late TextEditingController _descriptionController;
  late TextEditingController _seatsController;

  String? _selectedFuelType;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _formKey = GlobalKey<FormState>();

    // Pre-fill with existing car data
    _makeController = TextEditingController(text: widget.initialCar.brand);
    _modelController = TextEditingController(text: widget.initialCar.model);
    _colorController =
        TextEditingController(text: widget.initialCar.color ?? '');
    _dailyRateController = TextEditingController(
      text: widget.initialCar.dailyRate.toStringAsFixed(0),
    );
    _descriptionController = TextEditingController(
      text: widget.initialCar.description ?? '',
    );
    _seatsController = TextEditingController(
      text: (widget.initialCar.seats ?? 5).toString(),
    );
    _selectedFuelType = widget.initialCar.fuelType ?? 'Petrol';
  }

  @override
  void dispose() {
    _makeController.dispose();
    _modelController.dispose();
    _colorController.dispose();
    _dailyRateController.dispose();
    _descriptionController.dispose();
    _seatsController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final updateDto = UpdateCarDto(
        make: _makeController.text,
        model: _modelController.text,
        color: _colorController.text,
        dailyRate: double.parse(_dailyRateController.text),
        description: _descriptionController.text,
        seats: int.parse(_seatsController.text),
        fuelType: _selectedFuelType,
      );

      final service = ref.read(carRentalServiceProvider);
      await service.updateCar(widget.carId, updateDto);

      if (mounted) {
        // Refresh the cars list
        ref.refresh(myCarsFutureProvider);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Car updated successfully'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.of(context).pop(true); // Return true to indicate success
      }
    } on Exception catch (e) {
      if (mounted) {
        CarHireErrorHandler.showErrorDialog(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Car'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section header: Basic Information
              Text(
                'Basic Information',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),

              // Make
              TextFormField(
                controller: _makeController,
                decoration: InputDecoration(
                  labelText: 'Car Make (Brand)',
                  hintText: 'e.g., Toyota',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                validator: CarHireValidators.validateMake,
              ),
              const SizedBox(height: 16),

              // Model
              TextFormField(
                controller: _modelController,
                decoration: InputDecoration(
                  labelText: 'Car Model',
                  hintText: 'e.g., Axio',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                validator: CarHireValidators.validateModel,
              ),
              const SizedBox(height: 16),

              // Color
              TextFormField(
                controller: _colorController,
                decoration: InputDecoration(
                  labelText: 'Color',
                  hintText: 'e.g., Silver',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                validator: CarHireValidators.validateColor,
              ),
              const SizedBox(height: 24),

              // Section header: Rental Settings
              Text(
                'Rental Settings',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),

              // Daily Rate
              TextFormField(
                controller: _dailyRateController,
                decoration: InputDecoration(
                  labelText: 'Daily Rate (MWK)',
                  hintText: '50000',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixText: 'MWK ',
                ),
                keyboardType: TextInputType.number,
                validator: CarHireValidators.validateDailyRate,
              ),
              const SizedBox(height: 16),

              // Seats and Fuel Type
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _seatsController,
                      decoration: InputDecoration(
                        labelText: 'Number of Seats',
                        hintText: '5',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Required';
                        }
                        return CarHireValidators.validateSeats(
                            int.tryParse(value));
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedFuelType,
                      decoration: InputDecoration(
                        labelText: 'Fuel Type',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      items: ['Petrol', 'Diesel', 'Electric', 'Hybrid']
                          .map((fuel) => DropdownMenuItem(
                                value: fuel,
                                child: Text(fuel),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setState(() => _selectedFuelType = value);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Section header: Description
              Text(
                'Description',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),

              // Description
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: 'Description',
                  hintText: 'Describe your car and features',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignLabelWithHint: true,
                ),
                maxLines: 5,
                validator: CarHireValidators.validateDescription,
              ),
              const SizedBox(height: 24),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _isLoading ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submitForm,
                      child: _isLoading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text('Save Changes'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
