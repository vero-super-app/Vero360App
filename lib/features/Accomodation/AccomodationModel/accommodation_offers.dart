import 'dart:typed_data';

import 'package:intl/intl.dart';

const int kAccommodationOfferPhotoLimit = 5;

List<String> _photoUrlsFromMap(Map<String, dynamic> m) {
  final urls = <String>[];
  void add(Object? raw) {
    final s = raw?.toString().trim() ?? '';
    if (s.isEmpty || urls.contains(s)) return;
    urls.add(s);
  }

  final many = m['images'] ?? m['photos'] ?? m['gallery'];
  if (many is List) {
    for (final item in many) {
      if (item is Map) {
        add(item['image'] ?? item['url'] ?? item['imageUrl']);
      } else {
        add(item);
      }
    }
  }
  add(m['image'] ?? m['imageUrl'] ?? m['photo'] ?? m['photoUrl']);
  if (urls.length > kAccommodationOfferPhotoLimit) {
    return urls.sublist(0, kAccommodationOfferPhotoLimit);
  }
  return urls;
}

/// One priced room type on a stay (Executive, Standard, …).
class AccommodationRoomOffer {
  final String name;
  final num price;
  final int quantity;
  final List<String> imageUrls;
  final List<Uint8List> localImages;
  final List<String> localFilenames;

  const AccommodationRoomOffer({
    required this.name,
    required this.price,
    this.quantity = 1,
    this.imageUrls = const [],
    this.localImages = const [],
    this.localFilenames = const [],
  });

  String? get imageUrl => imageUrls.isEmpty ? null : imageUrls.first;
  Uint8List? get imageBytes => localImages.isEmpty ? null : localImages.first;
  String? get imageFilename =>
      localFilenames.isEmpty ? null : localFilenames.first;

  bool get hasPhoto => imageUrls.isNotEmpty || localImages.isNotEmpty;

  Map<String, dynamic> toMap() => {
        'name': name,
        'price': price,
        'quantity': quantity < 1 ? 1 : quantity,
        if (imageUrls.isNotEmpty) 'image': imageUrls.first,
        if (imageUrls.isNotEmpty) 'images': imageUrls,
      };

  AccommodationRoomOffer copyWith({
    List<String>? imageUrls,
    bool clearLocalImage = false,
  }) {
    return AccommodationRoomOffer(
      name: name,
      price: price,
      quantity: quantity,
      imageUrls: imageUrls ?? this.imageUrls,
      localImages: clearLocalImage ? const [] : localImages,
      localFilenames: clearLocalImage ? const [] : localFilenames,
    );
  }

  static AccommodationRoomOffer? fromDynamic(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final name = (m['name'] ?? m['title'] ?? m['roomName'] ?? '')
        .toString()
        .trim();
    final price = num.tryParse(
          (m['price'] ?? m['pricePerNight'] ?? m['amount'] ?? '').toString(),
        ) ??
        0;
    final qtyRaw = m['quantity'] ?? m['count'] ?? m['rooms'] ?? 1;
    final qty = qtyRaw is num
        ? qtyRaw.toInt()
        : int.tryParse(qtyRaw.toString()) ?? 1;
    if (name.isEmpty || price <= 0) return null;
    return AccommodationRoomOffer(
      name: name,
      price: price,
      quantity: qty < 1 ? 1 : qty,
      imageUrls: _photoUrlsFromMap(m),
    );
  }
}

/// A bookable conference / meeting space at the property.
class AccommodationConferenceOffer {
  final String name;
  final num price;
  final int capacity;
  final List<String> imageUrls;
  final List<Uint8List> localImages;
  final List<String> localFilenames;

  const AccommodationConferenceOffer({
    required this.name,
    required this.price,
    this.capacity = 0,
    this.imageUrls = const [],
    this.localImages = const [],
    this.localFilenames = const [],
  });

  String? get imageUrl => imageUrls.isEmpty ? null : imageUrls.first;
  Uint8List? get imageBytes => localImages.isEmpty ? null : localImages.first;
  String? get imageFilename =>
      localFilenames.isEmpty ? null : localFilenames.first;

  bool get hasPhoto => imageUrls.isNotEmpty || localImages.isNotEmpty;

  Map<String, dynamic> toMap() => {
        'name': name,
        'price': price,
        if (capacity > 0) 'capacity': capacity,
        if (imageUrls.isNotEmpty) 'image': imageUrls.first,
        if (imageUrls.isNotEmpty) 'images': imageUrls,
      };

  AccommodationConferenceOffer copyWith({
    List<String>? imageUrls,
    bool clearLocalImage = false,
  }) {
    return AccommodationConferenceOffer(
      name: name,
      price: price,
      capacity: capacity,
      imageUrls: imageUrls ?? this.imageUrls,
      localImages: clearLocalImage ? const [] : localImages,
      localFilenames: clearLocalImage ? const [] : localFilenames,
    );
  }

  static AccommodationConferenceOffer? fromDynamic(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final name = (m['name'] ?? m['title'] ?? m['hallName'] ?? '')
        .toString()
        .trim();
    final price = num.tryParse(
          (m['price'] ?? m['amount'] ?? m['rate'] ?? '').toString(),
        ) ??
        0;
    final capRaw = m['capacity'] ?? m['seats'] ?? m['people'] ?? 0;
    final cap = capRaw is num
        ? capRaw.toInt()
        : int.tryParse(capRaw.toString()) ?? 0;
    if (name.isEmpty || price <= 0) return null;
    return AccommodationConferenceOffer(
      name: name,
      price: price,
      capacity: cap < 0 ? 0 : cap,
      imageUrls: _photoUrlsFromMap(m),
    );
  }
}

List<AccommodationRoomOffer> parseAccommodationRoomOffers(Object? raw) {
  if (raw is! List) return const [];
  final out = <AccommodationRoomOffer>[];
  for (final item in raw) {
    final offer = AccommodationRoomOffer.fromDynamic(item);
    if (offer != null) out.add(offer);
  }
  return out;
}

List<AccommodationConferenceOffer> parseAccommodationConferenceOffers(
  Object? raw,
) {
  if (raw is! List) return const [];
  final out = <AccommodationConferenceOffer>[];
  for (final item in raw) {
    final offer = AccommodationConferenceOffer.fromDynamic(item);
    if (offer != null) out.add(offer);
  }
  return out;
}

String formatAccommodationMwk(num amount) =>
    NumberFormat('#,##0').format(amount.round());
