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
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Enter your password'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            hintText: 'PIN (4–6 digits)',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final pin = controller.text.trim();
              if (pin.length < 4) return;
              Navigator.pop(context, pin);
            },
            child: const Text(
              'Continue',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
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
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Set password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Create a PIN to use if Face ID or fingerprint isn’t available.',
              ),
              const SizedBox(height: 10),
              TextField(
                controller: p1,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  hintText: 'New PIN (4–6 digits)',
                  counterText: '',
                ),
              ),
              TextField(
                controller: p2,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  hintText: 'Confirm PIN',
                  counterText: '',
                ),
              ),
              if (err != null) ...[
                const SizedBox(height: 8),
                Text(
                  err!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final a = p1.text.trim();
                final b = p2.text.trim();

                if (a.length < 4) {
                  setLocal(() => err = 'PIN must be at least 4 digits.');
                  return;
                }
                if (a != b) {
                  setLocal(() => err = 'PINs do not match.');
                  return;
                }
                Navigator.pop(context, a);
              },
              child: const Text(
                'Save',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
