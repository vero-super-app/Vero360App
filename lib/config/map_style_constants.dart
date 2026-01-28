import 'package:flutter/services.dart';

class MapStyleConstants {
  static String? _mapStyle;

  /// Load map style from assets
  static Future<String> loadMapStyle() async {
    if (_mapStyle != null) return _mapStyle!;

    try {
      _mapStyle = await rootBundle.loadString('assets/style/map_style.txt');
      return _mapStyle!;
    } catch (e) {
      print('[MapStyleConstants] Error loading map style: $e');
      return '';
    }
  }

  /// Get the cached map style (must call loadMapStyle() first)
  static String get mapStyle => _mapStyle ?? '';

  /// Check if map style is loaded
  static bool get isLoaded => _mapStyle != null;
}
