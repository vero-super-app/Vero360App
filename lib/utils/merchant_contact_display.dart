/// Merchant phone / contact shown in order UIs — never expose Firebase UIDs or junk strings.
String safeMerchantPhone(String? raw) {
  final cleaned = sanitizedPhoneOrEmpty(raw);
  return cleaned.isEmpty ? 'No phone number' : cleaned;
}

/// Real phone or empty. Drops Firebase UIDs like `+firebase_…`.
String sanitizedPhoneOrEmpty(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return '';

  final lower = s.toLowerCase();
  if (lower.contains('firebase') ||
      lower.contains('firestore') ||
      lower.contains('uid_') ||
      lower.startsWith('+firebase')) {
    return '';
  }

  final digitsOnly = s.replaceAll(RegExp(r'\D'), '');
  if (digitsOnly.length < 8 || digitsOnly.length > 15) return '';
  if (RegExp(r'[A-Za-z]').hasMatch(s)) return '';
  return s;
}
