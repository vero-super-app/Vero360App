// lib/providers/cart_service_provider.dart
/// Riverpod provider for CartService singleton
///
/// This ensures only ONE CartService instance is created and reused
/// throughout the entire app, reducing memory usage and maintaining
/// consistent state.
///
/// Usage:
///   final cartService = ref.watch(cartServiceProvider);
///   // or in non-Riverpod context:
///   final cartService = await CartServiceProvider.getInstance();
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/services/api_config.dart';
import 'package:vero360_app/services/cart_services.dart';

/// Singleton provider for CartService
/// Returns the same instance every time it's accessed
final cartServiceProvider = Provider<CartService>((ref) {
  return CartServiceProvider.getInstance();
});

/// Helper class to manage CartService singleton
class CartServiceProvider {
  static CartService? _instance;

  /// Get or create the singleton CartService instance
  ///
  /// Initializes with the base URL from ApiConfig
  /// This ensures the CartService always uses the correct API endpoint
  static CartService getInstance() {
    _instance ??= CartService(
      ApiConfig.prod, // Use ApiConfig base URL (prod endpoint)
      apiPrefix: ApiConfig.apiPrefix, // Use /vero prefix
    );
    return _instance!;
  }

  /// Clear the singleton instance (useful for testing)
  static void clear() {
    _instance = null;
  }

  /// Reinitialize with a specific base URL (for development/testing)
  static CartService initializeWithBase(String baseUrl,
      {String apiPrefix = '/vero'}) {
    _instance = CartService(baseUrl, apiPrefix: apiPrefix);
    return _instance!;
  }
}
