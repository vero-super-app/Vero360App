enum BookingStatus { pending, confirmed, cancelled, completed, unknown }

BookingStatus bookingStatusFrom(String? v) {
  var s = (v ?? '').toLowerCase().trim();
  if (s.isEmpty) return BookingStatus.unknown;
  // APIs often use snake_case or mixed labels
  s = s.replaceAll(RegExp(r'[\s_-]+'), '');

  switch (s) {
    case 'pending':
    case 'processing':
    case 'inprogress':
    case 'awaitingpayment':
    case 'awaiting_payment':
    case 'unpaid':
    case 'open':
      return BookingStatus.pending;
    case 'confirmed':
    case 'confirm':
    case 'active':
    case 'approved':
    case 'booked':
    case 'accepted':
      return BookingStatus.confirmed;
    case 'cancelled':
    case 'canceled':
    case 'declined':
    case 'failed':
    case 'rejected':
      return BookingStatus.cancelled;
    case 'completed':
    case 'complete':
    case 'done':
    case 'paid':
    case 'successful':
    case 'success':
    case 'succeeded': // Stripe / many payment APIs
    case 'settled':
    case 'captured':
      return BookingStatus.completed;
    default:
      return BookingStatus.unknown;
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

/// Guest PayChangu / notifications often use `vero…`; merchant UI + host alerts use **VERO** prefix.
String formatVeroAccommodationBookingRef(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return '';
  final lower = s.toLowerCase();
  if (lower.startsWith('vero')) {
    final rest = s.length > 4 ? s.substring(4).trim() : '';
    if (rest.isEmpty) return 'VERO';
    return 'VERO$rest';
  }
  return 'VERO$s';
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

  /// Guest / booker (merchant view); often nested as `user` / `guest` / `customer` in API JSON.
  final String? guestName;
  final String? guestEmail;
  final String? guestPhone;

  /// PayChangu / customer-facing ref when API sends it separately from numeric [id].
  final String? bookingNumber;

  /// Guest “My bookings” only lists rows where payment succeeded (or API marks paid).
  final bool includeInGuestMyBookings;

  /// Last night of stay is the day before checkout (checkout morning). Optional from API.
  final DateTime? checkOutDate;

  /// Length of stay in nights when API sends it; else inferred from checkout or price/ppn.
  final int? nights;

  num get total => price + bookingFee;

  /// Host **Total revenue** (gross MWK): paid/settled stays only — same bar as guest “My bookings”
  /// ([includeInGuestMyBookings]), plus **confirmed** / **completed** if the API omits payment flags.
  bool get countsTowardHostRevenue {
    if (status == BookingStatus.cancelled) return false;
    if (includeInGuestMyBookings) return true;
    return status == BookingStatus.confirmed || status == BookingStatus.completed;
  }

  /// Same ref style as guest “Stay booked” notification and host Firestore alerts.
  String get displayBookingRef {
    final human = bookingNumber?.trim();
    if (human != null && human.isNotEmpty) {
      return formatVeroAccommodationBookingRef(human);
    }
    return formatVeroAccommodationBookingRef(id);
  }

  /// Inclusive start / exclusive end in local calendar dates for slept nights.
  bool stayCoversCalendarDay(DateTime day, int accId) {
    if (!includeInGuestMyBookings) return false;
    if (accommodationId == null || accommodationId != accId) return false;
    final start = bookingDate;
    if (start == null) return false;
    final d = DateTime(day.year, day.month, day.day);
    final s = DateTime(start.year, start.month, start.day);
    if (d.isBefore(s)) return false;
    final endEx = _stayEndExclusiveLocal();
    return d.isBefore(endEx);
  }

  DateTime _stayEndExclusiveLocal() {
    final start = bookingDate!;
    final s = DateTime(start.year, start.month, start.day);
    if (checkOutDate != null) {
      final c = checkOutDate!;
      return DateTime(c.year, c.month, c.day);
    }
    return s.add(Duration(days: effectiveNights()));
  }

  int effectiveNights() {
    if (nights != null && nights! > 0) return nights!;
    if (checkOutDate != null && bookingDate != null) {
      final s = DateTime(bookingDate!.year, bookingDate!.month, bookingDate!.day);
      final c = DateTime(checkOutDate!.year, checkOutDate!.month, checkOutDate!.day);
      final diff = c.difference(s).inDays;
      return diff < 1 ? 1 : diff;
    }
    final ppn = pricePerNight;
    if (ppn != null && ppn > 0 && price > 0) {
      final inferred = (price / ppn).round();
      return inferred < 1 ? 1 : inferred;
    }
    return 1;
  }

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
    this.guestName,
    this.guestEmail,
    this.guestPhone,
    this.bookingNumber,
    this.includeInGuestMyBookings = false,
    this.checkOutDate,
    this.nights,
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

    DateTime? checkOut;
    final coRaw = _first<String>(m, [
      'checkOut',
      'checkOutDate',
      'checkout',
      'checkoutDate',
      'endDate',
      'departureDate',
      'check_out',
      'check_out_date',
    ]);
    if (coRaw != null) {
      try {
        checkOut = DateTime.parse(coRaw);
      } catch (_) {}
    }

    int? nightsCount;
    final nRaw = _first<Object>(m, [
      'nights',
      'numberOfNights',
      'nightCount',
      'totalNights',
      'numNights',
    ]);
    if (nRaw != null) {
      nightsCount = int.tryParse(nRaw.toString());
      if (nightsCount != null && nightsCount < 1) nightsCount = null;
    }

    final pr  = num.tryParse((_first<Object>(m, ['price','Price']) ?? 0).toString()) ?? 0;
    final fee = num.tryParse((_first<Object>(m, ['bookingFee','BookingFee']) ?? 0).toString()) ?? 0;

    // Prefer booking lifecycle fields for display; keep payment* separate for “paid?” checks.
    String? statusStr;
    final bookingStatusRaw = _first<Object>(m, [
      'status',
      'Status',
      'bookingStatus',
      'BookingStatus',
    ]);
    if (bookingStatusRaw != null) {
      statusStr =
          bookingStatusRaw is String ? bookingStatusRaw : bookingStatusRaw.toString();
    }
    if (statusStr == null || statusStr.trim().isEmpty) {
      final payOnly = _first<Object>(m, [
        'paymentStatus',
        'payment_status',
        'paymentState',
        'payment_state',
      ]);
      if (payOnly != null) {
        statusStr = payOnly is String ? payOnly : payOnly.toString();
      }
    }
    if ((statusStr == null || statusStr.trim().isEmpty) &&
        (m['paid'] == true || m['isPaid'] == true)) {
      statusStr = 'paid';
    }
    final st = bookingStatusFrom(statusStr);

    final guestPaidOk = _guestMyBookingsPaymentOk(m, st);

    const bookingRefKeys = [
      'bookingNumber',
      'BookingNumber',
      'reference',
      'Reference',
      'referenceNumber',
      'bookingRef',
      'BookingRef',
      'orderNumber',
      'OrderNumber',
      'transactionRef',
      'tx_ref',
      'txRef',
    ];
    Object? bnRaw = _first<Object>(m, bookingRefKeys);
    String? bookingNumberStr = _nonEmpty(bnRaw?.toString());
    if (bookingNumberStr == null) {
      for (final wrap in ['data', 'booking', 'Booking']) {
        final inner = m[wrap];
        if (inner is Map<String, dynamic>) {
          bnRaw = _first<Object>(inner, bookingRefKeys);
          bookingNumberStr = _nonEmpty(bnRaw?.toString());
          if (bookingNumberStr != null) break;
        }
      }
    }

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
    accName ??= _first<String>(m, ['accommodationName', 'propertyName', 'title']);
    accLoc ??= _first<String>(m, ['accommodationLocation', 'location']);

    var gName = _first<String>(m, [
      'guestName',
      'guest_name',
      'customerName',
      'customer_name',
      'bookerName',
      'booker_name',
      'clientName',
    ]);
    var gEmail = _first<String>(m, [
      'guestEmail',
      'guest_email',
      'customerEmail',
      'customer_email',
      'bookerEmail',
    ]);
    var gPhone = _first<String>(m, [
      'guestPhone',
      'guest_phone',
      'customerPhone',
      'bookerPhone',
      'phone',
    ]);

    final person = _first<Map<String, dynamic>>(m, [
      'user',
      'User',
      'guest',
      'Guest',
      'customer',
      'Customer',
      'bookedBy',
      'booked_by',
      'booker',
      'Booker',
      'client',
      'Client',
    ]);
    if (person != null) {
      gName ??= _displayNameFromPersonMap(person);
      gEmail ??= person['email']?.toString() ?? person['Email']?.toString();
      gPhone ??= person['phone']?.toString() ??
          person['phoneNumber']?.toString() ??
          person['mobile']?.toString() ??
          person['telephone']?.toString();
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
      guestName: _nonEmpty(gName),
      guestEmail: _nonEmpty(gEmail),
      guestPhone: _nonEmpty(gPhone),
      bookingNumber: bookingNumberStr,
      includeInGuestMyBookings: guestPaidOk,
      checkOutDate: checkOut,
      nights: nightsCount,
    );
  }

  /// True when this row should appear under the guest “My bookings” tab.
  ///
  /// Most backends set `status` to `confirmed` or `completed` after PayChangu/webhook,
  /// without a separate `paymentStatus` field — those must still appear here.
  /// Rows stay hidden while `pending` (created at POST /bookings before payment) unless
  /// the payload explicitly marks paid. **Price / pricePerNight are not payment proof.**
  static bool _guestMyBookingsPaymentOk(
    Map<String, dynamic> m,
    BookingStatus displayStatus,
  ) {
    if (displayStatus == BookingStatus.cancelled) return false;

    if (m['paid'] == true || m['isPaid'] == true) return true;

    final payRaw = _first<Object>(m, [
      'paymentStatus',
      'payment_status',
      'paymentState',
      'payment_state',
    ]);
    final payStr = payRaw?.toString().toLowerCase().trim() ?? '';
    if (payStr.isNotEmpty) {
      final payAsStatus = bookingStatusFrom(payStr);
      if (payAsStatus == BookingStatus.completed) return true;
      if (payAsStatus == BookingStatus.pending ||
          payStr.contains('unpaid') ||
          payStr.contains('await') ||
          payStr.contains('failed')) {
        return false;
      }
    }

    if (displayStatus == BookingStatus.completed) return true;

    if (displayStatus == BookingStatus.confirmed) return true;

    if (displayStatus == BookingStatus.pending) return false;

    if (displayStatus == BookingStatus.unknown) {
      return payStr.isNotEmpty &&
          bookingStatusFrom(payStr) == BookingStatus.completed;
    }
    return false;
  }

  static String? _nonEmpty(String? s) {
    final t = s?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }

  static String? _displayNameFromPersonMap(Map<String, dynamic> u) {
    final fn = u['firstName'] ?? u['first_name'];
    final ln = u['lastName'] ?? u['last_name'];
    if (fn != null || ln != null) {
      final combined = '${fn ?? ''} ${ln ?? ''}'.trim();
      if (combined.isNotEmpty) return combined;
    }
    for (final k in [
      'fullName',
      'displayName',
      'name',
      'username',
      'userName',
    ]) {
      final v = u[k];
      if (v != null && v.toString().trim().isNotEmpty) {
        return v.toString().trim();
      }
    }
    return null;
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
