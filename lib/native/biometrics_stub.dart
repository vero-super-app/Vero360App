class LocalAuthentication {
  Future<bool> isDeviceSupported() async => false;
  Future<bool> get canCheckBiometrics async => false;
  Future<List<BiometricType>> getAvailableBiometrics() async => const [];
  Future<bool> authenticate({
    required String localizedReason,
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async =>
      false;
}

class AuthenticationOptions {
  const AuthenticationOptions({
    this.biometricOnly = false,
    this.stickyAuth = false,
    this.useErrorDialogs = true,
    this.sensitiveTransaction = true,
  });

  final bool biometricOnly;
  final bool stickyAuth;
  final bool useErrorDialogs;
  final bool sensitiveTransaction;
}

enum BiometricType { face, fingerprint, iris, weak, strong }
