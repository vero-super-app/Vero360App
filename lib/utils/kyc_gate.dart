import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:vero360_app/features/Auth/AuthPresenter/kyc_verification_screen.dart';

/// Shared KYC checks for merchant wallet withdrawals, food posting, and similar flows.
class KycGate {
  KycGate._();

  static const _verified = {'verified', 'approved'};
  static const _pending = {'pending', 'in_review', 'submitted'};
  static const _rejected = {'rejected', 'declined'};

  /// True when Firestore marks the signed-in user as KYC-complete.
  static Future<bool> isVerified({String? uid}) async {
    final snap = await loadStatus(uid: uid);
    return snap.verified;
  }

  static Future<KycStatusSnapshot> loadStatus({String? uid}) async {
    final id = (uid ?? FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (id.isEmpty) return const KycStatusSnapshot();
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(id).get();
      final data = doc.data() ?? {};
      var status = (data['kycStatus'] ?? '').toString().trim().toLowerCase();
      if (data['kycVerified'] == true && !_verified.contains(status)) {
        status = 'verified';
      }
      final reason = (data['kycRejectionReason'] ?? '').toString().trim();
      return KycStatusSnapshot(status: status, rejectionReason: reason);
    } catch (_) {
      return const KycStatusSnapshot();
    }
  }

  /// If KYC is incomplete, show a prompt and open verification.
  /// Returns `true` only when the user is verified.
  static Future<bool> ensureVerified(
    BuildContext context, {
    String title = 'Identity verification required',
    String message =
        'Complete identity verification (KYC) to continue. This protects your account and payouts.',
    String pendingMessage =
        'Verification is still pending or incomplete. You can continue once KYC is approved.',
  }) async {
    if (await isVerified()) return true;
    if (!context.mounted) return false;

    final go = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: Text(message),
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
        SnackBar(content: Text(pendingMessage)),
      );
    }
    return false;
  }

  /// If KYC is incomplete, show a mandatory prompt and open verification.
  /// Returns `true` only when the user is verified (already or after completing).
  static Future<bool> ensureVerifiedForWithdraw(BuildContext context) {
    return ensureVerified(
      context,
      title: 'Identity verification required',
      message:
          'Before you can withdraw wallet funds, you must complete identity '
          'verification (KYC). This protects your account and payouts.',
      pendingMessage:
          'Verification is still pending or incomplete. '
          'You can withdraw once KYC is approved.',
    );
  }
}

class KycStatusSnapshot {
  const KycStatusSnapshot({
    this.status = '',
    this.rejectionReason = '',
  });

  final String status;
  final String rejectionReason;

  bool get verified =>
      KycGate._verified.contains(status.trim().toLowerCase());
  bool get pending => KycGate._pending.contains(status.trim().toLowerCase());
  bool get rejected => KycGate._rejected.contains(status.trim().toLowerCase());
}
