import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/merchant_review_id_resolver.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/merchant_review_service.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';

/// Why the rating prompt is shown — mirrors Facebook-style gated reviews.
enum MerchantReviewReason {
  /// After a real back-and-forth in chat.
  afterChat,

  /// After business is done (e.g. buyer confirmed parcel receipt).
  afterOrder,
}

/// Shows a one-time rating sheet after chat or completed business.
/// Reviews are not open to anyone from the public reviews page.
class MerchantReviewPrompt {
  MerchantReviewPrompt._();

  static const _brandOrange = Color(0xFFFF8A00);
  static const _service = MerchantReviewService();

  static String _prefsKey(String contextKey) =>
      'merchant_review_prompted_v1_${contextKey.trim()}';

  /// Returns true if a review was submitted.
  static Future<bool> maybeShow(
    BuildContext context, {
    required String merchantName,
    required MerchantReviewReason reason,
    required String contextKey,
    String? merchantRef,
    String? serviceProviderId,
    String? sellerUserId,
    int? merchantBackendId,
  }) async {
    final key = contextKey.trim();
    if (key.isEmpty) return false;
    final name = merchantName.trim().isEmpty ? 'this seller' : merchantName.trim();

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefsKey(key)) == true) return false;

    if (!context.mounted) return false;

    final draft = await showModalBottomSheet<_ReviewDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReviewPromptSheet(
        merchantName: name,
        reason: reason,
      ),
    );

    // Remember we asked (even if skipped) so we don't nag every back press.
    await prefs.setBool(_prefsKey(key), true);

    if (draft == null || !context.mounted) return false;
    if (draft.skipped) return false;

    try {
      final resolvedMerchantId = await MerchantReviewIdResolver.resolveMerchantId(
        merchantRef: (merchantRef ?? '').trim().isEmpty
            ? '${merchantBackendId ?? ''}'
            : merchantRef!.trim(),
        serviceProviderId: serviceProviderId,
        sellerUserId: sellerUserId,
        preResolvedBackendId: merchantBackendId,
      );
      await MerchantReviewIdResolver.ensureMerchantEligibleForReview(
        resolvedMerchantId,
      );
      final customerId = await MerchantReviewIdResolver.resolveCustomerId();

      await _service.createReview(
        merchantId: resolvedMerchantId,
        customerId: customerId,
        rating: draft.rating,
        comment: draft.comment,
      );

      if (!context.mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks for your rating!')),
      );
      return true;
    } catch (e) {
      if (!context.mounted) return false;
      var msg = e is ApiException ? e.message : 'Could not save rating.';
      final lower = msg.toLowerCase();
      if (lower.contains('only be left for merchants')) {
        msg =
            'This seller is not marked as a merchant on the server yet. '
            'Ask them to open their Merchant dashboard once, then try again.';
      } else if (lower.contains('log in again') ||
          lower.contains('resolve your account')) {
        msg =
            'Could not verify your account for reviews. Pull to refresh, or sign out and back in.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.red.shade700,
        ),
      );
      // Allow retry next time if submit failed.
      await prefs.remove(_prefsKey(key));
      return false;
    }
  }
}

class _ReviewDraft {
  final int rating;
  final String comment;
  final bool skipped;

  const _ReviewDraft({
    required this.rating,
    required this.comment,
    this.skipped = false,
  });

  static const skip = _ReviewDraft(rating: 0, comment: '', skipped: true);
}

class _ReviewPromptSheet extends StatefulWidget {
  final String merchantName;
  final MerchantReviewReason reason;

  const _ReviewPromptSheet({
    required this.merchantName,
    required this.reason,
  });

  @override
  State<_ReviewPromptSheet> createState() => _ReviewPromptSheetState();
}

class _ReviewPromptSheetState extends State<_ReviewPromptSheet> {
  int _rating = 5;
  final _commentCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  String get _title {
    switch (widget.reason) {
      case MerchantReviewReason.afterChat:
        return 'How was your chat?';
      case MerchantReviewReason.afterOrder:
        return 'How was your experience?';
    }
  }

  String get _subtitle {
    switch (widget.reason) {
      case MerchantReviewReason.afterChat:
        return 'Rate ${widget.merchantName} after your conversation.';
      case MerchantReviewReason.afterOrder:
        return 'Rate ${widget.merchantName} now that business is done.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF101010),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    final star = i + 1;
                    final filled = star <= _rating;
                    return IconButton(
                      onPressed: _submitting
                          ? null
                          : () => setState(() => _rating = star),
                      icon: Icon(
                        filled ? Icons.star_rounded : Icons.star_outline_rounded,
                        size: 36,
                        color: filled
                            ? MerchantReviewPrompt._brandOrange
                            : Colors.grey.shade400,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _commentCtrl,
                  enabled: !_submitting,
                  maxLines: 4,
                  minLines: 2,
                  maxLength: 1000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Add a short comment (optional)…',
                    filled: true,
                    fillColor: const Color(0xFFF7F8FA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: MerchantReviewPrompt._brandOrange,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _submitting
                      ? null
                      : () {
                          setState(() => _submitting = true);
                          Navigator.pop(
                            context,
                            _ReviewDraft(
                              rating: _rating.clamp(1, 5),
                              comment: _commentCtrl.text.trim(),
                            ),
                          );
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: MerchantReviewPrompt._brandOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Submit rating',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton(
                  onPressed: _submitting
                      ? null
                      : () => Navigator.pop(context, _ReviewDraft.skip),
                  child: const Text('Not now'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
