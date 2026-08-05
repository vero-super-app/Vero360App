/// Detects off-platform contact / payment details in chat text
/// (phone numbers, bank accounts, mobile money, etc.).
class ChatOffPlatformDetector {
  ChatOffPlatformDetector._();

  static const warningText =
      'Vero360 is not responsible when business is done outside the Vero360 '
      'system. Vero will not be responsible for payments or any business '
      'done outside the app.';

  /// Malawi mobiles: 088… / 099… (with optional spaces/dashes) and +265 forms.
  static final RegExp _malawiPhone = RegExp(
    r'(?:(?:\+|00)?265[\s\-]*)?0?[89](?:[\s\-]?\d){8}\b',
    caseSensitive: false,
  );

  /// Generic international-ish phone (9–15 digits, optional +).
  static final RegExp _genericPhone = RegExp(
    r'(?<!\d)(?:\+?\d[\s\-]?){9,15}\d(?!\d)',
  );

  static final RegExp _bankOrPaymentKeywords = RegExp(
    r'\b('
    r'bank\s*account|account\s*(?:number|no\.?|#)|acc(?:ount)?\s*(?:no\.?|number|#)|'
    r'iban|swift(?:\s*code)?|sort\s*code|routing\s*(?:number|no\.?)|'
    r'account\s*name|deposit\s*(?:to|into)|wire\s*transfer|bank\s*transfer|'
    r'airtel\s*money|tnm\s*mpamba|mpamba|mobile\s*money|mo|NB|'
    r'standard\s*bank|national\s*bank|fdh(?:\s*bank)?|nbs(?:\s*bank)?|'
    r'centenary(?:\s*bank)?|first\s*capital|ecobank|opportunity\s*bank|'
    r'pay\s*outside|pay\s*offline|pay\s*directly|send\s*money\s*to|'
    r'whatsapp\s*(?:me|number)|call\s*me\s*on|text\s*me\s*on'
    r')\b',
    caseSensitive: false,
  );

  /// Long digit runs that look like account numbers (not already matched as phone).
  static final RegExp _longAccountDigits = RegExp(r'(?<!\d)\d{10,16}(?!\d)');

  /// Returns true when [text] looks like it shares phone / bank / payment details.
  static bool containsSensitiveDetails(String? text) {
    if (text == null) return false;
    final cleaned = text.trim();
    if (cleaned.isEmpty) return false;

    // Ignore pure media / call payloads.
    final lower = cleaned.toLowerCase();
    if (lower.startsWith('img::') ||
        lower.startsWith('aud::') ||
        lower.startsWith('call::') ||
        lower.startsWith('http://') ||
        lower.startsWith('https://')) {
      // Still scan captions after media prefixes.
      final caption = cleaned.contains('\n')
          ? cleaned.substring(cleaned.indexOf('\n') + 1)
          : '';
      if (caption.trim().isEmpty) return false;
      return containsSensitiveDetails(caption);
    }

    if (_malawiPhone.hasMatch(cleaned)) return true;
    if (_bankOrPaymentKeywords.hasMatch(cleaned)) return true;

    // Account-like digit runs only when bank / payment context is nearby.
    for (final m in _longAccountDigits.allMatches(cleaned)) {
      final digits = m.group(0)!.replaceAll(RegExp(r'\D'), '');
      if (_isLikelyMalawiMobile(digits)) continue;
      final start = (m.start - 40).clamp(0, cleaned.length);
      final end = (m.end + 40).clamp(0, cleaned.length);
      final window = cleaned.substring(start, end);
      if (_bankOrPaymentKeywords.hasMatch(window)) {
        return true;
      }
    }

    // Generic phone only when it looks like a Malawi / intl mobile.
    for (final m in _genericPhone.allMatches(cleaned)) {
      final raw = m.group(0)!;
      final digits = raw.replaceAll(RegExp(r'\D'), '');
      if (_isLikelyMalawiMobile(digits)) return true;
      if ((raw.contains('+') || raw.trimLeft().startsWith('00')) &&
          _isLikelyIntlMobile(digits)) {
        return true;
      }
    }

    return false;
  }

  static bool _isLikelyMalawiMobile(String digits) {
    if (digits.length == 10 &&
        (digits.startsWith('08') || digits.startsWith('09'))) {
      return true;
    }
    if (digits.length == 12 &&
        digits.startsWith('265') &&
        (digits[3] == '8' || digits[3] == '9')) {
      return true;
    }
    if (digits.length == 9 && (digits.startsWith('8') || digits.startsWith('9'))) {
      return true;
    }
    return false;
  }

  static bool _isLikelyIntlMobile(String digits) {
    // Avoid short IDs; require E.164-ish length without being year/order noise.
    return digits.length >= 10 && digits.length <= 15;
  }
}
