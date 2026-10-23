import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'package:vero360_app/GernalServices/pawapay_payment.dart';
import 'package:vero360_app/features/car_hire/data/car_hire_api.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';

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

  return api.initiatePayment(booking.id, depositId: depositId);
}
