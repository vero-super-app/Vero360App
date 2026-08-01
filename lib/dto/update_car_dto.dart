class UpdateCarDto {
  final String? make;
  final String? model;
  final String? color;
  final double? dailyRate;
  final String? description;
  final int? seats;
  final String? fuelType;
  final String? bodyType;
  final List<String>? features;
  final bool? isAvailable;

  const UpdateCarDto({
    this.make,
    this.model,
    this.color,
    this.dailyRate,
    this.description,
    this.seats,
    this.fuelType,
    this.bodyType,
    this.features,
    this.isAvailable,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (make != null) json['make'] = make;
    if (model != null) json['model'] = model;
    if (color != null) json['color'] = color;
    if (dailyRate != null) json['dailyRate'] = dailyRate;
    if (description != null) json['description'] = description;
    if (seats != null) json['seats'] = seats;
    if (fuelType != null) json['fuelType'] = fuelType;
    if (bodyType != null) json['bodyType'] = bodyType;
    if (features != null) json['features'] = features;
    if (isAvailable != null) json['isAvailable'] = isAvailable;
    return json;
  }

  factory UpdateCarDto.fromJson(Map<String, dynamic> json) {
    return UpdateCarDto(
      make: json['make'],
      model: json['model'],
      color: json['color'],
      dailyRate: json['dailyRate'],
      description: json['description'],
      seats: json['seats'],
      fuelType: json['fuelType'],
      bodyType: json['bodyType'],
      features: json['features'] != null ? List<String>.from(json['features']) : null,
      isAvailable: json['isAvailable'],
    );
  }
}
