/// Signup-only password rules. Do not use on login — existing accounts
/// may be shorter, and login should only check that a password was entered.
class SignupPasswordRules {
  SignupPasswordRules._();

  static const int minLength = 8;

  static const _common = <String>{
    'password',
    'password1',
    'password12',
    'password123',
    'qwertyui',
    'qwerty123',
    '12345678',
    '123456789',
    '87654321',
    '01234567',
    'abcdefgh',
    'letmein1',
    'welcome1',
    'admin123',
    'vero3601',
    'vero3608',
    'iloveyou',
    '11111111',
    '00000000',
    '22222222',
    '12341234',
    '12121212',
  };

  /// 0 = empty, 1 = weak, 2 = fair, 3 = strong.
  static int strengthScore(String raw) {
    final s = raw;
    if (s.isEmpty) return 0;
    if (validate(s) != null) return 1;

    var score = 1;
    if (s.length >= 10) score++;
    final classes = <bool>[
      RegExp(r'[a-z]').hasMatch(s),
      RegExp(r'[A-Z]').hasMatch(s),
      RegExp(r'\d').hasMatch(s),
      RegExp(r'[^A-Za-z0-9]').hasMatch(s),
    ].where((ok) => ok).length;
    if (classes >= 3) score++;
    if (s.length >= 12 && classes >= 3) score = 3;
    return score.clamp(1, 3);
  }

  static String strengthLabel(int score) {
    switch (score) {
      case 0:
        return '';
      case 1:
        return 'Weak';
      case 2:
        return 'Fair';
      default:
        return 'Strong';
    }
  }

  static String? validate(String? v) {
    final s = v ?? '';
    if (s.isEmpty) return 'Password is required';
    if (s.length < minLength) return 'Must be at least $minLength characters';

    if (RegExp(r'^(.)\1+$').hasMatch(s)) {
      return 'Don’t repeat the same character';
    }
    if (_isSequential(s)) {
      return 'Don’t use a simple sequence like 12345678';
    }
    if (_isRepeatingBlock(s)) {
      return 'Don’t use a repeating pattern';
    }
    if (_common.contains(s.toLowerCase())) {
      return 'This password is too common. Choose a stronger one';
    }

    final hasLetter = RegExp(r'[A-Za-z]').hasMatch(s);
    final hasDigit = RegExp(r'\d').hasMatch(s);
    if (!hasLetter || !hasDigit) {
      return 'Use letters and numbers';
    }
    return null;
  }

  static bool _isSequential(String s) {
    if (s.length < 4) return false;
    final lower = s.toLowerCase();
    var inc = true;
    var dec = true;
    for (var i = 1; i < lower.length; i++) {
      final a = lower.codeUnitAt(i - 1);
      final b = lower.codeUnitAt(i);
      if (b != a + 1) inc = false;
      if (b != a - 1) dec = false;
      if (!inc && !dec) return false;
    }
    return inc || dec;
  }

  static bool _isRepeatingBlock(String s) {
    if (s.length < 4) return false;
    for (var len = 1; len <= s.length ~/ 2; len++) {
      if (s.length % len != 0) continue;
      final unit = s.substring(0, len);
      if (unit.length == s.length) continue;
      if (List.filled(s.length ~/ len, unit).join() == s) return true;
    }
    return false;
  }
}
