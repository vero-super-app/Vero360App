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
