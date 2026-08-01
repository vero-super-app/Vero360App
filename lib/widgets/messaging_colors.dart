import 'package:flutter/material.dart';

/// Messaging Module Color Constants
/// Aligned with app-wide design system from CarRentalColors
class MessagingColors {
  // Brand Colors
  static const Color brandOrange = Color(0xFFFF8A00);
  static const Color brandOrangeSoft = Color(0xFFFFEAD1);
  static const Color brandOrangePale = Color(0xFFFFF4E6);

  // Text Colors
  static const Color title = Color(0xFF101010);
  static const Color body = Color(0xFF6B6B6B);
  static const Color subtitle = Color(0xFF9E9E9E);

  // Background & Surface
  static const Color background = Color(0xFFFFFFFF);
  static const Color surfaceLight = Color(0xFFFAFAFA);
  static const Color chip = Color(0xFFF9F5EF);
  static const Color messageInputBg = Color(0xFFF6F6F6);

  // Semantic Colors
  static const Color success = Color(0xFF4CAF50);
  static const Color successLight = Color(0xFFE8F5E9);
  static const Color warning = Color(0xFFFFC107);
  static const Color warningLight = Color(0xFFFFF9C4);
  static const Color error = Color(0xFFF44336);
  static const Color errorLight = Color(0xFFFFEBEE);

  // Neutral Colors
  static const Color grey = Color(0xFF9E9E9E);
  static const Color greyLight = Color(0xFFFAFAFA);
  static const Color greyDark = Color(0xFF424242);

  // Call-specific Colors
  static const Color callIncoming = Color(0xFF4CAF50); // Green
  static const Color callOutgoing = Color(0xFF2196F3); // Blue
  static const Color callEnded = Color(0xFF757575); // Grey
  static const Color callMissed = Color(0xFFF44336); // Red
  static const Color callDeclined = Color(0xFFFF9800); // Orange

  // Message Status Colors
  static const Color messageSent = Color(0xFF757575);
  static const Color messageDelivered = Color(0xFF1976D2);
  static const Color messageRead = Color(0xFF4CAF50);

  // Upload Progress Colors
  static const Color uploadProgress = Color(0xFF2196F3);
  static const Color uploadError = Color(0xFFF44336);
  static const Color uploadComplete = Color(0xFF4CAF50);

  // Borders
  static const Color border = Color(0xFFE0E0E0);
  static const Color borderLight = Color(0xFFF0F0F0);
  static const Color divider = Color(0xFFEEEEEE);
}
