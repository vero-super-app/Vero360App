import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider, FutureProvider;
import 'package:flutter_riverpod/legacy.dart' show StateNotifierProvider;
import 'package:state_notifier/state_notifier.dart';

import 'package:vero360_app/GeneralModels/payment_model.dart';
import 'package:vero360_app/GernalServices/payment_service.dart';

final paymentServiceProvider = Provider<PaymentService>((ref) {
  return PaymentService();
});

final paymentMethodsFutureProvider = FutureProvider<List<PaymentMethodModel>>((ref) async {
  final service = ref.watch(paymentServiceProvider);
  return service.getPaymentMethods();
});

final transactionHistoryFutureProvider = FutureProvider<List<PaymentModel>>((ref) async {
  final service = ref.watch(paymentServiceProvider);
  return service.getTransactionHistory();
});

final paymentFormProvider =
    StateNotifierProvider<PaymentFormNotifier, PaymentFormState>((ref) {
  return PaymentFormNotifier();
});

class PaymentFormState {
  final int bookingId;
  final double amount;
  final String method;
  final String? phoneNumber;
  final String? cardToken;
  final String? bankCode;
  final bool isLoading;
  final String? error;

  PaymentFormState({
    this.bookingId = 0,
    this.amount = 0,
    this.method = 'MERCHANT_MONEY',
    this.phoneNumber,
    this.cardToken,
    this.bankCode,
    this.isLoading = false,
    this.error,
  });

  PaymentFormState copyWith({
    int? bookingId,
    double? amount,
    String? method,
    String? phoneNumber,
    String? cardToken,
    String? bankCode,
    bool? isLoading,
    String? error,
  }) {
    return PaymentFormState(
      bookingId: bookingId ?? this.bookingId,
      amount: amount ?? this.amount,
      method: method ?? this.method,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      cardToken: cardToken ?? this.cardToken,
      bankCode: bankCode ?? this.bankCode,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class PaymentFormNotifier extends StateNotifier<PaymentFormState> {
  PaymentFormNotifier() : super(PaymentFormState());

  void setBookingId(int id) => state = state.copyWith(bookingId: id);
  void setAmount(double amount) => state = state.copyWith(amount: amount);
  void setMethod(String method) => state = state.copyWith(method: method);
  void setPhoneNumber(String number) => state = state.copyWith(phoneNumber: number);
  void setCardToken(String token) => state = state.copyWith(cardToken: token);
  void setBankCode(String code) => state = state.copyWith(bankCode: code);
  void setLoading(bool isLoading) => state = state.copyWith(isLoading: isLoading);
  void setError(String? error) => state = state.copyWith(error: error);
  void reset() => state = PaymentFormState();
}
