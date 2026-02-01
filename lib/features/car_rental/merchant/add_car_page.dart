import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/car_hire_provider.dart';
import 'package:vero360_app/dto/create_car_dto.dart';
import 'package:vero360_app/utils/validators.dart';
import 'package:vero360_app/utils/error_handler.dart';

class AddCarPage extends ConsumerStatefulWidget {
  const AddCarPage({Key? key}) : super(key: key);

  @override
  ConsumerState<AddCarPage> createState() => _AddCarPageState();
}

class _AddCarPageState extends ConsumerState<AddCarPage> {
  late GlobalKey<FormState> _formKey;
  late TextEditingController _makeController;
  late TextEditingController _modelController;
  late TextEditingController _yearController;
  late TextEditingController _licensePlateController;
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
    _makeController = TextEditingController();
    _modelController = TextEditingController();
    _yearController = TextEditingController();
    _licensePlateController = TextEditingController();
    _colorController = TextEditingController();
    _dailyRateController = TextEditingController();
    _descriptionController = TextEditingController();
    _seatsController = TextEditingController(text: '5');
    _selectedFuelType = 'Petrol';
  }

  @override
  void dispose() {
    _makeController.dispose();
    _modelController.dispose();
    _yearController.dispose();
    _licensePlateController.dispose();
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
      final carDto = CreateCarDto(
        make: _makeController.text,
        model: _modelController.text,
        year: int.parse(_yearController.text),
        licensePlate: _licensePlateController.text.toUpperCase(),
        color: _colorController.text,
        dailyRate: double.parse(_dailyRateController.text),
        description: _descriptionController.text,
        seats: int.parse(_seatsController.text),
        fuelType: _selectedFuelType,
      );

      final service = ref.read(carRentalServiceProvider);
      final newCar = await service.createCar(carDto);

      if (mounted) {
        // Refresh the cars list
        ref.refresh(myCarsFutureProvider);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Car added successfully'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.of(context).pop();
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
        title: const Text('Add New Car'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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

              // Year and License Plate
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _yearController,
                      decoration: InputDecoration(
                        labelText: 'Year',
                        hintText: '2023',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Required';
                        }
                        return CarHireValidators.validateYear(
                            int.tryParse(value));
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _licensePlateController,
                      decoration: InputDecoration(
                        labelText: 'License Plate',
                        hintText: 'ABC 123',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      validator: CarHireValidators.validateLicensePlate,
                      textCapitalization: TextCapitalization.characters,
                    ),
                  ),
                ],
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
                      value: _selectedFuelType,
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

              Text(
                'Description & Media',
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

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 48,
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
                      : const Text('Add Car'),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
