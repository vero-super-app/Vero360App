import 'package:cloud_firestore/cloud_firestore.dart';

class WalletModel {
  final String walletId;
  final String userId;
  final String? merchantName;
  final double balance;
  final double pendingBalance;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<WalletTransaction> transactions;

  WalletModel({
    required this.walletId,
    required this.userId,
    this.merchantName,
    required this.balance,
    this.pendingBalance = 0.0,
    required this.createdAt,
    required this.updatedAt,
    required this.transactions,
  });

  // Convert to Firestore Map
  Map<String, dynamic> toMap() {
    return {
      'walletId': walletId,
      'userId': userId,
      'merchantName': merchantName,
      'balance': balance,
      'pendingBalance': pendingBalance,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'transactions': transactions.map((tx) => tx.toMap()).toList(),
    };
  }

  // Create from Firestore Document
  factory WalletModel.fromMap(Map<String, dynamic> map) {
    return WalletModel(
      walletId: map['walletId'] ?? '',
      userId: map['userId'] ?? '',
      merchantName: map['merchantName'],
      balance: (map['balance'] ?? 0.0).toDouble(),
      pendingBalance: (map['pendingBalance'] ?? 0.0).toDouble(),
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      updatedAt: (map['updatedAt'] as Timestamp).toDate(),
      transactions: List<WalletTransaction>.from(
        (map['transactions'] as List<dynamic>? ?? []).map((tx) => 
          WalletTransaction.fromMap(tx as Map<String, dynamic>)),
      ),
    );
  }

  // Copy with updates
  WalletModel copyWith({
    String? walletId,
    String? userId,
    String? merchantName,
    double? balance,
    double? pendingBalance,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<WalletTransaction>? transactions,
  }) {
    return WalletModel(
      walletId: walletId ?? this.walletId,
      userId: userId ?? this.userId,
      merchantName: merchantName ?? this.merchantName,
      balance: balance ?? this.balance,
      pendingBalance: pendingBalance ?? this.pendingBalance,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      transactions: transactions ?? this.transactions,
    );
  }
}

class WalletTransaction {
  final String transactionId;
  final String walletId;
  final String type;
  final double amount;
  final String status;
  final String description;
  final String reference;
  final DateTime createdAt;
  final String? payoutMethod;
  final String? bankName;
  final String? accountNumber;
  final String? recipientName;
  final String? recipientPhone;
  final double? fee;

  WalletTransaction({
    required this.transactionId,
    required this.walletId,
    required this.type,
    required this.amount,
    required this.status,
    required this.description,
    required this.reference,
    required this.createdAt,
    this.payoutMethod,
    this.bankName,
    this.accountNumber,
    this.recipientName,
    this.recipientPhone,
    this.fee,
  });

  // Convert to Firestore Map
  Map<String, dynamic> toMap() {
    return {
      'transactionId': transactionId,
      'walletId': walletId,
      'type': type,
      'amount': amount,
      'status': status,
      'description': description,
      'reference': reference,
      'createdAt': Timestamp.fromDate(createdAt),
      'payoutMethod': payoutMethod,
      'bankName': bankName,
      'accountNumber': accountNumber,
      'recipientName': recipientName,
      'recipientPhone': recipientPhone,
      'fee': fee,
    };
  }

  // Create from Firestore Map
  factory WalletTransaction.fromMap(Map<String, dynamic> map) {
    return WalletTransaction(
      transactionId: map['transactionId'] ?? '',
      walletId: map['walletId'] ?? '',
      type: map['type'] ?? '',
      amount: (map['amount'] ?? 0.0).toDouble(),
      status: map['status'] ?? '',
      description: map['description'] ?? '',
      reference: map['reference'] ?? '',
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      payoutMethod: map['payoutMethod'],
      bankName: map['bankName'],
      accountNumber: map['accountNumber'],
      recipientName: map['recipientName'],
      recipientPhone: map['recipientPhone'],
      fee: (map['fee'] ?? 0.0).toDouble(),
    );
  }
}