enum PaymentStatus {
  pending,
  processing,
  success,
  failed,
  cancelled,
  refunded,
}

class PaymentModel {
  final String id;
  final int bookingId;
  final double amount;
  final PaymentStatus status;
  final String method; // MERCHANT_MONEY, PAYPAL, STRIPE, BANK_TRANSFER
  final String? transactionId;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? failureReason;
  final Map<String, dynamic>? metadata;

  PaymentModel({
    required this.id,
    required this.bookingId,
    required this.amount,
    required this.status,
    required this.method,
    this.transactionId,
    required this.createdAt,
    this.completedAt,
    this.failureReason,
    this.metadata,
  });

  factory PaymentModel.fromJson(Map<String, dynamic> json) {
    return PaymentModel(
      id: json['id'] ?? '',
      bookingId: json['bookingId'] ?? json['booking_id'] ?? 0,
      amount: (json['amount'] ?? 0).toDouble(),
      status: _parsePaymentStatus(json['status'] ?? 'PENDING'),
      method: json['method'] ?? 'MERCHANT_MONEY',
      transactionId: json['transactionId'] ?? json['transaction_id'],
      createdAt: DateTime.parse(
        json['createdAt'] ?? json['created_at'] ?? DateTime.now().toIso8601String(),
      ),
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'])
          : (json['completed_at'] != null ? DateTime.parse(json['completed_at']) : null),
      failureReason: json['failureReason'] ?? json['failure_reason'],
      metadata: json['metadata'],
    );
  }

  static PaymentStatus _parsePaymentStatus(String status) {
    switch (status.toUpperCase()) {
      case 'PROCESSING':
        return PaymentStatus.processing;
      case 'SUCCESS':
        return PaymentStatus.success;
      case 'FAILED':
        return PaymentStatus.failed;
      case 'CANCELLED':
        return PaymentStatus.cancelled;
      case 'REFUNDED':
        return PaymentStatus.refunded;
      default:
        return PaymentStatus.pending;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'bookingId': bookingId,
        'amount': amount,
        'status': status.name.toUpperCase(),
        'method': method,
        'transactionId': transactionId,
        'createdAt': createdAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'failureReason': failureReason,
        'metadata': metadata,
      };

  PaymentModel copyWith({
    String? id,
    int? bookingId,
    double? amount,
    PaymentStatus? status,
    String? method,
    String? transactionId,
    DateTime? createdAt,
    DateTime? completedAt,
    String? failureReason,
    Map<String, dynamic>? metadata,
  }) {
    return PaymentModel(
      id: id ?? this.id,
      bookingId: bookingId ?? this.bookingId,
      amount: amount ?? this.amount,
      status: status ?? this.status,
      method: method ?? this.method,
      transactionId: transactionId ?? this.transactionId,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      failureReason: failureReason ?? this.failureReason,
      metadata: metadata ?? this.metadata,
    );
  }
}

class PaymentMethodModel {
  final String id;
  final String type; // CARD, MOBILE_MONEY, BANK_ACCOUNT
  final String? cardLast4;
  final String? cardBrand;
  final String? phoneNumber;
  final String? accountNumber;
  final String? bankName;
  final bool isDefault;
  final DateTime createdAt;

  PaymentMethodModel({
    required this.id,
    required this.type,
    this.cardLast4,
    this.cardBrand,
    this.phoneNumber,
    this.accountNumber,
    this.bankName,
    required this.isDefault,
    required this.createdAt,
  });

  factory PaymentMethodModel.fromJson(Map<String, dynamic> json) {
    return PaymentMethodModel(
      id: json['id'] ?? '',
      type: json['type'] ?? 'CARD',
      cardLast4: json['cardLast4'] ?? json['card_last_4'],
      cardBrand: json['cardBrand'] ?? json['card_brand'],
      phoneNumber: json['phoneNumber'] ?? json['phone_number'],
      accountNumber: json['accountNumber'] ?? json['account_number'],
      bankName: json['bankName'] ?? json['bank_name'],
      isDefault: json['isDefault'] ?? json['is_default'] ?? false,
      createdAt: DateTime.parse(
        json['createdAt'] ?? json['created_at'] ?? DateTime.now().toIso8601String(),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'cardLast4': cardLast4,
        'cardBrand': cardBrand,
        'phoneNumber': phoneNumber,
        'accountNumber': accountNumber,
        'bankName': bankName,
        'isDefault': isDefault,
        'createdAt': createdAt.toIso8601String(),
      };
}
