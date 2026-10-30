import 'package:flutter_test/flutter_test.dart';

import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';

Map<String, dynamic> realCarJson() {
  return <String, dynamic>{
    'id': 42,
    'make': 'Toyota',
    'model': 'Corolla',
    'year': 2021,
    'color': 'White',
    'dailyRate': '45000.00',
    'currency': 'MWK',
    'isAvailable': true,
    'imageUrl': 'https://cdn.example.com/corolla.jpg',
    'images': <String>[],
    'description': 'Reliable sedan with air conditioning.',
    'seats': '5',
    'transmission': 'AUTOMATIC',
    'fuelType': 'PETROL',
    'bodyType': 'SEDAN',
    'pickupArea': 'Lilongwe',
    'latitude': '-13.96',
    'longitude': '33.78',
    'rating': '4.5',
    'reviews': '12',
    'listingStatus': 'PUBLISHED',
    'availableForDates': true,
    'depositAmount': '0.00',
    'minRentalDays': '1',
    'maxRentalDays': null,
  };
}

void main() {
  group('CarListing.fromJson', () {
    test('parses real backend JSON with decimal strings and make', () {
      final car = CarListing.fromJson(realCarJson());

      expect(car.id, 42);
      expect(car.make, 'Toyota');
      expect(car.model, 'Corolla');
      expect(car.title, 'Toyota Corolla');
      expect(car.year, 2021);
      expect(car.dailyRate, 45000.0);
      expect(car.currency, 'MWK');
      expect(car.isAvailable, isTrue);
      expect(car.seats, 5);
      expect(car.transmission, 'AUTOMATIC');
      expect(car.transmissionLabel, 'Automatic');
      expect(car.fuelLabel, 'Petrol');
      expect(car.bodyLabel, 'Sedan');
      expect(car.pickupArea, 'Lilongwe');
      expect(car.latitude, -13.96);
      expect(car.longitude, 33.78);
      expect(car.rating, 4.5);
      expect(car.reviews, 12);
      expect(car.listingStatus, ListingStatus.published);
      expect(car.availableForDates, isTrue);
      expect(car.depositAmount, 0.0);
      expect(car.minRentalDays, 1);
      expect(car.maxRentalDays, isNull);
      expect(car.isBookable, isTrue);
    });

    test('uses images[] before the imageUrl fallback', () {
      final car = CarListing.fromJson(<String, dynamic>{
        ...realCarJson(),
        'images': <String>['https://cdn.example.com/one.jpg', 'https://cdn.example.com/two.jpg'],
        'listingStatus': 'published',
        'availableForDates': false,
      });

      expect(car.galleryImages, <String>[
        'https://cdn.example.com/one.jpg',
        'https://cdn.example.com/two.jpg',
      ]);
      expect(car.primaryImage, 'https://cdn.example.com/one.jpg');
      expect(car.availabilityLabel, 'Not available for these dates');
    });

    test('falls back to imageUrl when images[] is empty', () {
      final car = CarListing.fromJson(realCarJson());

      expect(car.galleryImages, <String>[
        'https://cdn.example.com/corolla.jpg',
      ]);
    });

    test('tolerates missing optional fields and legacy brand', () {
      final car = CarListing.fromJson(<String, dynamic>{
        'id': '7',
        'brand': 'Nissan',
        'model': 'Note',
      });

      expect(car.id, 7);
      expect(car.make, 'Nissan');
      expect(car.title, 'Nissan Note');
      expect(car.dailyRate, 0);
      expect(car.seats, isNull);
      expect(car.description, isNull);
      expect(car.images, isEmpty);
      expect(car.galleryImages, isEmpty);
      expect(car.maxRentalDays, isNull);
      expect(car.currency, 'MWK');
      expect(car.minRentalDays, 1);
      expect(car.listingStatus, ListingStatus.published);
      expect(car.availableForDates, isNull);
    });

    test('prefers make over a legacy brand value', () {
      final car = CarListing.fromJson(<String, dynamic>{
        'id': 1,
        'make': 'Toyota',
        'brand': 'Legacy Brand',
        'model': 'Vitz',
      });

      expect(car.make, 'Toyota');
      expect(car.title, 'Toyota Vitz');
    });

    test('parses the providing company', () {
      final car = CarListing.fromJson(<String, dynamic>{
        'id': 3,
        'make': 'Toyota',
        'model': 'Hilux',
        'operator': {
          'id': 'op-1',
          'name': 'Lilongwe Car Rentals',
          'type': 'BUSINESS',
          'logoUrl': null,
        },
      });

      expect(car.provider?.name, 'Lilongwe Car Rentals');
      expect(car.provider?.isBusiness, isTrue);
      expect(car.providerLabel, 'Provided by Lilongwe Car Rentals');
    });

    test('has no provider when the backend omits it', () {
      final car = CarListing.fromJson(<String, dynamic>{'id': 4, 'operator': null});
      expect(car.provider, isNull);
      expect(car.providerLabel, isEmpty);
    });

    test('shows units left only for multi-unit listings', () {
      final multi = CarListing.fromJson(<String, dynamic>{
        'id': 5,
        'listingId': 'grp-1',
        'unitCount': 4,
        'availableUnits': 3,
      });
      expect(multi.listingId, 'grp-1');
      expect(multi.unitsLeftLabel, '3 left');

      final single = CarListing.fromJson(<String, dynamic>{
        'id': 6,
        'unitCount': 1,
        'availableUnits': 1,
      });
      expect(single.unitsLeftLabel, isNull);
    });

    test('parses the pickup branch and booking mode', () {
      final car = CarListing.fromJson(<String, dynamic>{
        'id': 7,
        'instantBook': false,
        'location': {'id': 'b1', 'name': 'Airport desk', 'address': 'KIA'},
      });
      expect(car.branchLabel, 'Airport desk, KIA');
      expect(car.instantBook, isFalse);
      expect(car.bookingModeLabel, contains('24h'));

      final plain = CarListing.fromJson(<String, dynamic>{'id': 8});
      expect(plain.branchLabel, isNull);
      expect(plain.instantBook, isTrue);
    });
  });

  group('RentalQuote.fromJson', () {
    Map<String, dynamic> quoteJson() {
      return <String, dynamic>{
        'quoteId': 'quote-1',
        'carId': '42',
        'currency': 'MWK',
        'startAt': '2026-11-03T07:00:00.000Z',
        'endAt': '2026-11-06T15:00:00.000Z',
        'expiresAt': '2099-10-18T15:45:00.000Z',
        'days': '4',
        'dailyRate': '45000.00',
        'lineItems': <Map<String, dynamic>>[
          <String, dynamic>{
            'code': 'rental_base',
            'label': 'Vehicle hire (4 days)',
            'amount': '180000.00',
          },
          <String, dynamic>{
            'code': 'delivery',
            'label': 'Pickup delivery',
            'amount': 0,
          },
        ],
        'subtotal': '180000.00',
        'surcharges': '0.00',
        'discounts': '0.00',
        'insurance': '15000.00',
        'deposit': <String, dynamic>{
          'amount': '50000.00',
          'collectionMode': 'cash',
        },
        'totalDueNow': '180000.00',
        'totalDueLater': '15000.00',
        'total': '195000.00',
        'status': 'ACTIVE',
      };
    }

    test('parses line items, deposit and server totals', () {
      final quote = RentalQuote.fromJson(quoteJson());

      expect(quote.quoteId, 'quote-1');
      expect(quote.carId, 42);
      expect(quote.currency, 'MWK');
      expect(quote.startAt!.toUtc(), DateTime.utc(2026, 11, 3, 7));
      expect(quote.endAt!.toUtc(), DateTime.utc(2026, 11, 6, 15));
      expect(quote.days, 4);
      expect(quote.dailyRate, 45000.0);
      expect(quote.lineItems, hasLength(2));
      expect(quote.lineItems.first.code, 'rental_base');
      expect(quote.lineItems.first.label, 'Vehicle hire (4 days)');
      expect(quote.lineItems.first.amount, 180000.0);
      expect(quote.lineItems.last.amount, 0.0);
      expect(quote.subtotal, 180000.0);
      expect(quote.insurance, 15000.0);
      expect(quote.deposit.amount, 50000.0);
      expect(quote.deposit.collectionMode, 'cash');
      expect(quote.deposit.hasDeposit, isTrue);
      expect(quote.deposit.collectionModeLabel, 'Cash');
      expect(quote.totalDueNow, 180000.0);
      expect(quote.totalDueLater, 15000.0);
      expect(quote.total, 195000.0);
      expect(quote.status, QuoteStatus.active);
      expect(quote.isExpired, isFalse);
      expect(quote.isActive, isTrue);
    });

    test('unwraps a data envelope and defaults a missing deposit', () {
      final quote = RentalQuote.fromJson(<String, dynamic>{
        'data': <String, dynamic>{
          ...quoteJson(),
          'deposit': null,
          'status': 'consumed',
        },
      });

      expect(quote.quoteId, 'quote-1');
      expect(quote.deposit.amount, 0);
      expect(quote.deposit.hasDeposit, isFalse);
      expect(quote.status, QuoteStatus.consumed);
    });

    test('detects an expired quote', () {
      final quote = RentalQuote.fromJson(<String, dynamic>{
        ...quoteJson(),
        'expiresAt': '2020-01-01T00:00:00.000Z',
      });

      expect(quote.isLocallyExpired, isTrue);
      expect(quote.isExpired, isTrue);
      expect(quote.isActive, isFalse);
    });

    test('accepts legacy startDate/endDate aliases', () {
      final quote = RentalQuote.fromJson(<String, dynamic>{
        ...quoteJson(),
        'startAt': null,
        'endAt': null,
        'startDate': '2026-11-03T07:00:00.000Z',
        'endDate': '2026-11-06T15:00:00.000Z',
      });

      expect(quote.startAt!.toUtc(), DateTime.utc(2026, 11, 3, 7));
      expect(quote.endAt!.toUtc(), DateTime.utc(2026, 11, 6, 15));
    });
  });

  group('CarHireBooking.fromJson', () {
    test('parses the assigned unit plate when present', () {
      final booking = CarHireBooking.fromJson(<String, dynamic>{
        'id': 80,
        'assignedUnit': {'carId': 12, 'licensePlate': 'BZ 1234', 'color': 'White'},
      });
      expect(booking.assignedPlate, 'BZ 1234');
      expect(booking.assignedColor, 'White');
      expect(CarHireBooking.fromJson(<String, dynamic>{'id': 81}).assignedPlate, isNull);
    });

    test('blocks payment while a request awaits the company', () {
      final waiting = CarHireBooking.fromJson(<String, dynamic>{
        'id': 82,
        'bookingStatus': 'PENDING',
        'paymentStatus': 'NOT_STARTED',
        'nextAction': 'AWAITING_PROVIDER',
      });
      expect(waiting.canPay, isFalse);
      expect(waiting.nextActionLabel, contains('24 hours'));

      final accepted = CarHireBooking.fromJson(<String, dynamic>{
        'id': 83,
        'bookingStatus': 'CONFIRMED',
        'paymentStatus': 'NOT_STARTED',
        'nextAction': 'PAYMENT_REQUIRED',
      });
      expect(accepted.canPay, isTrue);
    });

    Map<String, dynamic> bookingJson() {
      return <String, dynamic>{
        'id': 77,
        'bookingNumber': 'VCH-000077',
        'carId': '42',
        'userId': 9,
        'startAt': '2026-11-03T07:00:00.000Z',
        'endAt': '2026-11-06T15:00:00.000Z',
        // Legacy alias present with a different value: camelCase must win.
        'startDate': '2026-11-01T07:00:00.000Z',
        'endDate': '2026-11-02T15:00:00.000Z',
        'bookingStatus': 'confirmed',
        'status': 'PENDING',
        'paymentStatus': 'SUCCEEDED',
        'currency': 'MWK',
        'quoteId': 'quote-1',
        'baseCost': '180000.00',
        'distanceCost': '0.00',
        'surcharges': '0.00',
        'discounts': '0.00',
        'insurance': '15000.00',
        // `total` intentionally missing to exercise the `totalCost` alias.
        'totalCost': '195000.00',
        'renterNotes': 'Call on arrival',
        'driverName': 'Maya Tembo',
        'holdExpiresAt': '2026-10-18T15:45:00.000Z',
        'cancellationReason': null,
        'cancelledAt': null,
        'nextAction': 'PICKUP_DUE',
        'car': realCarJson(),
      };
    }

    test('parses uppercase statuses, aliases and the nested car', () {
      final booking = CarHireBooking.fromJson(bookingJson());

      expect(booking.id, 77);
      expect(booking.bookingNumber, 'VCH-000077');
      expect(booking.bookingNumberLabel, 'VCH-000077');
      expect(booking.carId, 42);
      expect(booking.userId, 9);
      expect(booking.startAt!.toUtc(), DateTime.utc(2026, 11, 3, 7));
      expect(booking.endAt!.toUtc(), DateTime.utc(2026, 11, 6, 15));
      expect(booking.bookingStatus, BookingStatus.confirmed);
      expect(booking.paymentStatus, PaymentStatus.succeeded);
      expect(booking.paymentSucceeded, isTrue);
      expect(booking.paymentLabel, 'Payment received');
      expect(booking.currency, 'MWK');
      expect(booking.quoteId, 'quote-1');
      expect(booking.baseCost, 180000.0);
      expect(booking.insurance, 15000.0);
      expect(booking.total, 195000.0);
      expect(booking.renterNotes, 'Call on arrival');
      expect(booking.driverName, 'Maya Tembo');
      expect(booking.holdExpiresAt!.toUtc(), DateTime.utc(2026, 10, 18, 15, 45));
      expect(booking.nextAction, 'PICKUP_DUE');
      expect(booking.nextActionLabel, isNotNull);
      expect(booking.car, isNotNull);
      expect(booking.car!.title, 'Toyota Corolla');
      expect(booking.car!.make, 'Toyota');
      // The public model has no registration-plate field at all.
      expect(booking.car!.galleryImages, isNotEmpty);
      expect(booking.canCancel, isTrue);
      expect(booking.canPay, isFalse);
    });

    test('tolerates missing optional fields and legacy status/date keys', () {
      final booking = CarHireBooking.fromJson(<String, dynamic>{
        'id': '78',
        'status': 'pending',
        'startDate': '2026-11-03T07:00:00.000Z',
        'endDate': '2026-11-06T15:00:00.000Z',
      });

      expect(booking.id, 78);
      expect(booking.bookingNumber, isNull);
      expect(booking.bookingNumberLabel, 'Booking #78');
      expect(booking.startAt!.toUtc(), DateTime.utc(2026, 11, 3, 7));
      expect(booking.endAt!.toUtc(), DateTime.utc(2026, 11, 6, 15));
      expect(booking.bookingStatus, BookingStatus.pending);
      expect(booking.paymentStatus, PaymentStatus.notStarted);
      expect(booking.total, 0);
      expect(booking.car, isNull);
      expect(booking.holdExpiresAt, isNull);
      expect(booking.isHoldExpired, isFalse);
      expect(booking.canCancel, isTrue);
      expect(booking.canPay, isTrue);
      expect(booking.driverName, isNull);
      expect(booking.renterNotes, isNull);
    });

    test('parses incident and unknown statuses safely', () {
      final incident = CarHireBooking.fromJson(<String, dynamic>{
        'id': 1,
        'bookingStatus': 'incident_reported',
      });
      final unknown = CarHireBooking.fromJson(<String, dynamic>{
        'id': 2,
        'bookingStatus': 'SOMETHING_NEW',
      });

      expect(incident.bookingStatus, BookingStatus.incidentReported);
      expect(incident.bookingStatus.label, 'Incident reported');
      expect(unknown.bookingStatus, BookingStatus.unknown);
    });

    test('parses a priceBreakdown line-item snapshot', () {
      final booking = CarHireBooking.fromJson(<String, dynamic>{
        ...bookingJson(),
        'priceBreakdown': <Map<String, dynamic>>[
          <String, dynamic>{
            'code': 'rental_base',
            'label': 'Vehicle hire (4 days)',
            'amount': '180000.00',
          },
        ],
      });

      expect(booking.priceBreakdown, hasLength(1));
      expect(booking.priceBreakdown.first.amount, 180000.0);
    });
  });

  group('BookingPage.fromJson', () {
    test('parses the data + meta envelope with string meta values', () {
      final page = BookingPage.fromJson(<String, dynamic>{
        'data': <Map<String, dynamic>>[
          <String, dynamic>{'id': 1, 'status': 'PENDING'},
          <String, dynamic>{'id': 2, 'status': 'CONFIRMED'},
        ],
        'meta': <String, dynamic>{
          'page': '1',
          'limit': '20',
          'total': '2',
          'hasMore': false,
        },
      });

      expect(page.data, hasLength(2));
      expect(page.data.first.bookingStatus, BookingStatus.pending);
      expect(page.data.last.bookingStatus, BookingStatus.confirmed);
      expect(page.page, 1);
      expect(page.limit, 20);
      expect(page.total, 2);
      expect(page.hasMore, isFalse);
    });

    test('accepts a plain array fallback', () {
      final page = BookingPage.fromJson(<Map<String, dynamic>>[
        <String, dynamic>{'id': 3, 'status': 'CANCELLED'},
      ]);

      expect(page.data, hasLength(1));
      expect(page.total, 1);
      expect(page.data.first.bookingStatus, BookingStatus.cancelled);
    });
  });

  group('CarHireSearchResult.fromJson', () {
    test('parses data + meta and decimal listing values', () {
      final result = CarHireSearchResult.fromJson(<String, dynamic>{
        'data': <Map<String, dynamic>>[realCarJson()],
        'meta': <String, dynamic>{
          'page': 1,
          'limit': 20,
          'total': 12,
          'hasMore': false,
        },
      });

      expect(result.data, hasLength(1));
      expect(result.data.first.dailyRate, 45000.0);
      expect(result.total, 12);
      expect(result.hasMore, isFalse);
    });

    test('accepts a plain array fallback', () {
      final result = CarHireSearchResult.fromJson(<Map<String, dynamic>>[
        realCarJson(),
      ]);

      expect(result.data, hasLength(1));
      expect(result.total, 1);
    });
  });

  group('PaymentInitiation.fromJson', () {
    test('parses the checkout response and nested booking', () {
      final payment = PaymentInitiation.fromJson(<String, dynamic>{
        'paymentId': 123,
        'txRef': 'tx-1',
        'checkoutUrl': 'https://example.com/checkout/abc',
        'status': 'INITIATED',
        'booking': <String, dynamic>{
          'id': 77,
          'bookingStatus': 'PENDING',
          'paymentStatus': 'PENDING',
        },
      });

      expect(payment.paymentId, 123);
      expect(payment.txRef, 'tx-1');
      expect(payment.checkoutUrl, 'https://example.com/checkout/abc');
      expect(payment.status, 'INITIATED');
      expect(payment.booking, isNotNull);
      expect(payment.booking!.bookingStatus, BookingStatus.pending);
      expect(payment.booking!.paymentStatus, PaymentStatus.pending);
    });

    test('treats a PawaPay deposit id as the transaction reference', () {
      final payment = PaymentInitiation.fromJson(<String, dynamic>{
        'paymentId': 9,
        'depositId': 'dep-77',
        'provider': 'pawapay',
        'status': 'SUCCEEDED',
      });

      expect(payment.txRef, 'dep-77');
      expect(payment.provider, 'pawapay');
      expect(payment.status, 'SUCCEEDED');
      expect(payment.checkoutUrl, isNull);
    });
  });

  group('CarHireVerification.fromJson', () {
    test('parses status, requirements and next action', () {
      final verification = CarHireVerification.fromJson(<String, dynamic>{
        'status': 'NOT_STARTED',
        'requirements': <String>['drivers_licence', 'phone'],
        'nextAction': 'Complete driver verification',
      });

      expect(verification.status, VerificationState.notStarted);
      expect(verification.requirements, hasLength(2));
      expect(verification.nextAction, 'Complete driver verification');
      expect(verification.needsAttention, isFalse);
    });
  });
}
