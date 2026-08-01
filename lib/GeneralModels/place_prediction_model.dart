/// Model for place predictions/search results
class PlacePrediction {
  final String placeId;
  final String mainText;
  final String secondaryText;
  final String fullText;
  final List<dynamic> types;
  final double? latitude;
  final double? longitude;

  PlacePrediction({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
    required this.fullText,
    required this.types,
    this.latitude,
    this.longitude,
  });

  factory PlacePrediction.fromJson(Map<String, dynamic> json) {
    final structuredFormatting = json['structured_formatting'] as Map<String, dynamic>? ?? {};
    
    return PlacePrediction(
      placeId: json['place_id'] as String? ?? '',
      mainText: (structuredFormatting['main_text'] as String?) ?? '',
      secondaryText: (structuredFormatting['secondary_text'] as String?) ?? '',
      fullText: json['description'] as String? ?? '',
      types: (json['types'] as List<dynamic>?) ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
    'place_id': placeId,
    'main_text': mainText,
    'secondary_text': secondaryText,
    'full_text': fullText,
    'types': types,
    'latitude': latitude,
    'longitude': longitude,
  };

  @override
  String toString() => 'PlacePrediction($fullText)';
}
