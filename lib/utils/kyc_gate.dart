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
        status = 'approved';
      }
      final reason = (data['kycRejectionReason'] ?? '').toString().trim();
      return KycStatusSnapshot(status: status, rejectionReason: reason);
    } catch (_) {
      return const KycStatusSnapshot();
    }
  }

  /// If KYC is incomplete, show a modern prompt and open verification.
  /// Returns `true` only when the user is verified.
  static Future<bool> ensureVerified(
    BuildContext context, {
    String title = 'Verify your identity',
    String message =
        'Complete a quick KYC check to post dishes, receive orders, and withdraw payouts securely.',
    String pendingMessage =
        'Verification is still pending. You can continue once KYC is approved.',
  }) async {
    if (await isVerified()) return true;
    if (!context.mounted) return false;

    final go = await showModernKycDialog(
      context,
      title: title,
      message: message,
    );
    if (go != true || !context.mounted) return false;

    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const KycVerificationScreen()),
    );
    if (!context.mounted) return false;

    if (await isVerified()) return true;

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(pendingMessage),
        ),
      );
    }
    return false;
  }

  /// If KYC is incomplete, show a mandatory prompt and open verification.
  /// Returns `true` only when the user is verified (already or after completing).
  static Future<bool> ensureVerifiedForWithdraw(BuildContext context) {
    return ensureVerified(
      context,
      title: 'Verify before withdrawing',
      message:
          'Before withdrawing wallet funds, complete identity verification. '
          'This protects your account and payouts.',
      pendingMessage:
          'Verification is still pending. You can withdraw once KYC is approved.',
    );
  }
}

/// Modern centered KYC prompt (icon, title, short copy, pill actions).
Future<bool> showModernKycDialog(
  BuildContext context, {
  required String title,
  required String message,
  String cancelLabel = 'Not now',
  String confirmLabel = 'Verify now',
}) async {
  const brand = Color(0xFFFF8A00);
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final maxH = MediaQuery.sizeOf(ctx).height * 0.78;
      return Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 400, maxHeight: maxH),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFB347), brand],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: brand.withValues(alpha: 0.28),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.verified_user_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    letterSpacing: -0.3,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8F0),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: brand.withValues(alpha: 0.2)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.shield_outlined, color: brand, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Takes about 2 minutes · Encrypted & secure',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF374151),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          side: const BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                        child: Text(
                          cancelLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF374151),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: brand,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          confirmLabel,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return result == true;
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
