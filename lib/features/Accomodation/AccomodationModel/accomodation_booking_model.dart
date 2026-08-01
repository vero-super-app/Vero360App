/// Body for `POST /vero/bookings` (see backend OpenAPI / curl).
class VeroBookingsCreatePayload {
  final int accommodationId;
  final String bookingDate;
  final num price;
  final num bookingFee;
  final String? phoneNumber;

  VeroBookingsCreatePayload({
    required this.accommodationId,
    required this.bookingDate,
    required this.price,
    this.bookingFee = 0,
    this.phoneNumber,
  });

  Map<String, dynamic> toJson() => {
        'accommodationId': accommodationId,
        'bookingDate': bookingDate,
        'price': price,
        'bookingFee': bookingFee,
        if (phoneNumber != null && phoneNumber!.trim().isNotEmpty)
          'phone_number': phoneNumber!.trim(),
        if (phoneNumber != null && phoneNumber!.trim().isNotEmpty)
          'phoneNumber': phoneNumber!.trim(),
      };
}

/// Legacy `/accomodation/create` shape (kept if other clients still use it).
class BookingRequest {
  final int boardingHouseId;
  final String studentName;
  final String emailAddress;
  final String phoneNumber;
  final String bookingDate;
  final String price; // The booking fee will be passed from the hostel.

  BookingRequest({
    required this.boardingHouseId,
    required this.studentName,
    required this.emailAddress,
    required this.phoneNumber,
    required this.bookingDate,
    required this.price,
  });

  Map<String, dynamic> toJson() {
    return {
      'boardingHouseId': boardingHouseId,
      'studentName': studentName,
      'emailAddress': emailAddress,
      'phoneNumber': phoneNumber,
      'bookingDate': bookingDate,
      'Price': price,
    };
  }
}
