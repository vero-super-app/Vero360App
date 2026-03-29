import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App PIN used for buyer “confirm receipt” and merchant wallet unlock.
/// Same storage keys as [marketplace_merchant_dashboard] (`app_pin_hash` / `app_pin_salt`).
class AppWalletPin {
  AppWalletPin._();

  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandNavy = Color(0xFF16284C);
  static const Color _dialogFieldFill = Color(0xFFF4F6FA);

  static String _hashPin(String pin, String salt) {
    final bytes = utf8.encode('$pin::$salt');
    return sha256.convert(bytes).toString();
  }

  static String _randomSalt([int len = 16]) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final r = Random.secure();
    return List.generate(len, (_) => chars[r.nextInt(chars.length)]).join();
  }

  static InputDecoration _pinFieldDecoration(String hint) {
    final r = BorderRadius.circular(14);
    return InputDecoration(
      hintText: hint,
      counterText: '',
      filled: true,
      fillColor: _dialogFieldFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: r),
      enabledBorder: OutlineInputBorder(
        borderRadius: r,
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: r,
        borderSide: const BorderSide(color: _brandOrange, width: 2),
      ),
    );
  }

  static Widget _pinDialogHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF8A00), Color(0xFFFFA64D)],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    letterSpacing: -0.35,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Future<bool> hasPin() async {
    final sp = await SharedPreferences.getInstance();
    final h = (sp.getString('app_pin_hash') ?? '').trim();
    final s = (sp.getString('app_pin_salt') ?? '').trim();
    return h.isNotEmpty && s.isNotEmpty;
  }

  /// If no PIN exists, walks the user through creating one (same as merchant wallet).
  static Future<bool> ensurePinExists(BuildContext context) async {
    if (await hasPin()) return true;

    final pin = await _showSetPinDialog(context);
    if (pin == null) return false;

    final salt = _randomSalt();
    final hash = _hashPin(pin, salt);
    final sp = await SharedPreferences.getInstance();
    await sp.setString('app_pin_salt', salt);
    await sp.setString('app_pin_hash', hash);
    return true;
  }

  /// Confirms parcel receipt: tries **Face ID / fingerprint** first when available,
  /// then falls back to **PIN** (create PIN on first use if needed).
  static Future<bool> verifyParcelReceipt(BuildContext context) async {
    final auth = LocalAuthentication();
    var canUseBiometric = false;
    try {
      if (await auth.isDeviceSupported()) {
        final canCheck = await auth.canCheckBiometrics;
        if (canCheck) {
          final types = await auth.getAvailableBiometrics();
          canUseBiometric = types.isNotEmpty;
        }
      }
    } catch (_) {}

    if (canUseBiometric) {
      try {
        final ok = await auth.authenticate(
          localizedReason:
              'Confirm you received this parcel to release payment to the merchant.',
          options: const AuthenticationOptions(
            biometricOnly: true,
            stickyAuth: true,
          ),
        );
        if (ok) return true;
      } catch (_) {
        // Fall through to PIN (e.g. user cancelled or error).
      }
    }

    if (!context.mounted) return false;
    final ensured = await ensurePinExists(context);
    if (!context.mounted) return false;
    if (!ensured) return false;
    return verifyPin(context);
  }

  /// Prompts for PIN and returns true only if it matches the stored hash.
  static Future<bool> verifyPin(BuildContext context) async {
    if (!await hasPin()) return false;

    final sp = await SharedPreferences.getInstance();
    final salt = (sp.getString('app_pin_salt') ?? '').trim();
    final hash = (sp.getString('app_pin_hash') ?? '').trim();
    if (salt.isEmpty || hash.isEmpty) return false;

    final entered = await _showEnterPinDialog(context);
    if (entered == null) return false;

    final ok = _hashPin(entered, salt) == hash;
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wrong password')),
      );
    }
    return ok;
  }

  static Future<String?> _showEnterPinDialog(BuildContext context) async {
    final controller = TextEditingController();
    String? shortPinHint;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final kb = MediaQuery.viewInsetsOf(ctx).bottom;
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Material(
                color: Colors.white,
                elevation: 18,
                shadowColor: Colors.black.withValues(alpha: 0.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _pinDialogHeader(
                      icon: Icons.inventory_2_rounded,
                      title: 'Confirm receipt',
                      subtitle:
                          'Enter your wallet PIN to release payment to the seller.',
                    ),
                    Padding(
                      padding: EdgeInsets.only(bottom: kb),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                              child: Text(
                                'PIN',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.grey.shade700,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                              child: TextField(
                                controller: controller,
                                autofocus: true,
                                obscureText: true,
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                                onChanged: (_) {
                                  if (shortPinHint != null) {
                                    setLocal(() => shortPinHint = null);
                                  }
                                },
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2,
                                ),
                                decoration: _pinFieldDecoration('4–6 digits'),
                              ),
                            ),
                            if (shortPinHint != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    20, 0, 20, 12),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: _brandOrange.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _brandOrange
                                          .withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.info_outline_rounded,
                                        color: _brandNavy.withValues(alpha: 0.9),
                                        size: 22,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          shortPinHint!,
                                          style: TextStyle(
                                            color: Colors.grey.shade900,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1, thickness: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(null),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                side: BorderSide(color: Colors.grey.shade300),
                              ),
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              onPressed: () {
                                final pin = controller.text.trim();
                                if (pin.length < 4) {
                                  setLocal(() => shortPinHint =
                                      'Enter at least 4 digits to continue.');
                                  return;
                                }
                                Navigator.of(dialogContext).pop(pin);
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: _brandOrange,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                'Confirm',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static Future<String?> _showSetPinDialog(BuildContext context) async {
    final p1 = TextEditingController();
    final p2 = TextEditingController();
    String? err;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final kb = MediaQuery.viewInsetsOf(ctx).bottom;
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Material(
                color: Colors.white,
                elevation: 18,
                shadowColor: Colors.black.withValues(alpha: 0.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _pinDialogHeader(
                      icon: Icons.pin_rounded,
                      title: 'Set wallet PIN',
                      subtitle:
                          'Choose a 4–6 digit PIN. You’ll use it here and to unlock your wallet.',
                    ),
                    Padding(
                      padding: EdgeInsets.only(bottom: kb),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 20, 20, 0),
                              child: Text(
                                'New PIN',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.grey.shade700,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                              child: TextField(
                                controller: p1,
                                autofocus: true,
                                obscureText: true,
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                                onChanged: (_) {
                                  if (err != null) {
                                    setLocal(() => err = null);
                                  }
                                },
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2,
                                ),
                                decoration: _pinFieldDecoration('4–6 digits'),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                              child: Text(
                                'Confirm PIN',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.grey.shade700,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                              child: TextField(
                                controller: p2,
                                obscureText: true,
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                                onChanged: (_) {
                                  if (err != null) {
                                    setLocal(() => err = null);
                                  }
                                },
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2,
                                ),
                                decoration: _pinFieldDecoration('Re-enter PIN'),
                              ),
                            ),
                            if (err != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    20, 0, 20, 8),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFEBEE),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xFFEF9A9A)
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.error_outline_rounded,
                                        color: Color(0xFFC62828),
                                        size: 22,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          err!,
                                          style: const TextStyle(
                                            color: Color(0xFFB71C1C),
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1, thickness: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(null),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                side: BorderSide(color: Colors.grey.shade300),
                              ),
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              onPressed: () {
                                final a = p1.text.trim();
                                final b = p2.text.trim();

                                if (a.length < 4) {
                                  setLocal(() =>
                                      err = 'PIN must be at least 4 digits.');
                                  return;
                                }
                                if (a != b) {
                                  setLocal(() => err = 'PINs do not match.');
                                  return;
                                }
                                Navigator.of(dialogContext).pop(a);
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: _brandOrange,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                'Save PIN',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
