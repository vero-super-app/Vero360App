import 'package:intl/intl.dart';

/// Ensures food order numbers are shown with a Vero prefix (e.g. VeroF250902143012).
String formatVeroFoodOrderNumber(String? raw) {
  final clean = (raw ?? '').trim();
  if (clean.isEmpty) return '';
  if (clean.toLowerCase().startsWith('vero')) return clean;
  return 'Vero$clean';
}

/// Generates a human-readable food order reference for Firestore + escrow.
String generateFoodOrderNumber() {
  final stamp = DateFormat('yyMMddHHmmss').format(DateTime.now());
  return 'VeroF$stamp';
}
