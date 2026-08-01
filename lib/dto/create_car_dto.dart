class CreateCarDto {
  final String make;
  final String model;
  final int year;
  final String licensePlate;
  final String color;
  final double dailyRate;
  final String description;
  final int? seats;
  final String? fuelType;
  final String? bodyType;
  final List<String>? features;

  const CreateCarDto({
    required this.make,
    required this.model,
    required this.year,
    required this.licensePlate,
    required this.color,
    required this.dailyRate,
    required this.description,
    this.seats,
    this.fuelType,
    this.bodyType,
    this.features,
  });

  Map<String, dynamic> toJson() => {
        'make': make,
        'model': model,
        'year': year,
        'licensePlate': licensePlate,
        'color': color,
        'dailyRate': dailyRate,
        'description': description,
        'seats': seats ?? 5,
        'fuelType': fuelType ?? 'Petrol',
        'bodyType': bodyType,
        'features': features ?? [],
      };

  factory CreateCarDto.fromJson(Map<String, dynamic> json) {
    return CreateCarDto(
      make: json['make'] ?? '',
      model: json['model'] ?? '',
      year: json['year'] ?? 0,
      licensePlate: json['licensePlate'] ?? '',
      color: json['color'] ?? '',
      dailyRate: (json['dailyRate'] ?? 0).toDouble(),
      description: json['description'] ?? '',
      seats: json['seats'],
      fuelType: json['fuelType'],
      bodyType: json['bodyType'],
      features: List<String>.from(json['features'] ?? []),
    );
  }
}
