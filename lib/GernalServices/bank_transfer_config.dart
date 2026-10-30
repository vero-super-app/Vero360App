import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Live National Bank details from Firestore `app_config/bank_transfer`.
/// Admin can switch this off from web Finance.
class BankTransferDetails {
  final bool enabled;
  final String bankName;
  final String accountName;
  final String accountNumber;
  final String branch;

  const BankTransferDetails({
    required this.enabled,
    required this.bankName,
    required this.accountName,
    required this.accountNumber,
    required this.branch,
  });

  static const defaults = BankTransferDetails(
    enabled: true,
    bankName: 'National Bank of Malawi',
    accountName: 'VERO360 LIMITED',
    accountNumber: '1015027734',
    branch: 'City Centre',
  );

  bool get hasAccount => accountNumber.trim().isNotEmpty;

  bool get showToCustomers => enabled && hasAccount;
}

class BankTransferConfig extends ChangeNotifier {
  BankTransferConfig._();
  static final BankTransferConfig instance = BankTransferConfig._();

  static const String configPath = 'app_config/bank_transfer';

  BankTransferDetails _details = BankTransferDetails.defaults;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  BankTransferDetails get details => _details;

  Future<void> ensureStarted() async {
    if (_sub != null) return;
    try {
      final ref = FirebaseFirestore.instance.doc(configPath);
      final snap = await ref.get();
      _apply(snap.data(), exists: snap.exists);
      notifyListeners();
      _sub = ref.snapshots().listen((doc) {
        _apply(doc.data(), exists: doc.exists);
        notifyListeners();
      }, onError: (e) {
        if (kDebugMode) debugPrint('[BankTransfer] listen failed: $e');
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[BankTransfer] start failed: $e');
      notifyListeners();
    }
  }

  void _apply(Map<String, dynamic>? data, {required bool exists}) {
    if (!exists || data == null) {
      _details = BankTransferDetails.defaults;
      return;
    }
    _details = BankTransferDetails(
      enabled: data['enabled'] != false,
      bankName: (data['bankName'] ?? BankTransferDetails.defaults.bankName)
          .toString()
          .trim(),
      accountName:
          (data['accountName'] ?? BankTransferDetails.defaults.accountName)
              .toString()
              .trim(),
      accountNumber:
          (data['accountNumber'] ?? BankTransferDetails.defaults.accountNumber)
              .toString()
              .trim(),
      branch: (data['branch'] ?? BankTransferDetails.defaults.branch)
          .toString()
          .trim(),
    );
  }
}
