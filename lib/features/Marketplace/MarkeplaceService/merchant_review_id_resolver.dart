import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';
import 'package:vero360_app/GernalServices/backend_chat_service.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/serviceprovider_service.dart';

/// Resolves marketplace merchant references (Firebase UID, phone, etc.)
/// to the numeric backend id required by `/vero/reviews` APIs.
class MerchantReviewIdResolver {
  MerchantReviewIdResolver._();

  static bool _looksLikeFirebaseUid(String value) {
    return RegExp(r'^[A-Za-z0-9_-]{20,}$').hasMatch(value);
  }

  static int? _parsePositiveInt(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final n = int.tryParse(raw.trim());
    if (n != null && n > 0) return n;
    return null;
  }

  /// Guest-safe: never calls authenticated-only `/users` without a token.
  static Future<int> resolveMerchantId({
    required String merchantRef,
    String? serviceProviderId,
    String? sellerUserId,
    int? preResolvedBackendId,
  }) async {
    final preset = preResolvedBackendId;
    if (preset != null && preset > 0) return preset;

    final direct = _parsePositiveInt(merchantRef);
    if (direct != null) return direct;

    for (final raw in [sellerUserId, serviceProviderId]) {
      final n = _parsePositiveInt(raw);
      if (n != null) return n;
    }

    for (final raw in [serviceProviderId, merchantRef, sellerUserId]) {
      final key = (raw ?? '').trim();
      if (key.isEmpty || _looksLikeFirebaseUid(key)) continue;
      try {
        final sp = await ServiceProviderServicess.fetchByNumber(key);
        if (sp?.id != null && sp!.id! > 0) return sp.id!;
      } catch (_) {}
    }

    for (final raw in [merchantRef, sellerUserId, serviceProviderId]) {
      if (raw == null || raw.trim().isEmpty) continue;
      final trimmed = raw.trim();
      if (!_looksLikeFirebaseUid(trimmed)) continue;

      final fromFirestore = await _lookupBackendIdFromFirestore(trimmed);
      if (fromFirestore != null && fromFirestore > 0) return fromFirestore;

      if (await AuthHandler.isAuthenticated()) {
        final id = await _lookupUserIdByFirebaseUidAuthenticated(trimmed);
        if (id != null && id > 0) return id;
      }
    }

    throw const ApiException(
      message: 'Please log in to view and leave reviews.',
      requiresLogin: true,
    );
  }

  static Future<int?> _lookupBackendIdFromFirestore(String firebaseUid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('marketplace_merchants')
          .doc(firebaseUid)
          .get();
      if (!doc.exists) return null;
      final data = doc.data();
      if (data == null) return null;

      for (final key in [
        'backendUserId',
        'userId',
        'merchantUserId',
        'ownerId',
        'sellerUserId',
      ]) {
        final parsed = _parsePositiveInt(data[key]?.toString());
        if (parsed != null) return parsed;
      }
    } catch (_) {}
    return null;
  }

  static Future<int?> _lookupUserIdByFirebaseUidAuthenticated(
    String firebaseUid,
  ) async {
    if (firebaseUid.isEmpty) return null;
    try {
      if (!await AuthHandler.isAuthenticated()) return null;
      await BackendChatService.ensureAuth();
      return BackendChatService.getUserIdByFirebaseUid(firebaseUid, quiet: true);
    } catch (_) {
      return null;
    }
  }

  static Future<int> resolveCustomerId() async {
    await BackendChatService.ensureAuth();
    return BackendChatService.getUserId();
  }
}
