import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:vero360_app/GernalServices/pawapay_payment.dart';
import 'package:vero360_app/features/car_hire/data/car_hire_api.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';

String _depositPrefsKey(int bookingId) => 'car_hire_pawapay_deposit_$bookingId';

Future<void> storeCarHirePawaPayDepositId({
  required int bookingId,
  required String depositId,
}) async {
  final id = depositId.trim();
  if (id.isEmpty) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_depositPrefsKey(bookingId), id);
}

Future<String?> readCarHirePawaPayDepositId(int bookingId) async {
  final prefs = await SharedPreferences.getInstance();
  final id = prefs.getString(_depositPrefsKey(bookingId))?.trim();
  if (id == null || id.isEmpty) return null;
  return id;
}

/// Collects the booking total with PawaPay, then confirms it on Nest.
Future<PaymentInitiation?> confirmCarHirePawaPayPayment({
  required BuildContext context,
  required CarHireApi api,
  required CarHireBooking booking,
  String? initialPhone,
}) async {
  final amountMwk = booking.total.round();
  if (amountMwk < 1) {
    throw const CarHireApiException(
      message: 'This booking has no payable amount.',
      kind: CarHireErrorKind.validation,
    );
  }

  final depositId = await Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => PawaPayCheckoutPage(
        amountMwk: amountMwk,
        reference: 'CAR_BOOKING:${booking.id}_${const Uuid().v4()}',
        initialPhone: initialPhone,
      ),
    ),
  );
  if (depositId == null || depositId.isEmpty) return null;
  await storeCarHirePawaPayDepositId(
    bookingId: booking.id,
    depositId: depositId,
  );

  return api.initiatePayment(booking.id, depositId: depositId);
}

/// Re-sends a completed PawaPay deposit to Nest after a successful phone prompt.
Future<PaymentInitiation> recoverCarHirePawaPayPayment({
  required CarHireApi api,
  required int bookingId,
}) async {
  final stored = await readCarHirePawaPayDepositId(bookingId);
  return api.initiatePayment(bookingId, depositId: stored);
}
