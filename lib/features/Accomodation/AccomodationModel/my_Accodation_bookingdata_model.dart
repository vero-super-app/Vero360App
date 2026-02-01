enum BookingStatus { pending, confirmed, cancelled, completed, unknown }

BookingStatus bookingStatusFrom(String? v) {
  final s = (v ?? '').toLowerCase().trim();
  switch (s) {
    case 'pending':   return BookingStatus.pending;
    case 'confirmed': return BookingStatus.confirmed;
    case 'cancelled':
    case 'canceled':  return BookingStatus.cancelled;
    case 'completed':
    case 'done':      return BookingStatus.completed;
    default:          return BookingStatus.unknown;
  }
}

String bookingStatusToApi(BookingStatus s) {
  switch (s) {
    case BookingStatus.pending:   return 'pending';
    case BookingStatus.confirmed: return 'confirmed';
    case BookingStatus.cancelled: return 'cancelled';
    case BookingStatus.completed: return 'completed';
    case BookingStatus.unknown:   return 'pending';
  }
}

class BookingItem {
  final String id;                 // accepts "ID" | "id" | "bookingId"
  final DateTime? bookingDate;     // ISO string -> DateTime
  final num price;
  final num bookingFee;
  final BookingStatus status;

  // Accommodation (if API returns nested object)
  final int?    accommodationId;
  final String? accommodationName;
  final String? accommodationLocation;
  final String? accommodationDescription;
  final String? accommodationType;
  final num?    pricePerNight;
  final String? imageUrl;

  num get total => price + bookingFee;

  BookingItem({
    required this.id,
    required this.bookingDate,
    required this.price,
    required this.bookingFee,
    required this.status,
    this.accommodationId,
    this.accommodationName,
    this.accommodationLocation,
    this.accommodationDescription,
    this.accommodationType,
    this.pricePerNight,
    this.imageUrl,
  });

  static T? _first<T>(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      if (m.containsKey(k) && m[k] != null) return m[k] as T?;
    }
    return null;
  }

  factory BookingItem.fromJson(Map<String, dynamic> m) {
    final idAny = _first<Object>(m, ['ID','id','bookingId','BookingId']);
    final idStr = idAny?.toString() ?? '';

    // date
    DateTime? date;
    final dRaw = _first<String>(m, ['bookingDate','BookingDate','date','createdAt']);
    if (dRaw != null) { try { date = DateTime.parse(dRaw); } catch (_) {} }

    final pr  = num.tryParse((_first<Object>(m, ['price','Price']) ?? 0).toString()) ?? 0;
    final fee = num.tryParse((_first<Object>(m, ['bookingFee','BookingFee']) ?? 0).toString()) ?? 0;

    final st  = bookingStatusFrom(_first<String>(m, ['status','Status']));

    // accommodation block
    int? accId = int.tryParse((_first<Object>(m, ['accommodationId','AccommodationId']) ?? '').toString());
    String? accName, accLoc, accDesc, accType, img;
    num? accPPN;

    final accRaw = _first<Map<String, dynamic>>(m, ['accommodation','Accommodation']);
    if (accRaw != null) {
      accId   = int.tryParse((accRaw['accommodationId'] ?? accRaw['id'] ?? accId ?? '').toString());
      accName = accRaw['name']?.toString();
      accLoc  = accRaw['location']?.toString();
      accDesc = accRaw['description']?.toString();
      accType = accRaw['accommodationType']?.toString();
      accPPN  = num.tryParse((accRaw['pricePerNight'] ?? '0').toString());
      img     = accRaw['image']?.toString() ?? accRaw['imageUrl']?.toString();
    }

    return BookingItem(
      id: idStr,
      bookingDate: date,
      price: pr,
      bookingFee: fee,
      status: st,
      accommodationId: accId,
      accommodationName: accName,
      accommodationLocation: accLoc,
      accommodationDescription: accDesc,
      accommodationType: accType,
      pricePerNight: accPPN,
      imageUrl: img,
    );
  }
}

class BookingCreatePayload {
  final int accommodationId;
  final String bookingDate; // "YYYY-MM-DD" or ISO date
  final num price;
  final num bookingFee;

  BookingCreatePayload({
    required this.accommodationId,
    required this.bookingDate,
    required this.price,
    required this.bookingFee,
  });

  Map<String, dynamic> toJson() => {
    'accommodationId': accommodationId,
    'bookingDate': bookingDate,
    'price': price,
    'bookingFee': bookingFee,
  };
}
