import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A device-local account remembered after a successful sign-in (survives logout).
class SavedLoginAccount {
  final String id;
  final String identifier;
  final String displayName;
  final String? photoUrl;
  final String authProvider; // password | google | apple
  final int lastUsedAtMs;

  const SavedLoginAccount({
    required this.id,
    required this.identifier,
    required this.displayName,
    this.photoUrl,
    this.authProvider = 'password',
    required this.lastUsedAtMs,
  });

  factory SavedLoginAccount.fromJson(Map<String, dynamic> json) {
    return SavedLoginAccount(
      id: json['id']?.toString() ?? '',
      identifier: json['identifier']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      photoUrl: json['photoUrl']?.toString(),
      authProvider: json['authProvider']?.toString() ?? 'password',
      lastUsedAtMs: json['lastUsedAtMs'] is int
          ? json['lastUsedAtMs'] as int
          : int.tryParse(json['lastUsedAtMs']?.toString() ?? '') ??
              DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'identifier': identifier,
        'displayName': displayName,
        if (photoUrl != null && photoUrl!.isNotEmpty) 'photoUrl': photoUrl,
        'authProvider': authProvider,
        'lastUsedAtMs': lastUsedAtMs,
      };

  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) {
      return identifier.isNotEmpty ? identifier[0].toUpperCase() : '?';
    }
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  bool get isSocial =>
      authProvider == 'google' || authProvider == 'apple';
}

class RecentLoginStorage {
  static const _prefsKey = 'saved_login_accounts_v1';
  static const _maxAccounts = 3;

  static String _accountId(String identifier) =>
      identifier.trim().toLowerCase();

  static Future<List<SavedLoginAccount>> loadAccounts() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => SavedLoginAccount.fromJson(Map<String, dynamic>.from(e)))
          .where((a) => a.identifier.isNotEmpty)
          .toList()
        ..sort((a, b) => b.lastUsedAtMs.compareTo(a.lastUsedAtMs));
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveAccount({
    required String identifier,
    required String displayName,
    String? photoUrl,
    String authProvider = 'password',
  }) async {
    final trimmedId = identifier.trim();
    if (trimmedId.isEmpty) return;

    final accounts = await loadAccounts();
    final id = _accountId(trimmedId);
    final now = DateTime.now().millisecondsSinceEpoch;
    final name = displayName.trim().isNotEmpty ? displayName.trim() : trimmedId;

    final updated = SavedLoginAccount(
      id: id,
      identifier: trimmedId,
      displayName: name,
      photoUrl: photoUrl?.trim().isNotEmpty == true ? photoUrl!.trim() : null,
      authProvider: authProvider,
      lastUsedAtMs: now,
    );

    final others = accounts.where((a) => a.id != id).toList();
    final merged = [updated, ...others];
    if (merged.length > _maxAccounts) {
      merged.removeRange(_maxAccounts, merged.length);
    }

    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _prefsKey,
      jsonEncode(merged.map((a) => a.toJson()).toList()),
    );

    // Legacy prefill keys for any older screens still reading them.
    await sp.setString('prefill_login_identifier', trimmedId);
  }

  static Future<void> removeAccount(String accountId) async {
    final accounts = await loadAccounts();
    final merged = accounts.where((a) => a.id != accountId).toList();
    final sp = await SharedPreferences.getInstance();
    if (merged.isEmpty) {
      await sp.remove(_prefsKey);
      await sp.remove('prefill_login_identifier');
      return;
    }
    await sp.setString(
      _prefsKey,
      jsonEncode(merged.map((a) => a.toJson()).toList()),
    );
  }
}
