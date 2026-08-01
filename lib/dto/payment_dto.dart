class PaymentDto {
  final int bookingId;
  final double amount;
  final String method; // MERCHANT_MONEY, PAYPAL, STRIPE, BANK_TRANSFER
  final String? currency;
  final Map<String, dynamic>? metadata;

  const PaymentDto({
    required this.bookingId,
    required this.amount,
    required this.method,
    this.currency,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
        'bookingId': bookingId,
        'amount': amount,
        'method': method,
        'currency': currency ?? 'MWK',
        'metadata': metadata ?? {},
      };

  factory PaymentDto.fromJson(Map<String, dynamic> json) {
    return PaymentDto(
      bookingId: json['bookingId'] ?? 0,
      amount: (json['amount'] ?? 0).toDouble(),
      method: json['method'] ?? 'MERCHANT_MONEY',
      currency: json['currency'],
      metadata: json['metadata'],
    );
  }
}

class InitiatePaymentDto {
  final int bookingId;
  final double amount;
  final String method;
  final String? phoneNumber; // For mobile money
  final String? cardToken; // For card payments
  final String? bankCode; // For bank transfers
  final String? returnUrl;

  const InitiatePaymentDto({
    required this.bookingId,
    required this.amount,
    required this.method,
    this.phoneNumber,
    this.cardToken,
    this.bankCode,
    this.returnUrl,
  });

  Map<String, dynamic> toJson() => {
        'bookingId': bookingId,
        'amount': amount,
        'method': method,
        'phoneNumber': phoneNumber,
        'cardToken': cardToken,
        'bankCode': bankCode,
        'returnUrl': returnUrl,
      };
}

class PaymentMethodDto {
  final String type; // CARD, MOBILE_MONEY, BANK_ACCOUNT
  final String? cardToken;
  final String? phoneNumber;
  final String? accountNumber;
  final String? bankName;
  final bool? isDefault;

  const PaymentMethodDto({
    required this.type,
    this.cardToken,
    this.phoneNumber,
    this.accountNumber,
    this.bankName,
    this.isDefault,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'cardToken': cardToken,
        'phoneNumber': phoneNumber,
        'accountNumber': accountNumber,
        'bankName': bankName,
        'isDefault': isDefault ?? false,
      };
}
