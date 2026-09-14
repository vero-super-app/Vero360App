/// Masks phone numbers in public listing / promo / shop descriptions so
/// contact stays on Vero360 (e.g. `0991234567` → `0991******`).
class DescriptionContactMask {
  DescriptionContactMask._();

  /// Malawi mobiles: 088… / 099… (optional spaces/dashes) and +265 forms.
  static final RegExp _malawiPhone = RegExp(
    r'(?:(?:\+|00)?265[\s\-]*)?0?[89](?:[\s\-]?\d){8}\b',
    caseSensitive: false,
  );

  /// Generic international-ish phone (9–15 digits, optional +).
  static final RegExp _genericPhone = RegExp(
    r'(?<!\d)(?:\+?\d[\s\-]?){9,15}\d(?!\d)',
  );

  /// Returns [text] with phone numbers hidden (digits after a short prefix → `*`).
  static String mask(String? text) {
    if (text == null) return '';
    final cleaned = text;
    if (cleaned.trim().isEmpty) return cleaned;

    var out = cleaned.replaceAllMapped(_malawiPhone, (m) {
      return _maskMatch(m.group(0)!);
    });

    out = out.replaceAllMapped(_genericPhone, (m) {
      final raw = m.group(0)!;
      final digits = raw.replaceAll(RegExp(r'\D'), '');
      if (!_isLikelyMalawiMobile(digits) && !_isLikelyIntlMobile(digits)) {
        return raw;
      }
      // Skip if already mostly starred from the Malawi pass.
      if (raw.contains('*')) return raw;
      return _maskMatch(raw);
    });

    return out;
  }

  /// True when [text] still contains an unmasked phone-like number.
  static bool containsPhone(String? text) {
    if (text == null || text.trim().isEmpty) return false;
    if (_malawiPhone.hasMatch(text)) return true;
    for (final m in _genericPhone.allMatches(text)) {
      final digits = m.group(0)!.replaceAll(RegExp(r'\D'), '');
      if (_isLikelyMalawiMobile(digits) || _isLikelyIntlMobile(digits)) {
        return true;
      }
    }
    return false;
  }

  static String _maskMatch(String raw) {
    final chars = raw.split('');
    var digitCount = 0;
    for (final c in chars) {
      if (RegExp(r'\d').hasMatch(c)) digitCount++;
    }
    if (digitCount < 9) return raw;

    // Keep only a short prefix visible — majority starred (e.g. 0991******).
    final keepDigits = digitCount >= 12 ? 5 : 4;
    var seen = 0;
    final buf = StringBuffer();
    for (final c in chars) {
      if (RegExp(r'\d').hasMatch(c)) {
        seen++;
        buf.write(seen <= keepDigits ? c : '*');
      } else {
        buf.write(c);
      }
    }
    return buf.toString();
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
    if (digits.length == 9 &&
        (digits.startsWith('8') || digits.startsWith('9'))) {
      return true;
    }
    return false;
  }

  static bool _isLikelyIntlMobile(String digits) {
    return digits.length >= 10 && digits.length <= 15;
  }
}
