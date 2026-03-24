/// Merchant phone / contact shown in order UIs — never expose Firebase UIDs or junk strings.
String safeMerchantPhone(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return 'No phone number';

  final lower = s.toLowerCase();
  if (lower.contains('firebase')) return 'No phone number';

  // Real phone: mostly digits (E.164 / local), optional +, spaces, dashes, parens.
  final digitsOnly = s.replaceAll(RegExp(r'[^\d]'), '');
  if (digitsOnly.length >= 7 && digitsOnly.length <= 15) {
    // Reject if it still looks like an encoded id (many letters)
    if (!RegExp(r'[a-zA-Z]').hasMatch(s)) return s;
  }

  return 'No phone number';
}
