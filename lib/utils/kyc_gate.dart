import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:vero360_app/features/Auth/AuthPresenter/kyc_verification_screen.dart';

/// Shared KYC checks for merchant wallet withdrawals (and similar money-out flows).
class KycGate {
  KycGate._();

  static const _verified = {'verified', 'approved'};

  /// True when Firestore marks the signed-in user as KYC-complete.
  static Future<bool> isVerified({String? uid}) async {
    final id = (uid ?? FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (id.isEmpty) return false;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(id).get();
      final data = snap.data() ?? {};
      if (data['kycVerified'] == true) return true;
      final status =
          (data['kycStatus'] ?? '').toString().trim().toLowerCase();
      return _verified.contains(status);
    } catch (_) {
      return false;
    }
  }

  /// If KYC is incomplete, show a mandatory prompt and open verification.
  /// Returns `true` only when the user is verified (already or after completing).
  static Future<bool> ensureVerifiedForWithdraw(BuildContext context) async {
    if (await isVerified()) return true;
    if (!context.mounted) return false;

    final go = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Identity verification required'),
        content: const Text(
          'Before you can withdraw wallet funds, you must complete identity '
          'verification (KYC). This protects your account and payouts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF8A00),
              foregroundColor: Colors.white,
            ),
            child: const Text('Verify now'),
          ),
        ],
      ),
    );

    if (go != true || !context.mounted) return false;

    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const KycVerificationScreen()),
    );
    if (!context.mounted) return false;

    if (await isVerified()) return true;

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Verification is still pending or incomplete. '
            'You can withdraw once KYC is approved.',
          ),
        ),
      );
    }
    return false;
  }
}
